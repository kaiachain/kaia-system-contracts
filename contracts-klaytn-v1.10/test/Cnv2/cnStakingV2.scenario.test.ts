import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import {
  FuncID,
  RequestState,
  WithdrawalState,
  augmentChai,
  toPeb,
  toBytes32,
  jumpTime,
  notConfirmedRequestFail,
  submitRequest,
  confirmRequests,
  submitAndExecuteRequest,
} from "../../helpers/utils";
import { cnV2ScenarioTestFixture } from "../materials";

// const RAND_ADDR = "0xe3B0C44298FC1C149AfBF4C8996fb92427aE41E4"; // non-null placeholder
const DAY = 24 * 60 * 60;
const WEEK = 7 * DAY;

type UnPromisify<T> = T extends Promise<infer U> ? U : T;

/**
 * @dev This is scenario tests for cnStakingV2.sol
 * 1. Scenario tests about confirmRequest/revokeConfirmation
 * 2. Scenario tests about lockup-stakes withdraw
 *    - Case for now < unLockTimes[0]
 *    - Case for unLockTimes[0] <= now < unLockTimes[1]
 *    - Case for unLockTimes[1] <= now
 * 3. Scenario tests about free-stakes stake/withdraw
 *    - When withdraw free-stakes
 *    - When cancel approved withdrawal
 */
describe("Scenario test for cnStakingV2.sol", function () {
  let fixture: UnPromisify<ReturnType<typeof cnV2ScenarioTestFixture>>;
  beforeEach(async function () {
    augmentChai();
    fixture = await loadFixture(cnV2ScenarioTestFixture);

    // Assume that initialization has been done
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
  });
  // 1. Scenario tests about confirmRequest/revokeConfirmation
  describe("Scenario tests about confirmRequest/revokeConfirmation", function () {
    it("#1. Request will be canceled if proposer revokes confirmation", async function () {
      const { cnStakingV2, adminList, other1 } = fixture;

      await submitRequest(cnStakingV2, FuncID.AddAdmin, adminList[0], [other1.address, 0, 0]);

      // Not executed since requirement is 3
      await confirmRequests(cnStakingV2, [adminList[1]], [0, FuncID.AddAdmin, other1.address, 0, 0]);
      // Revoked by proposer
      await cnStakingV2
        .connect(adminList[0])
        .revokeConfirmation(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0));

      // Check request is canceled
      const request = await cnStakingV2.getRequestInfo(0);
      expect(request[6]).to.equal(RequestState.Canceled);

      // Can't confirm canceled request
      const confirmRequestTx = cnStakingV2
        .connect(adminList[2])
        .confirmRequest(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0));
      await notConfirmedRequestFail(confirmRequestTx);
    });
    it("#2. Executed request can't be canceled", async function () {
      const { cnStakingV2, adminList, other1 } = fixture;

      await submitRequest(cnStakingV2, FuncID.AddAdmin, adminList[0], [other1.address, 0, 0]);

      // Executed by 3 admins
      await confirmRequests(cnStakingV2, [adminList[1], adminList[2]], [0, FuncID.AddAdmin, other1.address, 0, 0]);

      // Check request is executed
      const request = await cnStakingV2.getRequestInfo(0);
      expect(request[6]).to.equal(RequestState.Executed);

      // Can't cancel executed request
      const revokeConfirmationTx = cnStakingV2
        .connect(adminList[0])
        .revokeConfirmation(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0));
      await notConfirmedRequestFail(revokeConfirmationTx);
    });
    it("#3. Revoked scenario by confirmers", async function () {
      const { cnStakingV2, adminList, other1 } = fixture;

      await submitRequest(cnStakingV2, FuncID.AddAdmin, adminList[0], [other1.address, 0, 0]);

      // Now confirmed by 2 admins
      await confirmRequests(cnStakingV2, [adminList[1]], [0, FuncID.AddAdmin, other1.address, 0, 0]);

      // Confirmer revokes confirmation
      await cnStakingV2
        .connect(adminList[1])
        .revokeConfirmation(0, FuncID.AddAdmin, toBytes32(other1.address), toBytes32(0), toBytes32(0));

      // Again, confirmed by 2 admins
      await confirmRequests(cnStakingV2, [adminList[2]], [0, FuncID.AddAdmin, other1.address, 0, 0]);

      // Check request is not confirmed
      let request = await cnStakingV2.getRequestInfo(0);
      expect(request[6]).to.equal(RequestState.NotConfirmed);

      // Admin 1 confirms again, request will be executed
      await confirmRequests(cnStakingV2, [adminList[1]], [0, FuncID.AddAdmin, other1.address, 0, 0]);

      // Check request is executed
      request = await cnStakingV2.getRequestInfo(0);
      expect(request[6]).to.equal(RequestState.Executed);
    });
  });

  // 2. Scenario tests about lockup-stakes withdraw
  describe("Scenario test about lockup-stakes withdraw", function () {
    it("Check getLockupStakingInfo", async function () {
      const { cnStakingV2, unLockAmounts } = fixture;

      let getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(0n);

      // unLockAmounts[0] should be withdrawable
      await jumpTime(1005);
      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(unLockAmounts[0]);

      // unLockAmounts[0] + unLockAmount[1] should be withdrawable
      await jumpTime(1000);
      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(BigInt(unLockAmounts[0]) + BigInt(unLockAmounts[1]));
    });
    it("#1. Scenario when now < unLockTimes[0]", async function () {
      const { cnStakingV2, adminList, unLockAmounts, other1 } = fixture;

      let getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(0n);

      // now < unLockTime[0]: withdraw should be failed
      await jumpTime(30);
      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(0n);

      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, unLockAmounts[0]),
      ).to.be.revertedWith("Invalid value.");
    });
    it("#2. Scenario when unLockTimes[0] <= now < unLockTimes[1]", async function () {
      const { cnStakingV2, adminList, unLockAmounts, requirement, other1 } = fixture;

      let getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(0n);

      // unLockTimes[0] <= now < unLockTimes[1]: unLockAmounts[0] is withdrawable
      await jumpTime(1005);
      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(unLockAmounts[0]);

      // Partial withdraws should be success
      // 1. Withdraw 100 KLAY => Success
      // 2. Withdraw 50 KLAY => Success
      // 3. Withdraw 100 KLAY => Fail
      // 4. Withdraw 50 KLAY => Success

      // 1. Withdraw 100 KLAY
      await submitAndExecuteRequest(cnStakingV2, adminList, requirement, FuncID.WithdrawLockupStaking, adminList[0], [
        0,
        FuncID.WithdrawLockupStaking,
        other1.address,
        BigInt(toPeb(100n)),
        0,
      ]);

      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(BigInt(toPeb(100n)));

      // 2. Withdraw 50 KLAY
      await submitAndExecuteRequest(cnStakingV2, adminList, requirement, FuncID.WithdrawLockupStaking, adminList[0], [
        1,
        FuncID.WithdrawLockupStaking,
        other1.address,
        BigInt(toPeb(50n)),
        0,
      ]);

      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(BigInt(toPeb(50n)));

      // 3. Withdraw 100 KLAY => Fail
      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, BigInt(toPeb(100n))),
      ).to.be.revertedWith("Invalid value.");

      // 4. Withdraw 50 KLAY
      await submitAndExecuteRequest(cnStakingV2, adminList, requirement, FuncID.WithdrawLockupStaking, adminList[0], [
        2,
        FuncID.WithdrawLockupStaking,
        other1.address,
        BigInt(toPeb(50n)),
        0,
      ]);

      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(0n);

      // Get request ids
      const ids = await cnStakingV2.getRequestIds(0, 0, RequestState.Executed);
      expect(ids).to.equalNumberList([0n, 1n, 2n]);
    });
    it("#3. Scenario when now <= unLockTImes[1]", async function () {
      const { cnStakingV2, adminList, requirement, unLockAmounts, other1 } = fixture;

      let getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(0n);

      // unLockTimes[1] <= now: unLockAmounts[0] + unLockAmounts[1] is withdrawable
      await jumpTime(2005);
      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(BigInt(unLockAmounts[0]) + BigInt(unLockAmounts[1]));

      // Partial withdraws should be success
      // 1. Withdraw 200 KLAY => Success
      // 2. Withdraw 250 KLAY => Success
      // 3. Withdraw 200 KLAY => Fail
      // 4. Withdraw 50 KLAY => Success
      // Remaining: 100 KLAY

      // 1. Withdraw 200 KLAY
      await submitAndExecuteRequest(cnStakingV2, adminList, requirement, FuncID.WithdrawLockupStaking, adminList[0], [
        0,
        FuncID.WithdrawLockupStaking,
        other1.address,
        BigInt(toPeb(200n)),
        0,
      ]);

      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(BigInt(toPeb(400n)));

      // 2. Withdraw 250 KLAY
      await submitAndExecuteRequest(cnStakingV2, adminList, requirement, FuncID.WithdrawLockupStaking, adminList[0], [
        1,
        FuncID.WithdrawLockupStaking,
        other1.address,
        BigInt(toPeb(250n)),
        0,
      ]);

      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(BigInt(toPeb(150n)));

      // 3. Withdraw 200 KLAY => Fail
      await expect(
        cnStakingV2.connect(adminList[0]).submitWithdrawLockupStaking(other1.address, BigInt(toPeb(200n))),
      ).to.be.revertedWith("Invalid value.");

      // 4. Withdraw 50 KLAY
      await submitAndExecuteRequest(cnStakingV2, adminList, requirement, FuncID.WithdrawLockupStaking, adminList[0], [
        2,
        FuncID.WithdrawLockupStaking,
        other1.address,
        BigInt(toPeb(50n)),
        0,
      ]);

      // Remaining: 100 KLAY
      getLockupStakingInfo = await cnStakingV2.getLockupStakingInfo();
      expect(getLockupStakingInfo[4]).to.equal(BigInt(toPeb(100n)));
    });
  });

  // 3. Scenario tests about free-stakes stake/withdraw
  describe("Scenario tests about free-stakes stake/withdraw", function () {
    beforeEach(async function () {
      const { cnStakingV2 } = fixture;

      // Stake 500 KLAY free-stakes via stakeKlay function
      await cnStakingV2.stakeKlay({ value: toPeb(500n) });

      const staking = await cnStakingV2.staking();
      expect(staking).to.equal(BigInt(toPeb(500n)));
    });
    it("#1. Scenario when withdraw stakes", async function () {
      const { cnStakingV2, adminList, requirement, other1 } = fixture;

      // Partial withdraws in following scenario should be success
      // 1. submit withdraw 200 KLAY => Success
      // jumpTime(3 * DAY)
      // 2. submit withdraw 150 KLAY => Success
      // jumTime(5 * DAY)
      // 3. withdraw from (1) => Success
      // jumTime(10 * DAY)
      // 4. submit withdraw 250 KLAY => Fail
      // 5. withdraw from (2) => Fail and request canceled
      // 6. submit withdraw 250 KLAY => Success
      // jumTime(WEEK)
      // 7. withdraw from (6) => Success
      // 8. submit withdraw 500 KLAY => Fail
      // 9. stake 500 KLAY via stakeKlay function
      // 10. submit withdraw 500 KLAY => Success

      // 1. submit withdraw 200 KLAY
      await submitAndExecuteRequest(
        cnStakingV2,
        adminList,
        requirement,
        FuncID.ApproveStakingWithdrawal,
        adminList[0],
        [0, FuncID.ApproveStakingWithdrawal, other1.address, BigInt(toPeb(200n)), 0],
      );

      await jumpTime(3 * DAY);

      // 2. submit withdraw 150 KLAY
      await submitAndExecuteRequest(
        cnStakingV2,
        adminList,
        requirement,
        FuncID.ApproveStakingWithdrawal,
        adminList[0],
        [1, FuncID.ApproveStakingWithdrawal, other1.address, BigInt(toPeb(150n)), 0],
      );

      await jumpTime(5 * DAY);

      // 3. withdraw from (1)
      await cnStakingV2.connect(adminList[1]).withdrawApprovedStaking(0);

      // Check approvedStakingInfo
      let staking = await cnStakingV2.staking();
      let unstaking = await cnStakingV2.unstaking();
      let approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(0);
      expect(staking).to.equal(BigInt(toPeb(300n)));
      expect(unstaking).to.equal(BigInt(toPeb(150n)));
      expect(approvedStakingWithdrawalInfo[3]).to.equal(WithdrawalState.Transferred);

      await jumpTime(10 * DAY);

      // 4. submit withdraw 250 KLAY => Fail
      await expect(
        cnStakingV2.connect(adminList[2]).submitApproveStakingWithdrawal(other1.address, BigInt(toPeb(250n))),
      ).to.be.revertedWith("Too much outstanding withdrawal");

      // 5. withdraw from (2) => Fail and request canceled
      await expect(cnStakingV2.connect(adminList[2]).withdrawApprovedStaking(1)).to.emit(
        cnStakingV2,
        "CancelApprovedStakingWithdrawal",
      );

      // Check approvedStakingInfo
      approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(1);
      expect(approvedStakingWithdrawalInfo[3]).to.equal(WithdrawalState.Canceled);

      // 6. submit withdraw 250 KLAY => Success
      await submitAndExecuteRequest(
        cnStakingV2,
        adminList,
        requirement,
        FuncID.ApproveStakingWithdrawal,
        adminList[0],
        [2, FuncID.ApproveStakingWithdrawal, other1.address, BigInt(toPeb(250n)), 0],
      );

      await jumpTime(WEEK);

      // 7. withdraw from (6) => Success
      await cnStakingV2.connect(adminList[2]).withdrawApprovedStaking(2);

      // Check approvedStakingInfo
      staking = await cnStakingV2.staking();
      unstaking = await cnStakingV2.unstaking();
      approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(2);
      expect(staking).to.equal(BigInt(toPeb(50n)));
      expect(unstaking).to.equal(0n);
      expect(approvedStakingWithdrawalInfo[3]).to.equal(WithdrawalState.Transferred);

      // 8. submit withdraw 500 KLAY => Fail
      await expect(
        cnStakingV2.connect(adminList[2]).submitApproveStakingWithdrawal(other1.address, BigInt(toPeb(250n))),
      ).to.be.revertedWith("Invalid value.");

      // 9. stake 500 KLAY via stakeKlay function
      await cnStakingV2.connect(adminList[2]).stakeKlay({ value: toPeb(500n) });

      // 10. submit withdraw 500 KLAY => Success
      await submitAndExecuteRequest(
        cnStakingV2,
        adminList,
        requirement,
        FuncID.ApproveStakingWithdrawal,
        adminList[0],
        [3, FuncID.ApproveStakingWithdrawal, other1.address, BigInt(toPeb(500n)), 0],
      );

      // Check approvedStakingInfo
      staking = await cnStakingV2.staking();
      unstaking = await cnStakingV2.unstaking();
      approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(3);
      expect(staking).to.equal(BigInt(toPeb(550n)));
      expect(unstaking).to.equal(BigInt(toPeb(500n)));
      expect(approvedStakingWithdrawalInfo[3]).to.equal(WithdrawalState.Unknown);

      // Get approved staking withdrawal ids
      const ids = await cnStakingV2.getApprovedStakingWithdrawalIds(0, 0, WithdrawalState.Transferred);
      expect(ids).to.equalNumberList([0n, 2n]);
    });
    it("#2. Scenario when cancel approved withdrawal", async function () {
      const { cnStakingV2, adminList, requirement, other1 } = fixture;

      // Partial withdraws with canceled request in following scenario should be success
      // 1. submit withdraw 200 KLAY => Success
      // jumpTime(3 * DAY)
      // 2. submit withdraw 150 KLAY => Success
      // jumTime(5 * DAY)
      // 3. withdraw from (1) => Success
      // jumTime(3 * DAY)
      // 4. submit withdraw 250 KLAY => Fail
      // 5. cancel request (2) => Success
      // 6. submit withdraw 250 KLAY => Success

      // 1. submit withdraw 200 KLAY
      await submitAndExecuteRequest(
        cnStakingV2,
        adminList,
        requirement,
        FuncID.ApproveStakingWithdrawal,
        adminList[0],
        [0, FuncID.ApproveStakingWithdrawal, other1.address, BigInt(toPeb(200n)), 0],
      );

      await jumpTime(3 * DAY);

      // 2. submit withdraw 150 KLAY
      await submitAndExecuteRequest(
        cnStakingV2,
        adminList,
        requirement,
        FuncID.ApproveStakingWithdrawal,
        adminList[0],
        [1, FuncID.ApproveStakingWithdrawal, other1.address, BigInt(toPeb(150n)), 0],
      );

      await jumpTime(5 * DAY);

      // 3. withdraw from (1)
      await cnStakingV2.connect(adminList[1]).withdrawApprovedStaking(0);

      // Check approvedStakingInfo
      let staking = await cnStakingV2.staking();
      let unstaking = await cnStakingV2.unstaking();
      let approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(0);
      expect(staking).to.equal(BigInt(toPeb(300n)));
      expect(unstaking).to.equal(BigInt(toPeb(150n)));
      expect(approvedStakingWithdrawalInfo[3]).to.equal(WithdrawalState.Transferred);

      await jumpTime(5 * DAY);

      // 4. submit withdraw 250 KLAY => Fail
      await expect(
        cnStakingV2.connect(adminList[2]).submitApproveStakingWithdrawal(other1.address, BigInt(toPeb(250n))),
      ).to.be.revertedWith("Too much outstanding withdrawal");

      // 5. cancel request (2)
      await submitAndExecuteRequest(
        cnStakingV2,
        adminList,
        requirement,
        FuncID.CancelApprovedStakingWithdrawal,
        adminList[0],
        [2, FuncID.CancelApprovedStakingWithdrawal, 1, 0, 0],
      );

      // Check approvedStakingInfo
      unstaking = await cnStakingV2.unstaking();
      approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(1);
      expect(unstaking).to.equal(0n);
      expect(approvedStakingWithdrawalInfo[3]).to.equal(WithdrawalState.Canceled);

      // 6. submit withdraw 250 KLAY => Success
      await submitAndExecuteRequest(
        cnStakingV2,
        adminList,
        requirement,
        FuncID.ApproveStakingWithdrawal,
        adminList[0],
        [3, FuncID.ApproveStakingWithdrawal, other1.address, BigInt(toPeb(250n)), 0],
      );

      // Check approvedStakingInfo
      staking = await cnStakingV2.staking();
      unstaking = await cnStakingV2.unstaking();
      approvedStakingWithdrawalInfo = await cnStakingV2.getApprovedStakingWithdrawalInfo(2);
      expect(staking).to.equal(BigInt(toPeb(300n)));
      expect(unstaking).to.equal(BigInt(toPeb(250n)));
      expect(approvedStakingWithdrawalInfo[3]).to.equal(WithdrawalState.Unknown);
    });
  });
});
