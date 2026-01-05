/* eslint-disable @typescript-eslint/no-explicit-any */
import { loadFixture, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { delegatorTestFixture } from "../materials";
import { addTime, WEEK } from "../../helpers/utils";
import { parseEther, keccak256, toUtf8Bytes, ZeroAddress } from "ethers";

describe("Delegator tests", function () {
  describe("Check delegator initial state", function () {
    it("should have correct access control roles", async function () {
      const { dc } = await loadFixture(delegatorTestFixture);

      expect(await dc.DELEGATOR_ROLE()).to.equal(keccak256(toUtf8Bytes("DELEGATOR_ROLE")));
      expect(await dc.DELEGATEE_ROLE()).to.equal(keccak256(toUtf8Bytes("DELEGATEE_ROLE")));
    });
    it("should have correct delegator/delegatee", async function () {
      const { delegator, delegatee, dc } = await loadFixture(delegatorTestFixture);

      expect(await dc.getRoleMember(await dc.DELEGATOR_ROLE(), 0)).to.equal(delegator.address);
      expect(await dc.getRoleMember(await dc.DELEGATEE_ROLE(), 0)).to.equal(delegatee.address);
    });
  });
  describe("only role check", function () {
    it("check all functions", async function () {
      const { delegator, delegatee, dc } = await loadFixture(delegatorTestFixture);

      await expect(dc.connect(delegatee).transferDelegator(delegatee.address)).to.be.revertedWithCustomError(
        dc,
        "AccessControlUnauthorizedAccount",
      );
      await expect(dc.connect(delegator).transferDelegatee(delegator.address)).to.be.revertedWithCustomError(
        dc,
        "AccessControlUnauthorizedAccount",
      );

      await expect(dc.connect(delegatee).delegate({ value: 1 })).to.be.revertedWithCustomError(
        dc,
        "AccessControlUnauthorizedAccount",
      );

      await expect(dc.connect(delegatee).withdrawDelegation(delegatee.address, 1)).to.be.revertedWithCustomError(
        dc,
        "AccessControlUnauthorizedAccount",
      );
      await expect(dc.connect(delegator).withdrawReward(delegator.address, 1)).to.be.revertedWithCustomError(
        dc,
        "AccessControlUnauthorizedAccount",
      );

      await expect(dc.connect(delegatee).claimDelegation(0)).to.be.revertedWithCustomError(
        dc,
        "AccessControlUnauthorizedAccount",
      );
      await expect(dc.connect(delegator).claimReward(0)).to.be.revertedWithCustomError(
        dc,
        "AccessControlUnauthorizedAccount",
      );
    });
  });
  describe("role transfer check", function () {
    it("delegator/delegatee can't be zero address", async function () {
      const { delegator, delegatee, dc } = await loadFixture(delegatorTestFixture);

      await expect(dc.connect(delegator).transferDelegator(ZeroAddress)).to.be.revertedWith("Address is null.");
      await expect(dc.connect(delegatee).transferDelegatee(ZeroAddress)).to.be.revertedWith("Address is null.");
    });
    it("check transferDelegator/transferDelegatee", async function () {
      const { delegator, delegatee, dc } = await loadFixture(delegatorTestFixture);

      await dc.connect(delegator).transferDelegator(delegatee.address);
      await dc.connect(delegatee).transferDelegatee(delegator.address);

      expect(await dc.getRoleMember(await dc.DELEGATOR_ROLE(), 0)).to.equal(delegatee.address);
      expect(await dc.getRoleMember(await dc.DELEGATEE_ROLE(), 0)).to.equal(delegator.address);
    });
  });
  describe("Delegation", function () {
    it("#delegate: msg.value should be greater than 0", async function () {
      const { delegator, dc } = await loadFixture(delegatorTestFixture);

      await expect(dc.connect(delegator).delegate({ value: 0 })).to.be.revertedWith("Delegation can't be 0.");
    });
    it("#delegate: successfully delegate", async function () {
      const { delegator, dc, pd } = await loadFixture(delegatorTestFixture);

      await expect(dc.connect(delegator).delegate({ value: 1 }))
        .to.emit(dc, "Delegate")
        .withArgs(1);

      expect(await dc.delegation()).to.equal(1);
      expect(await pd.balanceOf(dc.target)).to.equal(1);
    });
  });
  describe("Withdrawal/Claim", function () {
    let fixture: Awaited<ReturnType<typeof delegatorTestFixture>>;
    this.beforeEach(async function () {
      fixture = await loadFixture(delegatorTestFixture);
      const { delegator, dc, pd } = fixture;

      await dc.connect(delegator).delegate({ value: parseEther("1") });

      // Get 1 KAIA as reward
      await setBalance(await pd.getAddress(), parseEther("1"));
    });
    it("#withdrawDelegation: can't withdraw more than delegation", async function () {
      const { delegator, dc } = fixture;

      await expect(dc.connect(delegator).withdrawDelegation(delegator.address, parseEther("2"))).to.be.revertedWith(
        "Insufficient delegation.",
      );
    });
    it("#withdrawDelegation: successfully withdraw delegation", async function () {
      const { delegator, dc, pd } = fixture;

      await expect(dc.connect(delegator).withdrawDelegation(delegator.address, parseEther("1")))
        .to.emit(dc, "WithdrawDelegation")
        .withArgs(delegator.address, parseEther("1"), 0);

      // Check _delegationWithdrawalIds
      expect(await dc.delegationWithdrawalIds()).to.deep.equal([0]);
      expect(await dc.delegation()).to.equal(0);
      expect(await dc.withdrawableReward()).to.equal(parseEther("1"));
      expect(await pd.balanceOf(dc.target)).to.equal(parseEther("0.5"));
    });
    it("withdrawReward: can't withdraw more than reward", async function () {
      const { delegatee, dc } = fixture;

      // Check withdrawable reward
      expect(await dc.withdrawableReward()).to.equal(parseEther("1"));

      await expect(dc.connect(delegatee).withdrawReward(delegatee.address, parseEther("2"))).to.be.revertedWith(
        "Insufficient withdrawable reward.",
      );
    });
    it("withdrawReward: successfully withdraw reward", async function () {
      const { delegatee, dc } = fixture;

      await expect(dc.connect(delegatee).withdrawReward(delegatee.address, parseEther("1")))
        .to.emit(dc, "WithdrawReward")
        .withArgs(delegatee.address, parseEther("1"), 0);

      // Check _rewardWithdrawalIds
      expect(await dc.rewardWithdrawalIds()).to.deep.equal([0]);
      expect(await dc.withdrawableReward()).to.equal(0);
    });
    it("claimDelegation: can't claim with invalid id", async function () {
      const { delegator, dc } = fixture;

      await dc.connect(delegator).withdrawDelegation(delegator.address, parseEther("1"));

      await expect(dc.connect(delegator).claimDelegation(1)).to.be.revertedWith(
        "Delegation withdrawal id is not valid.",
      );
    });
    it("claimDelegation: claim canceled after withdrawable time", async function () {
      const { delegator, cn, dc, pd } = fixture;

      await dc.connect(delegator).withdrawDelegation(delegator.address, parseEther("1"));

      await addTime(WEEK * 2);

      expect(await dc.delegation()).to.equal(0);

      await expect(dc.connect(delegator).claimDelegation(0))
        .to.emit(dc, "ClaimDelegationFailed")
        .withArgs(0)
        .to.emit(cn, "CancelApprovedStakingWithdrawal")
        .withArgs(0, delegator.address, parseEther("1"));

      // Delegation should be increased
      expect(await dc.delegation()).to.equal(parseEther("1"));
      expect(await pd.balanceOf(dc.target)).to.equal(parseEther("1"));
    });
    it("claimDelegation: successfully claim delegation", async function () {
      const { delegator, cn, dc } = fixture;

      await dc.connect(delegator).withdrawDelegation(delegator.address, parseEther("1"));

      await addTime(WEEK);

      await expect(dc.connect(delegator).claimDelegation(0))
        .to.emit(dc, "ClaimDelegation")
        .withArgs(0)
        .to.emit(cn, "WithdrawApprovedStaking")
        .withArgs(0, delegator.address, parseEther("1"));

      expect(await dc.delegation()).to.equal(parseEther("0"));
    });
    it("claimReward: can't claim with invalid id", async function () {
      const { delegatee, dc } = fixture;

      await dc.connect(delegatee).withdrawReward(delegatee.address, parseEther("1"));

      await expect(dc.connect(delegatee).claimReward(1)).to.be.revertedWith("Reward withdrawal id is not valid.");
    });
    it("claimReward: claim canceled after withdrawable time", async function () {
      const { delegatee, cn, dc } = fixture;

      await dc.connect(delegatee).withdrawReward(delegatee.address, parseEther("1"));

      await addTime(WEEK * 2);

      await expect(dc.connect(delegatee).claimReward(0))
        .to.emit(dc, "ClaimRewardFailed")
        .withArgs(0)
        .to.emit(cn, "CancelApprovedStakingWithdrawal")
        .withArgs(0, delegatee.address, parseEther("1"));
    });
    it("claimReward: successfully claim reward", async function () {
      const { delegatee, cn, dc, pd } = fixture;

      await dc.connect(delegatee).withdrawReward(delegatee.address, parseEther("1"));

      await addTime(WEEK);

      await expect(dc.connect(delegatee).claimReward(0))
        .to.emit(dc, "ClaimReward")
        .withArgs(0)
        .to.emit(cn, "WithdrawApprovedStaking")
        .withArgs(0, delegatee.address, parseEther("1"));

      expect(await pd.balanceOf(dc.target)).to.equal(parseEther("0.5"));
      expect(await dc.withdrawableReward()).to.equal(0);
    });
  });
  describe("Getters", function () {
    let fixture: Awaited<ReturnType<typeof delegatorTestFixture>>;
    this.beforeEach(async function () {
      fixture = await loadFixture(delegatorTestFixture);
      const { delegator, delegatee, dc, pd } = fixture;

      await dc.connect(delegator).delegate({ value: parseEther("1") });

      // Get 1 KAIA as reward
      await setBalance(await pd.getAddress(), parseEther("1"));

      // 0, 2: delegation withdrawal
      // 1, 3: reward withdrawal
      await dc.connect(delegator).withdrawDelegation(delegator.address, parseEther("0.5"));
      await dc.connect(delegatee).withdrawReward(delegatee.address, parseEther("0.3"));
      await dc.connect(delegator).withdrawDelegation(delegator.address, parseEther("0.2"));
      await dc.connect(delegatee).withdrawReward(delegatee.address, parseEther("0.2"));
    });
    it("withdrawal ids", async function () {
      const { dc } = fixture;

      expect(await dc.delegationWithdrawalIds()).to.deep.equal([0, 2]);
      expect(await dc.rewardWithdrawalIds()).to.deep.equal([1, 3]);
    });
    it("delegation", async function () {
      const { dc } = fixture;

      expect(await dc.delegation()).to.equal(parseEther("0.3"));

      await addTime(WEEK);

      expect(await dc.claimDelegation(0))
        .to.emit(dc, "ClaimDelegation")
        .withArgs(0);
      expect(await dc.delegation()).to.equal(parseEther("0.3"));

      await addTime(WEEK);

      expect(await dc.claimDelegation(2))
        .to.emit(dc, "ClaimDelegation")
        .withArgs(2);
      expect(await dc.delegation()).to.equal(parseEther("0.5"));
    });
  });
});
