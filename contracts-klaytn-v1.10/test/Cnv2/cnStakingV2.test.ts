import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import {
  FuncID,
  RequestState,
  WithdrawalState,
  augmentChai,
  nowTime,
  getBalance,
  setTime,
  toPeb,
  toBytes32,
  jumpTime,
  onlyAdminFail,
  notNullFail,
  notConfirmedRequestFail,
  beforeInitFail,
  afterInitFail,
  checkRequestInfo,
} from "../../helpers/utils";
import { ethers } from "hardhat";
import { cnV2UnitTestFixture } from "../materials";
import { ZeroAddress } from "ethers";

// const RAND_ADDR = "0xe3B0C44298FC1C149AfBF4C8996fb92427aE41E4"; // non-null placeholder
const DAY = 24 * 60 * 60;
const WEEK = 7 * DAY;

type UnPromisify<T> = T extends Promise<infer U> ? U : T;

/**
 * @dev This unit test is for CnStakingV2.sol
 * 1. Test initializing process
 *    - Check constructor
 *    - Check constants
 *    - Check all initializing functions
 * 2. Test afterInit condition of all multisig functions
 * 3. Test submit/confirm functions not related to stake
 *    Test case about revokeConfirmation by proposer and confirmRequest
 *    will only be tested in addAdmin case
 *    - addAdmin
 *    - deleteAdmin
 *    - updateRequirement
 *    - clearRequest
 *    - updateStakingTracker
 *    - updateVoterAddress
 *    - updateRewardAddress
 * 4. Test lockup stakes
 *    - withdrawLockupStaking
 * 5. Test free stakes
 *    - stakeKlay
 *    - approveStakingWithdrawal
 *    - cancelApprovedStakingWithdrawal
 */
describe("CnStakingV2", function () {
  let fixture: UnPromisify<ReturnType<typeof cnV2UnitTestFixture>>;
  beforeEach(async function () {
    augmentChai();
    fixture = await loadFixture(cnV2UnitTestFixture);
  });
  async function initialize() {
    const { contractValidator, adminList, stakingTrackerMockReceiver, cnStakingV2, gcId } = fixture;

    await expect(cnStakingV2.connect(adminList[0]).setStakingTracker(stakingTrackerMockReceiver.target)).to.emit(
      cnStakingV2,
      "UpdateStakingTracker",
    );

    await expect(cnStakingV2.connect(adminList[0]).setGCId(gcId)).to.emit(cnStakingV2, "UpdateGCId");

    await cnStakingV2.connect(contractValidator).reviewInitialConditions();
    for (let i = 0; i < adminList.length; i++) {
      await cnStakingV2.connect(adminList[i]).reviewInitialConditions();
    }

    await expect(cnStakingV2.connect(adminList[0]).depositLockupStakingAndInit({ value: toPeb(600n) })).to.emit(
      cnStakingV2,
      "DepositLockupStakingAndInit",
    );
  }

  // 1. Test initializing process
  describe("CnStakingV2 Initialize", function () {
    async function initializeBeforeDeposit(opt: boolean) {
      const { contractValidator, adminList, stakingTrackerMockReceiver, cnStakingV2, gcId } = fixture;
      // Setup initialization
      if (opt) {
        await expect(cnStakingV2.connect(adminList[0]).setStakingTracker(stakingTrackerMockReceiver.target)).to.emit(
          cnStakingV2,
          "UpdateStakingTracker",
        );
      }

      await expect(cnStakingV2.connect(adminList[0]).setGCId(gcId)).to.emit(cnStakingV2, "UpdateGCId");

      await cnStakingV2.connect(contractValidator).reviewInitialConditions();
      for (let i = 0; i < adminList.length; i++) {
        await cnStakingV2.connect(adminList[i]).reviewInitialConditions();
      }
    }
    it("Check constructor", async function () {
      const { contractValidator, adminList, nodeId, rewardAddr, requirement, cnStakingV2 } = fixture;

      expect(await cnStakingV2.contractValidator()).to.equal(contractValidator.address);
      expect(await cnStakingV2.adminList(0)).to.equal(adminList[0].address);
      expect(await cnStakingV2.adminList(1)).to.equal(adminList[1].address);
      expect(await cnStakingV2.adminList(2)).to.equal(adminList[2].address);
      expect(await cnStakingV2.requirement()).to.equal(requirement);
      expect(await cnStakingV2.nodeId()).to.equal(nodeId.address);
      expect(await cnStakingV2.rewardAddress()).to.equal(rewardAddr.address);
    });

    it("Check constants", async function () {
      const { cnStakingV2, addressBook } = fixture;

      expect(await cnStakingV2.MAX_ADMIN()).to.equal(50);
      expect(await cnStakingV2.CONTRACT_TYPE()).to.equal("CnStakingContract");
      expect(await cnStakingV2.VERSION()).to.equal(2);
      expect(await cnStakingV2.ADDRESS_BOOK_ADDRESS()).to.equal(addressBook.target);
      expect(await cnStakingV2.STAKE_LOCKUP()).to.equal(WEEK);
    });

    describe("Check initializing process #setStakingTracker", function () {
      it("#setStakingTracker: Wrong msg.sender", async function () {
        const { other1, cnStakingV2, stakingTrackerMockReceiver } = fixture;

        const setStakingTrackerTx = cnStakingV2.connect(other1).setStakingTracker(stakingTrackerMockReceiver.target);
        await onlyAdminFail(setStakingTrackerTx);
      });
      it("#setStakingTracker: Tracker address can't be zero address", async function () {
        const { adminList, cnStakingV2 } = fixture;

        const setStakingTrackerTx = cnStakingV2.connect(adminList[0]).setStakingTracker(ZeroAddress);
        await notNullFail(setStakingTrackerTx);
      });
      it("#setStakingTracker: Tracker address can't be set after initialization", async function () {
        const { adminList, cnStakingV2 } = fixture;

        await initializeBeforeDeposit(false);

        await expect(cnStakingV2.connect(adminList[0]).depositLockupStakingAndInit({ value: toPeb(600n) })).to.emit(
          cnStakingV2,
          "DepositLockupStakingAndInit",
        );

        const setStakingTrackerTx = cnStakingV2.connect(adminList[0]).setStakingTracker(ZeroAddress);
        await beforeInitFail(setStakingTrackerTx);
      });
      it("#setStakingTracker: Wrong tracker contract", async function () {
        const { adminList, cnStakingV2, stakingTrackerMockWrong } = fixture;

        await expect(
          cnStakingV2.connect(adminList[0]).setStakingTracker(stakingTrackerMockWrong.target),
        ).to.be.revertedWith("Invalid contract");
      });
      it("#setStakingTracker: Successfully set staking tracker", async function () {
        const { adminList, cnStakingV2, stakingTrackerMockReceiver } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).setStakingTracker(stakingTrackerMockReceiver.target)).to.emit(
          cnStakingV2,
          "UpdateStakingTracker",
        );

        expect(await cnStakingV2.stakingTracker()).to.equal(stakingTrackerMockReceiver.target);
      });
    });
    describe("Check initializing process #setGCId", function () {
      it("#setGCId: Wrong msg.sender", async function () {
        const { other1, cnStakingV2, gcId } = fixture;

        const setGCIdTx = cnStakingV2.connect(other1).setGCId(gcId);
        await onlyAdminFail(setGCIdTx);
      });
      it("#setGCId: GC ID can't be zero", async function () {
        const { adminList, cnStakingV2 } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).setGCId(0)).to.be.revertedWith("GC ID cannot be zero");
      });
      it("#setGCId: GCId can't be set after initialization", async function () {
        const { adminList, cnStakingV2, gcId } = fixture;

        await initializeBeforeDeposit(true);

        await expect(cnStakingV2.connect(adminList[0]).depositLockupStakingAndInit({ value: toPeb(600n) })).to.emit(
          cnStakingV2,
          "DepositLockupStakingAndInit",
        );

        const setGCIdTx = cnStakingV2.connect(adminList[0]).setGCId(gcId);
        await beforeInitFail(setGCIdTx);
      });
      it("#setGCId: Successfully set GCId", async function () {
        const { adminList, cnStakingV2, gcId } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).setGCId(gcId)).to.emit(cnStakingV2, "UpdateGCId");
        expect(await cnStakingV2.gcId()).to.equal(gcId);
      });
    });
    describe("Check initializing process #reviewInitialConditions", function () {
      it("#reviewInitialConditions: Wrong msg.sender", async function () {
        const { other1, cnStakingV2 } = fixture;

        const reviewInitialConditionsTx = cnStakingV2.connect(other1).reviewInitialConditions();
        await onlyAdminFail(reviewInitialConditionsTx);
      });
      it("#reviewInitialConditions: Admin can review only once", async function () {
        const { adminList, cnStakingV2 } = fixture;

        // First review
        await expect(cnStakingV2.connect(adminList[0]).reviewInitialConditions()).to.emit(
          cnStakingV2,
          "ReviewInitialConditions",
        );

        // Second review by same admin - fail
        await expect(cnStakingV2.connect(adminList[0]).reviewInitialConditions()).to.be.revertedWith(
          "Msg.sender already reviewed.",
        );
      });
      it("#reviewInitialConditions: Can't review after initialization", async function () {
        const { adminList, cnStakingV2 } = fixture;

        await initializeBeforeDeposit(true);

        await expect(cnStakingV2.connect(adminList[0]).depositLockupStakingAndInit({ value: toPeb(600n) })).to.emit(
          cnStakingV2,
          "DepositLockupStakingAndInit",
        );

        const reviewInitialConditionsTx = cnStakingV2.connect(adminList[0]).reviewInitialConditions();
        await beforeInitFail(reviewInitialConditionsTx);
      });
      it("#reviewInitialConditions: Successfully review initial conditions", async function () {
        const { contractValidator, adminList, cnStakingV2, stakingTrackerMockReceiver, gcId } = fixture;

        // Setup initialization
        await expect(cnStakingV2.connect(adminList[0]).setStakingTracker(stakingTrackerMockReceiver.target)).to.emit(
          cnStakingV2,
          "UpdateStakingTracker",
        );

        await expect(cnStakingV2.connect(adminList[0]).setGCId(gcId)).to.emit(cnStakingV2, "UpdateGCId");

        await expect(cnStakingV2.connect(contractValidator).reviewInitialConditions()).to.emit(
          cnStakingV2,
          "ReviewInitialConditions",
        );
        for (let i = 0; i < adminList.length - 1; i++) {
          await expect(cnStakingV2.connect(adminList[i]).reviewInitialConditions()).to.emit(
            cnStakingV2,
            "ReviewInitialConditions",
          );
        }

        await expect(cnStakingV2.connect(adminList[adminList.length - 1]).reviewInitialConditions()).to.emit(
          cnStakingV2,
          "CompleteReviewInitialConditions",
        );

        expect((await cnStakingV2.lockupConditions()).allReviewed).to.equal(true);
        expect((await cnStakingV2.lockupConditions()).reviewedCount).to.equal(4);

        // Get reviewers
        const reviewers = await cnStakingV2.getReviewers();
        expect(reviewers).to.equalAddrList([contractValidator.address, ...adminList.map((x) => x.address)]);
      });
    });
    describe("Check initializing process #depositLockupStakingAndInit", function () {
      it("#depositLockupStakingAndInit: Can't deposit before setting GC Id", async function () {
        const { contractValidator, adminList, cnStakingV2, stakingTrackerMockReceiver } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).setStakingTracker(stakingTrackerMockReceiver.target)).to.emit(
          cnStakingV2,
          "UpdateStakingTracker",
        );

        await cnStakingV2.connect(contractValidator).reviewInitialConditions();
        for (let i = 0; i < adminList.length; i++) {
          await cnStakingV2.connect(adminList[i]).reviewInitialConditions();
        }

        await expect(
          cnStakingV2.connect(adminList[0]).depositLockupStakingAndInit({ value: toPeb(600n) }),
        ).to.be.revertedWith("GC ID cannot be zero");
      });
      it("#depositLockupStakingAndInit: Can't deposit before allReviewed", async function () {
        const { adminList, cnStakingV2, stakingTrackerMockReceiver, gcId } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).setStakingTracker(stakingTrackerMockReceiver.target)).to.emit(
          cnStakingV2,
          "UpdateStakingTracker",
        );
        await expect(cnStakingV2.connect(adminList[0]).setGCId(gcId)).to.emit(cnStakingV2, "UpdateGCId");

        // contractValidator doesn't review the initial condition, which means allReviewed is false
        // await cnStakingV2.connect(contractValidator).reviewInitialConditions();
        for (let i = 0; i < adminList.length; i++) {
          await cnStakingV2.connect(adminList[i]).reviewInitialConditions();
        }

        await expect(
          cnStakingV2.connect(adminList[0]).depositLockupStakingAndInit({ value: toPeb(600n) }),
        ).to.be.revertedWith("Reviewing is not finished.");
      });
      it("#depositLockupStakingAndInit: Msg.value should be equal to unlockAmount", async function () {
        const { adminList, cnStakingV2 } = fixture;

        await initializeBeforeDeposit(true);

        await expect(
          cnStakingV2.connect(adminList[0]).depositLockupStakingAndInit({ value: toPeb(500n) }),
        ).to.be.revertedWith("Value does not match.");
      });
      it("#depositLockupStakingAndInit: Successfully deposit and initialize contract", async function () {
        const {
          contractValidator,
          adminList,
          unLockTimes,
          unLockAmounts,
          cnStakingV2,
          nodeId,
          rewardAddr,
          requirement,
        } = fixture;

        await initializeBeforeDeposit(true);

        await expect(cnStakingV2.connect(adminList[0]).depositLockupStakingAndInit({ value: toPeb(600n) })).to.emit(
          cnStakingV2,
          "DepositLockupStakingAndInit",
        );

        expect(await cnStakingV2.isAdmin(contractValidator.address)).to.equal(false);
        expect(await cnStakingV2.initialLockupStaking()).to.equal(toPeb(600n));
        expect(await cnStakingV2.remainingLockupStaking()).to.equal(toPeb(600n));
        expect(await getBalance(await cnStakingV2.getAddress())).to.equal(toPeb(600n));

        const state = await cnStakingV2.getState();
        expect(state[0]).to.equal(ZeroAddress);
        expect(state[1]).to.equal(nodeId.address);
        expect(state[2]).to.equal(rewardAddr.address);
        expect(state[3]).to.equalAddrList(adminList.map((x) => x.address));
        expect(state[4]).to.equal(requirement);
        expect(state[5]).to.equalNumberList(unLockTimes);
        expect(state[6]).to.equalNumberList(unLockAmounts);
        expect(state[7]).to.equal(true);
        expect(state[8]).to.equal(true);
      });
    });
  });

  // 2. Test afterInit condition of all multisig functions
  describe("Check afterInit condition of all multisig functions", function () {
    it("#AddAdmin", async function () {
      const { adminList, cnStakingV2, other1 } = fixture;

      const submitAddAdminTx = cnStakingV2.connect(adminList[0]).submitAddAdmin(other1.address);
      await afterInitFail(submitAddAdminTx);
    });
    it("#DeleteAdmin", async function () {
      const { adminList, cnStakingV2 } = fixture;

      const submitDeleteAdminTx = cnStakingV2.connect(adminList[0]).submitDeleteAdmin(adminList[2].address);
      await afterInitFail(submitDeleteAdminTx);
    });
    it("#UpdateRequirement", async function () {
      const { adminList, cnStakingV2 } = fixture;

      const submitUpdateRequirement = cnStakingV2.connect(adminList[0]).submitUpdateRequirement(3);
      await afterInitFail(submitUpdateRequirement);
    });
    it("#ClearRequest", async function () {
      const { adminList, cnStakingV2 } = fixture;

      const submitClearRequestTx = cnStakingV2.connect(adminList[0]).submitClearRequest();
      await afterInitFail(submitClearRequestTx);
    });
    it("#UpdateStakingTracker", async function () {
      const { adminList, cnStakingV2, other1 } = fixture;

      const submitUpdateStakingTrackerTx = cnStakingV2.connect(adminList[0]).submitUpdateStakingTracker(other1.address);
      await afterInitFail(submitUpdateStakingTrackerTx);
    });
    it("#UpdateVoterAddress", async function () {
      const { adminList, cnStakingV2, other1 } = fixture;

      const submitUpdateVoterAddressTx = cnStakingV2.connect(adminList[0]).submitUpdateVoterAddress(other1.address);
      await afterInitFail(submitUpdateVoterAddressTx);
    });
    it("#UpdateRewardAddress", async function () {
      const { adminList, cnStakingV2, other1 } = fixture;

      const submitUpdateRewardAddressTx = cnStakingV2.connect(adminList[0]).submitUpdateRewardAddress(other1.address);
      await afterInitFail(submitUpdateRewardAddressTx);
    });
    it("#WithdrawLockupStaking", async function () {
      const { adminList, cnStakingV2, other1 } = fixture;

      const submitWithdrawLockupStakingTx = cnStakingV2
        .connect(adminList[0])
        .submitWithdrawLockupStaking(other1.address, toPeb(100n));
      await afterInitFail(submitWithdrawLockupStakingTx);
    });
    it("#ApproveStakingWithdrawal", async function () {
      const { adminList, cnStakingV2, other1 } = fixture;

      const submitApproveStakingWithdrawalTx = cnStakingV2
        .connect(adminList[0])
        .submitApproveStakingWithdrawal(other1.address, toPeb(100n));
      await afterInitFail(submitApproveStakingWithdrawalTx);
    });
    it("#CancelApprovedStakingWithdrawal", async function () {
      const { adminList, cnStakingV2 } = fixture;

      const submitCancelApprovedStakingWithdrawalTx = cnStakingV2
        .connect(adminList[0])
        .submitCancelApprovedStakingWithdrawal(0);
      await afterInitFail(submitCancelApprovedStakingWithdrawalTx);
    });
  });

  // 3. Test submit/confirm functions not related to stake
  describe("Check multisig tx not related to stake", function () {
    // Now we can assume that the contract is initialized
    this.beforeEach(async () => {
      await initialize();
    });
    describe("Check addAdmin process", function () {
      it("#submitAddAdmin: Wrong msg.sender", async function () {
        const { cnStakingV2, other1, other2 } = fixture;

        const submitAddAdminTx = cnStakingV2.connect(other1).submitAddAdmin(other2.address);
        await onlyAdminFail(submitAddAdminTx);
      });
      it("#submitAddAdmin: Admin can't be zero address", async function () {
        const { adminList, cnStakingV2 } = fixture;

        const submitAddAdminTx = cnStakingV2.connect(adminList[0]).submitAddAdmin(ZeroAddress);
        await notNullFail(submitAddAdminTx);
      });
      it("#submitAddAdmin: Can't add admin that already exist", async function () {
        const { adminList, cnStakingV2 } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).submitAddAdmin(adminList[2].address)).to.be.revertedWith(
          "Admin already exists.",
        );
      });
      it("#submitAddAdmin::revokeConfirmation: Request proposer can cancel request", async function () {
        const { adminList, cnStakingV2, other1 } = fixture;

        // Submit submitAddAdmin tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitAddAdmin(other1.address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        // Check request state
        const request = await cnStakingV2.getRequestInfo(0);
        checkRequestInfo(
          [
            FuncID.AddAdmin,
            toBytes32(other1.address),
            toBytes32(0),
            toBytes32(0),
            adminList[0].address,
            [adminList[0].address],
            RequestState.NotConfirmed,
          ],
          request,
        );

        // Revoke request by proposer
        await expect(
          cnStakingV2
            .connect(adminList[0])
            .revokeConfirmation(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0)),
        ).to.emit(cnStakingV2, "CancelRequest");

        // Check updated request state
        const updatedRequest = await cnStakingV2.getRequestInfo(0);
        checkRequestInfo(
          [
            FuncID.AddAdmin,
            toBytes32(other1.address),
            toBytes32(0),
            toBytes32(0),
            adminList[0].address,
            [adminList[0].address],
            RequestState.Canceled,
          ],
          updatedRequest,
        );
      });
      it("#addAdmin::revokeConfirmation: Can't cancel executed request", async function () {
        const { adminList, cnStakingV2, other1 } = fixture;

        // Submit submitAddAdmin tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitAddAdmin(other1.address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        // Submit confirmRequest tx by adminList[1], and it will be confirmed since
        // current requirement is 2
        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0)),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess");

        // Can't cancel executed request
        const confirmRequestTx = cnStakingV2
          .connect(adminList[0])
          .revokeConfirmation(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0));
        await notConfirmedRequestFail(confirmRequestTx);
      });
      it("#submitAddAdmin::confirmRequest: Can't confirm a same request twice", async function () {
        const { adminList, cnStakingV2, other1 } = fixture;

        // Submit submitAddAdmin tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitAddAdmin(other1.address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        // Can't confirm a same request twice
        await expect(
          cnStakingV2
            .connect(adminList[0])
            .confirmRequest(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0)),
        ).to.be.revertedWith("Msg.sender already confirmed.");
      });
      it("#submitAddAdmin::confirmRequest: Can't confirm request with wrong args", async function () {
        const { adminList, cnStakingV2, other1 } = fixture;

        // Submit submitAddAdmin tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitAddAdmin(other1.address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        // Can't confirm request with wrong args
        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(0, FuncID.DeleteAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0)),
        ).to.be.revertedWith("Function id and arguments do not match.");
      });
      it("#submitAddAdmin::confirmRequest: Can't confirm canceled request", async function () {
        const { adminList, cnStakingV2, other1 } = fixture;

        // Submit submitAddAdmin tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitAddAdmin(other1.address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        // Revoke request by proposer
        await expect(
          cnStakingV2
            .connect(adminList[0])
            .revokeConfirmation(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0)),
        ).to.emit(cnStakingV2, "CancelRequest");

        // Can't confirm canceled request
        const confirmRequestTx = cnStakingV2
          .connect(adminList[1])
          .confirmRequest(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0));

        await notConfirmedRequestFail(confirmRequestTx);
      });
      it("#addAdmin: Successfully add admin", async function () {
        const { adminList, cnStakingV2, other1 } = fixture;

        // Submit submitAddAdmin tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitAddAdmin(other1.address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        // Submit confirmRequest tx by adminList[1], and it will be confirmed since
        // current requirement is 2
        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0)),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess");

        // Check updated adminList
        const updatedAdminList = (await cnStakingV2.getState())[3];
        expect(updatedAdminList).to.equalAddrList([...adminList.map((x) => x.address), other1.address]);

        // Check updated request state
        const updatedRequest = await cnStakingV2.getRequestInfo(0);
        checkRequestInfo(
          [
            FuncID.AddAdmin,
            toBytes32(other1.address),
            toBytes32(0),
            toBytes32(0),
            adminList[0].address,
            [adminList[0].address, adminList[1].address],
            RequestState.Executed,
          ],
          updatedRequest,
        );

        // Can't confirm executed request
        const confirmRequestTx = cnStakingV2
          .connect(adminList[2])
          .confirmRequest(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0));
        await notConfirmedRequestFail(confirmRequestTx);
      });
    });
    describe("Check deleteAdmin process", function () {
      it("#submitDeleteAdmin: Wrong msg.sender", async function () {
        const { cnStakingV2, other1, other2 } = fixture;

        const submitDeleteAdminTx = cnStakingV2.connect(other1).submitDeleteAdmin(other2.address);
        await onlyAdminFail(submitDeleteAdminTx);
      });
      it("#submitDeleteAdmin: Admin can't be zero address", async function () {
        const { adminList, cnStakingV2 } = fixture;

        const submitDeleteAdminTx = cnStakingV2.connect(adminList[0]).submitDeleteAdmin(ZeroAddress);
        await notNullFail(submitDeleteAdminTx);
      });
      it("#submitDeleteAdmin: Can't delete admin that doesn't exist", async function () {
        const { adminList, cnStakingV2, other1 } = fixture;

        const submitDeleteAdminTx = cnStakingV2.connect(adminList[0]).submitDeleteAdmin(other1.address);
        await onlyAdminFail(submitDeleteAdminTx);
      });
      it("#deleteAdmin: Successfully delete admin", async function () {
        const { adminList, cnStakingV2 } = fixture;

        // Submit submitDeleteAdmin tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitDeleteAdmin(adminList[2].address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(0, FuncID.DeleteAdmin, toBytes32(adminList[2].address), toBytes32(0), toBytes32(0)),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess");

        // Check updated adminList
        const updatedAdminList = (await cnStakingV2.getState())[3];
        expect(updatedAdminList).to.equalAddrList([adminList[0].address, adminList[1].address]);
      });
    });
    describe("Check updateRequirement process", function () {
      it("#submitUpdateRequirement: Wrong msg.sender", async function () {
        const { cnStakingV2, other1 } = fixture;

        const submitUpdateRequirementTx = cnStakingV2.connect(other1).submitUpdateRequirement(3);
        await onlyAdminFail(submitUpdateRequirementTx);
      });
      it("#submitUpdateRequirement: Can't update requirement to same value", async function () {
        const { adminList, cnStakingV2 } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).submitUpdateRequirement(2)).to.be.revertedWith("Invalid value");
      });
      it("#updateRequirement: Successfully update requirement", async function () {
        const { adminList, cnStakingV2 } = fixture;

        // Submit submitUpdateRequirement tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitUpdateRequirement(3))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(0, FuncID.UpdateRequirement, toBytes32(3), toBytes32(0), toBytes32(0)),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess");

        // Check update requirement
        const updatedRequirement = (await cnStakingV2.getState())[4];
        expect(updatedRequirement).to.equal(3);
      });
    });
    describe("Check clearRequest process", function () {
      async function addRequestsForTest() {
        const { adminList, cnStakingV2, other1 } = fixture;

        // 1. Submit submitAddAdmin tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitAddAdmin(other1.address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        // 2. Submit updateRequirement tx by adminList[1]
        await expect(cnStakingV2.connect(adminList[1]).submitUpdateRequirement(3))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");
      }
      it("#submitClearRequest: Wrong msg.sender", async function () {
        const { cnStakingV2, other1 } = fixture;

        const clearRequestTx = cnStakingV2.connect(other1).submitClearRequest();
        await onlyAdminFail(clearRequestTx);
      });
      it("#clearRequest: Automatically clear outdated request when add/delete/requirement request has been executed", async function () {
        const { adminList, cnStakingV2, other1 } = fixture;

        await addRequestsForTest();

        // Confirming #2 request results in clearing outdated request since it's about requirement update
        await expect(
          cnStakingV2
            .connect(adminList[0])
            .confirmRequest(1, FuncID.UpdateRequirement, toBytes32(3), toBytes32(0), toBytes32(0)),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess");

        // #1 Request state should be canceled
        const requestFor0 = await cnStakingV2.getRequestInfo(0);
        checkRequestInfo(
          [
            FuncID.AddAdmin,
            toBytes32(other1.address),
            toBytes32(0),
            toBytes32(0),
            adminList[0].address,
            [adminList[0].address],
            // Update to Canceled state
            RequestState.Canceled,
          ],
          requestFor0,
        );
      });
      it("#clearRequest: Manually clear outdated request", async function () {
        const { adminList, cnStakingV2, other1 } = fixture;

        await addRequestsForTest();

        // 3. Submit submitClearRequest tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitClearRequest())
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        // Confirming #3 request results in clearing outdated request
        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(2, FuncID.ClearRequest, toBytes32(0), toBytes32(0), toBytes32(0)),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess");

        // Check request state of #0 and #1
        const requestFor0 = await cnStakingV2.getRequestInfo(0);
        checkRequestInfo(
          [
            FuncID.AddAdmin,
            toBytes32(other1.address),
            toBytes32(0),
            toBytes32(0),
            adminList[0].address,
            [adminList[0].address],
            // Update to Canceled state
            RequestState.Canceled,
          ],
          requestFor0,
        );

        const requestFor1 = await cnStakingV2.getRequestInfo(1);
        checkRequestInfo(
          [
            FuncID.UpdateRequirement,
            toBytes32(3),
            toBytes32(0),
            toBytes32(0),
            adminList[1].address,
            [adminList[1].address],
            // Update to Canceled state
            RequestState.Canceled,
          ],
          requestFor1,
        );
      });
    });
    describe("Check updateStakingTracker process", function () {
      it("#submitUpdateStakingTracker: Wrong msg.sender", async function () {
        const { cnStakingV2, other1, stakingTrackerMockReceiver } = fixture;

        const updateStakingTrackerTx = cnStakingV2
          .connect(other1)
          .submitUpdateStakingTracker(stakingTrackerMockReceiver.target);
        await onlyAdminFail(updateStakingTrackerTx);
      });
      it("#submitUpdateStakingTracker: Staking tracker can't be zero address", async function () {
        const { cnStakingV2, adminList } = fixture;

        const updateStakingTrackerTx = cnStakingV2.connect(adminList[0]).submitUpdateStakingTracker(ZeroAddress);
        await notNullFail(updateStakingTrackerTx);
      });
      it("#submitUpdateStakingTracker: Wrong staking tracker contract", async function () {
        const { cnStakingV2, adminList, stakingTrackerMockWrong } = fixture;

        await expect(
          cnStakingV2.connect(adminList[0]).submitUpdateStakingTracker(stakingTrackerMockWrong.target),
        ).to.be.revertedWith("Invalid contract");
      });
      it("#updateStakingTracker: Can't update staking tracker if there's an active tracker", async function () {
        const { cnStakingV2, adminList, stakingTrackerMockReceiver, stakingTrackerMockActive } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).submitUpdateStakingTracker(stakingTrackerMockActive.target))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(stakingTrackerMockReceiver, "RefreshStake");

        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(
              0,
              FuncID.UpdateStakingTracker,
              toBytes32(stakingTrackerMockActive.target),
              toBytes32(0),
              toBytes32(0),
            ),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess")
          .to.emit(stakingTrackerMockReceiver, "RefreshStake");

        // Can't update stakingTrackerMockActive since it has live staking tracker
        await expect(
          cnStakingV2.connect(adminList[0]).submitUpdateStakingTracker(stakingTrackerMockReceiver.target),
        ).to.be.revertedWith("Cannot update tracker when there is an active tracker");
      });
      it("#updateStakingTracker: Successfully update staking tracker", async function () {
        const { cnStakingV2, adminList, stakingTrackerMockReceiver, stakingTrackerMockActive } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).submitUpdateStakingTracker(stakingTrackerMockActive.target))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(stakingTrackerMockReceiver, "RefreshStake");

        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(
              0,
              FuncID.UpdateStakingTracker,
              toBytes32(stakingTrackerMockActive.target),
              toBytes32(0),
              toBytes32(0),
            ),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess")
          .to.emit(stakingTrackerMockReceiver, "RefreshStake");

        // Check updated staking tracker
        expect(await cnStakingV2.stakingTracker()).to.be.equal(stakingTrackerMockActive.target);
      });
    });
    describe("Check updateVoterAddress process", function () {
      it("#submitUpdateVoterAddress: Wrong msg.sender", async function () {
        const { cnStakingV2, other1 } = fixture;

        const updateVoterAddressTx = cnStakingV2.connect(other1).submitUpdateVoterAddress(other1.address);
        await onlyAdminFail(updateVoterAddressTx);
      });
      it("#updateVoterAddress: Successfully update voter address", async function () {
        const { cnStakingV2, stakingTrackerMockReceiver, adminList, other1 } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).submitUpdateVoterAddress(other1.address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(0, FuncID.UpdateVoterAddress, toBytes32(other1.address), toBytes32(0), toBytes32(0)),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess")
          .to.emit(stakingTrackerMockReceiver, "RefreshVoter");
      });
    });
    describe("Check updateRewardAddress process", function () {
      async function updatePendingRewardAddress() {
        const { cnStakingV2, adminList, other1 } = fixture;

        // 1. Submit submitUpdateRewardAddress tx by adminList[0]
        await expect(cnStakingV2.connect(adminList[0]).submitUpdateRewardAddress(other1.address))
          .to.emit(cnStakingV2, "SubmitRequest")
          .to.emit(cnStakingV2, "ConfirmRequest");

        await expect(
          cnStakingV2
            .connect(adminList[1])
            .confirmRequest(0, FuncID.UpdateRewardAddress, toBytes32(other1.address), toBytes32(0), toBytes32(0)),
        )
          .to.emit(cnStakingV2, "ConfirmRequest")
          .to.emit(cnStakingV2, "ExecuteRequestSuccess");
      }
      it("#submitUpdateRewardAddress: Wrong msg.sender", async function () {
        const { cnStakingV2, other1 } = fixture;

        const updateRewardAddressTx = cnStakingV2.connect(other1).submitUpdateRewardAddress(other1.address);
        await onlyAdminFail(updateRewardAddressTx);
      });
      it("#updateRewardAddress: Successfully update pending reward address", async function () {
        const { cnStakingV2, other1 } = fixture;

        await updatePendingRewardAddress();

        // Check pending reward address
        const pendingRewardAddress = await cnStakingV2.pendingRewardAddress();
        expect(pendingRewardAddress).to.be.equal(other1.address);
      });
      it("#acceptRewardAddress: Unauthorized address can't accept reward address", async function () {
        const { cnStakingV2, other1, other2 } = fixture;

        await updatePendingRewardAddress();

        // Accept reward address by non-authorized address
        await expect(cnStakingV2.connect(other2).acceptRewardAddress(other1.address)).to.be.revertedWith(
          "Unauthorized to accept reward address",
        );
      });
      it("#acceptRewardAddress: Accept Reward address by abook admin", async function () {
        const { contractValidator, cnStakingV2, addressBook, other1 } = fixture;

        await updatePendingRewardAddress();

        // Accept reward address by abook admin
        // Note that contract validator is an abook admin
        await expect(cnStakingV2.connect(contractValidator).acceptRewardAddress(other1.address))
          .to.emit(addressBook, "ReviseRewardAddress")
          .to.emit(cnStakingV2, "UpdateRewardAddress");
      });
      it("#acceptRewardAddress: Accept Reward address by reward address", async function () {
        const { cnStakingV2, addressBook, other1 } = fixture;

        await updatePendingRewardAddress();

        // Accept reward address by reward address
        await expect(cnStakingV2.connect(other1).acceptRewardAddress(other1.address))
          .to.emit(addressBook, "ReviseRewardAddress")
          .to.emit(cnStakingV2, "UpdateRewardAddress");
      });
    });
  });

  // 4. Test lockup stakes
  describe("Check withdrawal process of lockup stakes (Initial lockup)", function () {
    async function withdraw(id: number, amount: bigint) {
      const { adminList, cnStakingV2, stakingTrackerMockReceiver, other1 } = fixture;

      await expect(cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, amount))
        .to.emit(cnStakingV2, "SubmitRequest")
        .to.emit(cnStakingV2, "ConfirmRequest");

      await expect(
        cnStakingV2
          .connect(adminList[1])
          .confirmRequest(id, FuncID.WithdrawLockupStaking, toBytes32(other1.address), toBytes32(amount), toBytes32(0)),
      )
        .to.emit(cnStakingV2, "ConfirmRequest")
        .to.emit(cnStakingV2, "ExecuteRequestSuccess")
        .to.emit(cnStakingV2, "WithdrawLockupStaking")
        .to.emit(stakingTrackerMockReceiver, "RefreshStake");
    }
    this.beforeEach(async () => {
      await initialize();
    });
    it("#submitWithdrawLockupStaking: Wrong msg.sender", async function () {
      const { cnStakingV2, other1 } = fixture;

      await jumpTime(1005);

      const submitWithdrawLockupStakingTx = cnStakingV2
        .connect(other1)
        .submitWithdrawLockupStaking(other1.address, toPeb(100n));
      await onlyAdminFail(submitWithdrawLockupStakingTx);
    });
    it("#submitWithdrawLockupStaking: Receiver can't be zero address", async function () {
      const { adminList, cnStakingV2 } = fixture;

      await jumpTime(1005);

      const submitWithdrawLockupStakingTx = cnStakingV2
        .connect(adminList[0])
        .submitWithdrawLockupStaking(ZeroAddress, toPeb(100n));
      await notNullFail(submitWithdrawLockupStakingTx);
    });
    it("#submitWithdrawLockupStaking: Value can't be zero", async function () {
      const { adminList, cnStakingV2, other1 } = fixture;

      await jumpTime(1005);

      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, toPeb(0n)),
      ).to.be.revertedWith("Invalid value.");
    });
    it("#submitWithdrawLockupStaking: Not enough withdrawable amount", async function () {
      const { adminList, cnStakingV2, other1 } = fixture;

      // 1. now < unlockTime[0]: 0
      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, toPeb(100n)),
      ).to.be.revertedWith("Invalid value.");

      await jumpTime(1005);

      // 2. unlockTime[0] < now < unlockTime[1]: unlockAmount[0] = 200 KLAY
      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, toPeb(300n)),
      ).to.be.revertedWith("Invalid value.");

      // 2-1. First withdraw: 100 KLAY
      await withdraw(0, BigInt(toPeb(100n)));

      // 2-2. Second withdraw: 150 KLAY => Not enough withdrawable amount
      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, toPeb(150n)),
      ).to.be.revertedWith("Invalid value.");

      await jumpTime(1005);

      // 3. unlockTime[1] < now: unlockAmount[0] + unlockAmount[1] - 100 KLAY = 500 KLAY
      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, toPeb(700n)),
      ).to.be.revertedWith("Invalid value.");
    });
    it("#withdrawLockupStaking: Successfully withdraw lockup stakes", async function () {
      const { adminList, cnStakingV2, unLockTimes, unLockAmounts, other1 } = fixture;
      const balanceOfOther1Before = await ethers.provider.getBalance(other1.address);

      let lockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(lockupStakingInfo[0]).to.equalNumberList(unLockTimes);
      expect(lockupStakingInfo[1]).to.equalNumberList(unLockAmounts);
      expect(lockupStakingInfo[2]).to.equal(BigInt(toPeb(600n)));
      expect(lockupStakingInfo[3]).to.equal(BigInt(toPeb(600n)));
      expect(lockupStakingInfo[4]).to.equal(BigInt(toPeb(0n)));

      // 1. now < unlockTime[0]: 0
      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, toPeb(100n)),
      ).to.be.revertedWith("Invalid value.");

      await jumpTime(1005);

      // 2. unlockTime[0] < now < unlockTime[1]: unlockAmount[0] = 200 KLAY
      lockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(lockupStakingInfo[4]).to.equal(BigInt(toPeb(200n)));

      await withdraw(0, BigInt(toPeb(100n)));

      lockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(lockupStakingInfo[3]).to.equal(BigInt(toPeb(500n)));
      expect(lockupStakingInfo[4]).to.equal(BigInt(toPeb(100n)));

      // Remaining withdrawable amount: 100 KLAY
      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, toPeb(200n)),
      ).to.be.revertedWith("Invalid value.");

      // It's possible to withdraw 100 KLAY
      await withdraw(1, BigInt(toPeb(100n)));

      lockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(lockupStakingInfo[3]).to.equal(BigInt(toPeb(400n)));
      expect(lockupStakingInfo[4]).to.equal(BigInt(toPeb(0n)));

      await jumpTime(1005);

      // 3. unlockTime[1] < now: unlockAmount[0] + unlockAmount[1] - 200 KLAY = 400 KLAY
      lockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(lockupStakingInfo[3]).to.equal(BigInt(toPeb(400n)));
      expect(lockupStakingInfo[4]).to.equal(BigInt(toPeb(400n)));

      await withdraw(2, BigInt(toPeb(250n)));

      lockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(lockupStakingInfo[3]).to.equal(BigInt(toPeb(150n)));
      expect(lockupStakingInfo[4]).to.equal(BigInt(toPeb(150n)));

      // Remaining withdrawable amount: 150 KLAY
      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, toPeb(200n)),
      ).to.be.revertedWith("Invalid value.");

      // It's possible to withdraw 150 KLAY
      await withdraw(3, BigInt(toPeb(150n)));

      lockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(lockupStakingInfo[3]).to.equal(BigInt(toPeb(0n)));
      expect(lockupStakingInfo[4]).to.equal(BigInt(toPeb(0n)));

      // Check balance of the contract and receiver
      const balanceOfOther1After = await ethers.provider.getBalance(other1.address);

      expect(await ethers.provider.getBalance(await cnStakingV2.getAddress())).to.be.equal(0);
      expect(balanceOfOther1After - balanceOfOther1Before).to.be.equal(BigInt(toPeb(600n)));
    });
  });

  // 5. Test free stakes
  describe("Check free stakes process", function () {
    async function approveStakingWithdrawal(id: number, amount: bigint) {
      const { cnStakingV2, stakingTrackerMockReceiver, adminList, other1 } = fixture;

      await expect(cnStakingV2.connect(adminList[0]).submitApproveStakingWithdrawal(other1.address, amount))
        .to.emit(cnStakingV2, "SubmitRequest")
        .to.emit(cnStakingV2, "ConfirmRequest");

      const now = await nowTime();
      await setTime(now + 1);

      await expect(
        cnStakingV2
          .connect(adminList[1])
          .confirmRequest(
            id,
            FuncID.ApproveStakingWithdrawal,
            toBytes32(other1.address),
            toBytes32(amount),
            toBytes32(0),
          ),
      )
        .to.emit(cnStakingV2, "ConfirmRequest")
        .to.emit(cnStakingV2, "ExecuteRequestSuccess")
        .to.emit(stakingTrackerMockReceiver, "RefreshStake");

      // Since confirmRequest executed after 1 second, the timestamp of the request is now + 2
      return now + 2;
    }
    this.beforeEach(async () => {
      await initialize();
    });
    describe("Check deposit process", function () {
      it("#stakeKlay: Can't stake 0 KLAY", async function () {
        const { cnStakingV2, adminList } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).stakeKlay({ value: 0 })).to.be.revertedWith("Invalid amount.");
      });
      it("#stakeKlay: Successfully stake KLAY via stakeKLAY function", async function () {
        const { cnStakingV2, stakingTrackerMockReceiver, adminList } = fixture;

        await expect(cnStakingV2.connect(adminList[0]).stakeKlay({ value: toPeb(500n) }))
          .to.emit(cnStakingV2, "StakeKlay")
          .to.emit(stakingTrackerMockReceiver, "RefreshStake");

        const balanceOfContract = await ethers.provider.getBalance(await cnStakingV2.getAddress());
        expect(balanceOfContract).to.be.equal(BigInt(toPeb(1100n)));
      });
      it("#fallback: Can't stake 0 KLAY", async function () {
        const { cnStakingV2, adminList } = fixture;

        await expect(
          adminList[0].sendTransaction({ to: await cnStakingV2.getAddress(), value: toPeb(0n) }),
        ).to.be.revertedWith("Invalid amount.");
      });
      it("#fallback: Successfully stake KLAY via fallback", async function () {
        const { cnStakingV2, stakingTrackerMockReceiver, adminList } = fixture;

        await expect(adminList[0].sendTransaction({ to: await cnStakingV2.getAddress(), value: toPeb(500n) }))
          .to.emit(cnStakingV2, "StakeKlay")
          .to.emit(stakingTrackerMockReceiver, "RefreshStake");

        const balanceOfContract = await ethers.provider.getBalance(await cnStakingV2.getAddress());
        expect(balanceOfContract).to.be.equal(BigInt(toPeb(1100n)));
      });
    });
    describe("Check withdrawal process", function () {
      this.beforeEach(async () => {
        const { adminList, cnStakingV2, stakingTrackerMockReceiver } = fixture;

        // Free stake 500 KLAY
        await expect(cnStakingV2.connect(adminList[0]).stakeKlay({ value: toPeb(500n) }))
          .to.emit(cnStakingV2, "StakeKlay")
          .to.emit(stakingTrackerMockReceiver, "RefreshStake");
      });
      describe("Check approveStakingWithdrawal process", function () {
        it("#submitApproveStakingWithdrawal: Wrong msg.sender", async function () {
          const { cnStakingV2, other1 } = fixture;

          const submitApproveStakingWithdrawalTx = cnStakingV2
            .connect(other1)
            .submitApproveStakingWithdrawal(other1.address, toPeb(100n));
          await onlyAdminFail(submitApproveStakingWithdrawalTx);
        });
        it("#submitApproveStakingWithdrawal: Receiver can't be zero address", async function () {
          const { cnStakingV2, adminList } = fixture;

          const submitApproveStakingWithdrawalTx = cnStakingV2
            .connect(adminList[0])
            .submitApproveStakingWithdrawal(ZeroAddress, toPeb(100n));
          await notNullFail(submitApproveStakingWithdrawalTx);
        });
        it("#submitApproveStakingWithdrawal: Value can't be zero", async function () {
          const { cnStakingV2, adminList, other1 } = fixture;

          await expect(
            cnStakingV2.connect(adminList[0]).submitApproveStakingWithdrawal(other1.address, toPeb(0n)),
          ).to.be.revertedWith("Invalid value.");
        });
        it("#submitApproveStakingWithdrawal: Not enough stakes to withdraw", async function () {
          const { cnStakingV2, adminList, other1 } = fixture;

          await expect(
            cnStakingV2.connect(adminList[0]).submitApproveStakingWithdrawal(other1.address, toPeb(550n)),
          ).to.be.revertedWith("Invalid value.");
        });
        it("#submitApproveStakingWithdrawal: unstaking + value can't exceed staking amount", async function () {
          const { cnStakingV2, adminList, other1 } = fixture;

          await approveStakingWithdrawal(0, BigInt(toPeb(300n)));

          // Now, we have unstaked 200 KLAY. So, we can't approve more than 300 KLAY
          await expect(
            cnStakingV2.connect(adminList[0]).submitApproveStakingWithdrawal(other1.address, toPeb(350n)),
          ).to.be.revertedWith("Too much outstanding withdrawal");

          // It's possible below 300 KLAY
          await expect(cnStakingV2.connect(adminList[0]).submitApproveStakingWithdrawal(other1.address, toPeb(200n)))
            .to.emit(cnStakingV2, "SubmitRequest")
            .to.emit(cnStakingV2, "ConfirmRequest");
        });
        it("#approveStakingWithdrawal: Not withdrawable before 1 week", async function () {
          const { cnStakingV2, adminList } = fixture;

          // Approve withdraw 300 KLAY
          await approveStakingWithdrawal(0, BigInt(toPeb(300n)));

          await jumpTime(4 * DAY);

          // Not withdrawable before 1 week
          await expect(cnStakingV2.connect(adminList[0]).withdrawApprovedStaking(0)).to.be.revertedWith(
            "Not withdrawable yet.",
          );
        });
        it("#approveStakingWithdrawal: Need to withdraw free stakes before 2 weeks", async function () {
          const { cnStakingV2, adminList, stakingTrackerMockReceiver } = fixture;

          await approveStakingWithdrawal(0, BigInt(toPeb(300n)));

          await jumpTime(2 * WEEK);

          await approveStakingWithdrawal(1, BigInt(toPeb(200n)));

          // Admin can't withdraw stakes after withdrawableFrom + WEEK (2 weeks after approve)
          await expect(cnStakingV2.connect(adminList[0]).withdrawApprovedStaking(0))
            .to.emit(cnStakingV2, "CancelApprovedStakingWithdrawal")
            .to.emit(stakingTrackerMockReceiver, "RefreshStake");

          // Check staking related state
          const balanceOfContract = await ethers.provider.getBalance(await cnStakingV2.getAddress());
          const staking = await cnStakingV2.staking();
          const unstaking = await cnStakingV2.unstaking();

          expect(balanceOfContract).to.equal(BigInt(toPeb(1100n)));
          expect(staking).to.equal(BigInt(toPeb(500n)));
          expect(unstaking).to.equal(BigInt(toPeb(200n)));
        });
        it("#approveStakingWithdrawal: Check approved staking withdrawal info", async function () {
          const { cnStakingV2, other1 } = fixture;

          const now1 = await approveStakingWithdrawal(0, BigInt(toPeb(300n)));

          await jumpTime(1000);

          const now2 = await approveStakingWithdrawal(1, BigInt(toPeb(200n)));

          // Check approved staking withdrawal info
          let approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(0);
          expect(approvedStakingWithdrawalInfo[0]).to.be.equal(other1.address);
          expect(approvedStakingWithdrawalInfo[1]).to.be.equal(BigInt(toPeb(300n)));
          expect(Number(approvedStakingWithdrawalInfo[2])).to.be.equal(now1 + WEEK);
          expect(Number(approvedStakingWithdrawalInfo[3])).to.be.equal(RequestState.Unknown);

          approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(1);
          expect(approvedStakingWithdrawalInfo[0]).to.be.equal(other1.address);
          expect(approvedStakingWithdrawalInfo[1]).to.be.equal(BigInt(toPeb(200n)));
          expect(Number(approvedStakingWithdrawalInfo[2])).to.be.equal(now2 + WEEK);
          expect(Number(approvedStakingWithdrawalInfo[3])).to.be.equal(RequestState.Unknown);
        });
        it("#withdrawApprovedStaking: Can't withdraw twice from a same request", async function () {
          const { cnStakingV2, adminList, stakingTrackerMockReceiver } = fixture;

          await approveStakingWithdrawal(0, BigInt(toPeb(300n)));

          await jumpTime(WEEK);

          // Admin can withdraw first withdraw stake request
          await expect(cnStakingV2.connect(adminList[0]).withdrawApprovedStaking(0))
            .to.emit(cnStakingV2, "WithdrawApprovedStaking")
            .to.emit(stakingTrackerMockReceiver, "RefreshStake");

          // Admin already withdrew first withdraw stake request
          await expect(cnStakingV2.connect(adminList[0]).withdrawApprovedStaking(0)).to.be.revertedWith(
            "Invalid state.",
          );
        });
        it("#withdrawApprovedStaking: Successfully withdraw all free stakes", async function () {
          const { cnStakingV2, adminList, stakingTrackerMockReceiver } = fixture;

          // Let's withdraw all funds through 2 requests
          await approveStakingWithdrawal(0, BigInt(toPeb(300n)));

          await jumpTime(3 * DAY);

          await approveStakingWithdrawal(1, BigInt(toPeb(200n)));

          await jumpTime(4 * DAY);

          // Admin can withdraw first withdraw stake request
          await expect(cnStakingV2.connect(adminList[0]).withdrawApprovedStaking(0))
            .to.emit(cnStakingV2, "WithdrawApprovedStaking")
            .to.emit(stakingTrackerMockReceiver, "RefreshStake");

          await jumpTime(4 * DAY);

          // Admin can withdraw third withdraw stake request
          await expect(cnStakingV2.connect(adminList[2]).withdrawApprovedStaking(1))
            .to.emit(cnStakingV2, "WithdrawApprovedStaking")
            .to.emit(stakingTrackerMockReceiver, "RefreshStake");

          // Check staking related state
          const unstaking = await cnStakingV2.unstaking();
          const staking = await cnStakingV2.staking();

          expect(unstaking).to.equal(BigInt(toPeb(0n)));
          expect(staking).to.equal(BigInt(toPeb(0n)));
        });
      });
      describe("Check cancelApprovedStakingWithdrawal process", function () {
        this.beforeEach(async () => {
          await approveStakingWithdrawal(0, BigInt(toPeb(300n)));

          await jumpTime(1000);

          await approveStakingWithdrawal(1, BigInt(toPeb(200n)));
        });
        it("#submitCancelApprovedStakingWithdrawal: Wrong msg.sender", async function () {
          const { cnStakingV2, other1 } = fixture;

          const submitCancelApprovedStakingWithdrawalTx = cnStakingV2
            .connect(other1)
            .submitCancelApprovedStakingWithdrawal(0);
          await onlyAdminFail(submitCancelApprovedStakingWithdrawalTx);
        });
        it("#submitCancelApprovedStakingWithdrawal: Can't cancel empty request", async function () {
          const { cnStakingV2, adminList } = fixture;

          await expect(cnStakingV2.connect(adminList[0]).submitCancelApprovedStakingWithdrawal(3)).to.be.revertedWith(
            "Withdrawal request does not exist.",
          );
        });
        it("#submitCancelApprovedStakingWithdrawal: Can't cancel transferred state", async function () {
          const { cnStakingV2, adminList, stakingTrackerMockReceiver } = fixture;

          await jumpTime(WEEK + DAY);

          // Withdraw first request
          await expect(cnStakingV2.connect(adminList[0]).withdrawApprovedStaking(0))
            .to.emit(cnStakingV2, "WithdrawApprovedStaking")
            .to.emit(stakingTrackerMockReceiver, "RefreshStake");

          // Check balance of contract
          expect(await ethers.provider.getBalance(await cnStakingV2.getAddress())).to.be.equal(BigInt(toPeb(800n)));

          // Can't cancel first request since it's already transferred
          await expect(cnStakingV2.connect(adminList[0]).submitCancelApprovedStakingWithdrawal(0)).to.be.revertedWith(
            "Invalid state.",
          );
        });
        it("#submitCancelApprovedStakingWithdrawal: Successfully cancel approved staking withdrawal request", async function () {
          const { cnStakingV2, adminList } = fixture;

          await expect(cnStakingV2.connect(adminList[0]).submitCancelApprovedStakingWithdrawal(0))
            .to.emit(cnStakingV2, "SubmitRequest")
            .to.emit(cnStakingV2, "ConfirmRequest");

          // Cancel first approved staking withdrawal request
          await expect(
            cnStakingV2
              .connect(adminList[1])
              .confirmRequest(2, FuncID.CancelApprovedStakingWithdrawal, toBytes32(0), toBytes32(0), toBytes32(0)),
          )
            .to.emit(cnStakingV2, "ConfirmRequest")
            .to.emit(cnStakingV2, "ExecuteRequestSuccess");

          // Check withdrawal staking state and total unstaking amount
          const approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(0);
          expect(approvedStakingWithdrawalInfo[3]).to.equal(WithdrawalState.Canceled);

          const unstaking = await cnStakingV2.unstaking();
          expect(unstaking).to.equal(BigInt(toPeb(200n)));
        });
      });
    });
  });
});
