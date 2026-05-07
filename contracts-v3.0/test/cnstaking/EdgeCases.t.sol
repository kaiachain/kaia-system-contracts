// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CnStakingBase} from "./CnStakingBase.t.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {ICnStaking} from "../../src/CnStaking/CnStakingV4/interfaces/ICnStaking.sol";
import {CnStakingV4Factory} from "../../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";
import {PublicDelegation} from "../../src/PublicDelegation/PublicDelegation.sol";
import {IPublicDelegation} from "../../src/PublicDelegation/interfaces/IPublicDelegation.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

/* ================================================================
 *  Helper: contract that reverts on receive
 * ================================================================ */

contract RevertOnReceive {
    receive() external payable {
        revert("no receive");
    }
}

/* ================================================================
 *  CnStaking Initialization Edge Cases
 * ================================================================ */

contract CnStaking_Init_EdgeCases is CnStakingBase {
    function test_initializeWithPD_revertsOnBaseCnStakingMismatch() public {
        // Deploy two raw CnStaking proxies
        address cnProxy1 = address(new BeaconProxy(address(cnBeacon), ""));
        address cnProxy2 = address(new BeaconProxy(address(cnBeacon), ""));

        // Deploy PD proxy and initialize it with cnProxy1
        address pdProxy = address(new BeaconProxy(address(pdBeacon), ""));
        PublicDelegation(payable(pdProxy)).initialize(
            cnProxy1,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TestGC"
            })
        );

        // Try to initializeWithPD on cnProxy2 with PD that points to cnProxy1 → should revert
        vm.expectRevert(ICnStaking.BaseCnStakingMismatch.selector);
        CnStakingV4(payable(cnProxy2)).initializeWithPD(owner, pdProxy);
    }

    function test_initializeWithPD_succeedsWhenPDMatchesThis() public {
        // Deploy raw proxies
        address cnProxy = address(new BeaconProxy(address(cnBeacon), ""));
        address pdProxy = address(new BeaconProxy(address(pdBeacon), ""));

        // Initialize PD pointing to cnProxy
        PublicDelegation(payable(pdProxy)).initialize(
            cnProxy,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TestGC"
            })
        );

        // initializeWithPD should succeed
        CnStakingV4(payable(cnProxy)).initializeWithPD(owner, pdProxy);

        assertEq(CnStakingV4(payable(cnProxy)).publicDelegation(), pdProxy);
    }
}

/* ================================================================
 *  CnStaking Unstaking Edge Cases
 * ================================================================ */

contract CnStaking_Unstaking_EdgeCases is CnStakingBase {
    CnStakingV4 internal cn;

    function setUp() public override {
        super.setUp();
        cn = _deployCnStaking(owner);

        // Stake 100 ether
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        cn.delegate{value: 100 ether}();
    }

    function test_approveWithdrawal_exactStakingAmount() public {
        // Approve exactly the full staking amount
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 100 ether);

        assertEq(cn.unstaking(), 100 ether);

        // Trying to approve even 1 more wei should revert
        vm.prank(owner);
        vm.expectRevert(ICnStaking.InvalidValue.selector);
        cn.approveStakingWithdrawal(user1, 1);

        // But can still withdraw the approved 100
        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(owner);
        cn.withdrawApprovedStaking(id);
        assertEq(cn.staking(), 0);
        assertEq(cn.unstaking(), 0);
    }

    function test_withdrawApprovedStaking_exactWithdrawableBoundary() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        (, , uint256 withdrawableFrom, ) = cn.getApprovedStakingWithdrawalInfo(id);

        // 1 second before withdrawable → reverts
        vm.warp(withdrawableFrom - 1);
        vm.prank(owner);
        vm.expectRevert(ICnStaking.NotWithdrawableYet.selector);
        cn.withdrawApprovedStaking(id);

        // Exact withdrawableFrom → executes
        vm.warp(withdrawableFrom);
        vm.prank(owner);
        cn.withdrawApprovedStaking(id);

        (, , , ICnStaking.WithdrawalStakingState state) = cn.getApprovedStakingWithdrawalInfo(id);
        assertEq(uint256(state), uint256(ICnStaking.WithdrawalStakingState.Transferred));
    }

    function test_withdrawApprovedStaking_exactAutoCancelBoundary() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        (, , uint256 withdrawableFrom, ) = cn.getApprovedStakingWithdrawalInfo(id);
        uint256 withdrawableUntil = withdrawableFrom + STAKE_LOCKUP;

        // 1 second before auto-cancel → still executes
        vm.warp(withdrawableUntil - 1);
        vm.prank(owner);
        cn.withdrawApprovedStaking(id);

        (, , , ICnStaking.WithdrawalStakingState state) = cn.getApprovedStakingWithdrawalInfo(id);
        assertEq(uint256(state), uint256(ICnStaking.WithdrawalStakingState.Transferred));
    }

    function test_withdrawApprovedStaking_autoCancelsAtExactBoundary() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        (, , uint256 withdrawableFrom, ) = cn.getApprovedStakingWithdrawalInfo(id);
        uint256 withdrawableUntil = withdrawableFrom + STAKE_LOCKUP;

        // At exact withdrawableUntil → auto-cancel
        vm.warp(withdrawableUntil);
        vm.prank(owner);
        cn.withdrawApprovedStaking(id);

        (, , , ICnStaking.WithdrawalStakingState state) = cn.getApprovedStakingWithdrawalInfo(id);
        assertEq(uint256(state), uint256(ICnStaking.WithdrawalStakingState.Canceled));
        assertEq(cn.staking(), 100 ether); // Staking unchanged on cancel
    }

    function test_withdrawApprovedStaking_revertsWhenTransferFails() public {
        RevertOnReceive revertReceiver = new RevertOnReceive();

        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(address(revertReceiver), 10 ether);

        vm.warp(block.timestamp + STAKE_LOCKUP);

        vm.prank(owner);
        vm.expectRevert(ICnStaking.TransferFailed.selector);
        cn.withdrawApprovedStaking(id);
    }

    function test_withdrawApprovedStaking_multipleSequentialWithdrawals() public {
        vm.startPrank(owner);
        uint256 id0 = cn.approveStakingWithdrawal(user1, 30 ether);
        uint256 id1 = cn.approveStakingWithdrawal(user1, 40 ether);
        uint256 id2 = cn.approveStakingWithdrawal(user1, 30 ether);
        vm.stopPrank();

        assertEq(cn.unstaking(), 100 ether);

        vm.warp(block.timestamp + STAKE_LOCKUP);

        // Withdraw in reverse order
        vm.startPrank(owner);
        cn.withdrawApprovedStaking(id2);
        assertEq(cn.staking(), 70 ether);
        assertEq(cn.unstaking(), 70 ether);

        cn.withdrawApprovedStaking(id1);
        assertEq(cn.staking(), 30 ether);
        assertEq(cn.unstaking(), 30 ether);

        cn.withdrawApprovedStaking(id0);
        assertEq(cn.staking(), 0);
        assertEq(cn.unstaking(), 0);
        vm.stopPrank();
    }

    function test_cancelApprovedStakingWithdrawal_afterTransferred_reverts() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(owner);
        cn.withdrawApprovedStaking(id);

        // Try to cancel an already-transferred request
        vm.prank(owner);
        vm.expectRevert(ICnStaking.InvalidWithdrawalState.selector);
        cn.cancelApprovedStakingWithdrawal(id);
    }

    function test_withdrawApprovedStaking_afterCanceled_reverts() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.prank(owner);
        cn.cancelApprovedStakingWithdrawal(id);

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(owner);
        vm.expectRevert(ICnStaking.InvalidWithdrawalState.selector);
        cn.withdrawApprovedStaking(id);
    }

    function test_approveWithdrawal_afterPartialCancel_canApproveMore() public {
        // Approve 80, cancel it, then approve 100
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 80 ether);
        assertEq(cn.unstaking(), 80 ether);

        vm.prank(owner);
        cn.cancelApprovedStakingWithdrawal(id);
        assertEq(cn.unstaking(), 0);

        // Now can approve full 100
        vm.prank(owner);
        cn.approveStakingWithdrawal(user1, 100 ether);
        assertEq(cn.unstaking(), 100 ether);
    }
}

/* ================================================================
 *  CnStaking Redelegation + Unstaking Interaction
 * ================================================================ */

contract CnStaking_Redelegation_EdgeCases is CnStakingBase {
    CnStakingV4 internal sourceCn;
    PublicDelegation internal sourcePd;
    CnStakingV4 internal targetCn;
    PublicDelegation internal targetPd;

    function setUp() public override {
        super.setUp();

        (sourceCn, sourcePd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "SourceGC"
            })
        );

        address targetOwner = makeAddr("targetOwner");
        (targetCn, targetPd) = _deployCnStakingWithPD(
            targetOwner,
            IPublicDelegation.PDConstructorArgs({
                owner: targetOwner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TargetGC"
            })
        );

        _stakeViaPD(sourcePd, user1, 100 ether);
    }

    function test_redelegate_withPendingUnstaking() public {
        // Approve a withdrawal of 30 ether
        vm.prank(address(sourcePd));
        sourceCn.approveStakingWithdrawal(user1, 30 ether);
        assertEq(sourceCn.unstaking(), 30 ether);

        // Redelegate up to staking - unstaking = 100 + INITIAL_LOCKUP - 30
        // Try to redelegate exactly the available amount
        uint256 available = sourceCn.staking() - sourceCn.unstaking();

        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), available);

        assertEq(sourceCn.staking(), 30 ether); // Only unstaking amount remains
        assertEq(sourceCn.unstaking(), 30 ether);
    }

    function test_redelegate_withPendingUnstaking_exceedsLimit() public {
        // Approve a withdrawal of 30 ether
        vm.prank(address(sourcePd));
        sourceCn.approveStakingWithdrawal(user1, 30 ether);

        uint256 available = sourceCn.staking() - sourceCn.unstaking();

        // Try to redelegate 1 wei more than available → reverts
        vm.prank(address(sourcePd));
        vm.expectRevert(ICnStaking.InvalidValue.selector);
        sourceCn.redelegate(user1, address(targetCn), available + 1);
    }

    function test_redelegate_thenWithdrawPendingSucceeds() public {
        // Approve withdrawal of 30
        vm.prank(address(sourcePd));
        uint256 id = sourceCn.approveStakingWithdrawal(user1, 30 ether);
        assertEq(sourceCn.unstaking(), 30 ether);

        // Redelegate 70 (leaving exactly 30 for the pending withdrawal)
        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), 70 ether + INITIAL_LOCKUP);

        assertEq(sourceCn.staking(), 30 ether);
        assertEq(sourceCn.unstaking(), 30 ether);

        // Withdraw the pending 30 → should succeed
        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(address(sourcePd));
        sourceCn.withdrawApprovedStaking(id);

        assertEq(sourceCn.staking(), 0);
        assertEq(sourceCn.unstaking(), 0);
    }

    function test_redelegate_afterWithdraw_noMoreFunds() public {
        // Approve FULL staking amount (including INITIAL_LOCKUP dead shares' value)
        uint256 totalStaking = sourceCn.staking();
        vm.prank(address(sourcePd));
        uint256 id = sourceCn.approveStakingWithdrawal(user1, totalStaking);
        assertEq(sourceCn.unstaking(), totalStaking);

        // Can't redelegate even 1 wei when everything is unstaking
        vm.prank(address(sourcePd));
        vm.expectRevert(ICnStaking.InvalidValue.selector);
        sourceCn.redelegate(user1, address(targetCn), 1);

        // Cancel the withdrawal → can redelegate again
        vm.prank(address(sourcePd));
        sourceCn.cancelApprovedStakingWithdrawal(id);

        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), 50 ether);
        assertEq(sourceCn.staking(), totalStaking - 50 ether);
    }

    function test_redelegate_cooldownExactBoundary() public {
        // First redelegation
        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), 50 ether);

        uint256 lastRedeleg = targetCn.lastRedelegation(user1);

        // At exact cooldown boundary: lastRedelegation + STAKE_LOCKUP == block.timestamp
        // The check: lastRedelegation[user] + STAKE_LOCKUP > block.timestamp
        // At boundary: lastRedeleg + STAKE_LOCKUP == block.timestamp → not > → should pass
        vm.warp(lastRedeleg + STAKE_LOCKUP);

        // user1 can now redelegate from target
        vm.prank(address(targetPd));
        targetCn.redelegate(user1, address(sourceCn), 10 ether);
    }

    function test_redelegate_cooldown1SecondBefore_reverts() public {
        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), 50 ether);

        uint256 lastRedeleg = targetCn.lastRedelegation(user1);

        // 1 second before cooldown expires
        vm.warp(lastRedeleg + STAKE_LOCKUP - 1);

        vm.prank(address(targetPd));
        vm.expectRevert(ICnStaking.RedelegationCooldown.selector);
        targetCn.redelegate(user1, address(sourceCn), 10 ether);
    }

    function test_redelegate_entireStaking_drainsCnStaking() public {
        uint256 totalStaked = sourceCn.staking();

        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), totalStaked);

        assertEq(sourceCn.staking(), 0);
        assertEq(address(sourceCn).balance, 0);
        assertEq(targetCn.staking(), INITIAL_LOCKUP + totalStaked);
    }
}

/* ================================================================
 *  PublicDelegation Staking Edge Cases
 * ================================================================ */

contract PD_Staking_EdgeCases is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TestGC"
            })
        );
    }

    function test_stake_zeroValue_reverts() public {
        vm.prank(user1);
        vm.expectRevert(IPublicDelegation.StakeAmountTooLow.selector);
        pd.stake{value: 0}();
    }

    function test_receive_zeroValue_reverts() public {
        vm.prank(user1);
        vm.expectRevert(IPublicDelegation.StakeAmountTooLow.selector);
        address(pd).call{value: 0}("");
    }

    function test_stake_multipleUsersWithRewards_proportionalShares() public {
        // user1 stakes 100
        _stakeViaPD(pd, user1, 100 ether);
        // totalSupply = INITIAL_LOCKUP + 100, totalAssets = INITIAL_LOCKUP + 100

        // Reward arrives: 10 ether → totalAssets increases to INITIAL_LOCKUP + 110
        _simulateReward(pd, 10 ether);

        // user2 stakes 110 ether → gets shares at new rate
        // shares = 110 * (INITIAL_LOCKUP + 100) / (INITIAL_LOCKUP + 110)
        // With INITIAL_LOCKUP = 1 ether: shares = 110 * 101 / 111 ≈ 100.09 ether
        _stakeViaPD(pd, user2, 110 ether);

        uint256 user1Shares = pd.balanceOf(user1);
        uint256 user2Shares = pd.balanceOf(user2);

        // Both should have roughly equal shares (user2 paid more but at higher rate)
        // user1: 100 shares, user2: ~100.09 shares
        assertEq(user1Shares, 100 ether);
        assertTrue(user2Shares > 99 ether && user2Shares < 101 ether);

        // Both users' share values should be proportional
        uint256 user1Value = pd.convertToAssets(user1Shares);
        uint256 user2Value = pd.convertToAssets(user2Shares);

        // user1 original 100 + proportional share of 10 ether reward
        assertTrue(user1Value > 100 ether);
        // user2 deposited 110 but got slightly less than 110 worth (reward diluted by deposit)
        assertTrue(user2Value >= 109 ether && user2Value <= 111 ether);
    }

    function test_stakeFor_afterRewards_correctShareRate() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 50 ether);

        // Exchange rate now: totalAssets = INITIAL_LOCKUP + 150, totalSupply = INITIAL_LOCKUP + 100
        uint256 expectedShares = pd.previewDeposit(150 ether);

        vm.deal(user2, 150 ether);
        vm.prank(user2);
        pd.stakeFor{value: 150 ether}(user2);

        assertEq(pd.balanceOf(user2), expectedShares);
    }
}

/* ================================================================
 *  PublicDelegation Withdrawal Edge Cases
 * ================================================================ */

contract PD_Withdrawal_EdgeCases is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TestGC"
            })
        );

        _stakeViaPD(pd, user1, 100 ether);
    }

    function test_withdraw_moreThanBalance_reverts() public {
        // user1 has 100 shares. Try to withdraw 101 ether worth (needs > 100 shares)
        // previewWithdraw(101 ether) = ceil(101 * supply / totalAssets), needs more than user owns
        vm.prank(user1);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        pd.withdraw(user1, 101 ether);
    }

    function test_redeem_moreThanBalance_reverts() public {
        vm.prank(user1);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        pd.redeem(user1, 101 ether);
    }

    function test_cancelWithdrawal_afterRewards_fewerSharesReminted() public {
        // user1 stakes 100, has 100 shares
        // Withdraw 50 ether → burns ceil(50*101/101) = 50 shares (1:1)
        vm.prank(user1);
        pd.withdraw(user1, 50 ether);
        assertEq(pd.balanceOf(user1), 50 ether);

        uint256 requestId = pd.userRequestIds(user1, 0);

        // Rewards arrive: 10 ether
        // Now totalAssets = (101 - 50) + 10 = 61 (staking=101, unstaking=50, pureReward=10)
        _simulateReward(pd, 10 ether);

        // Cancel → re-mint at NEW rate: previewDeposit(50) = floor(50 * 51 / 61) = floor(41.80) = 41
        // Note: rate changed because rewards accrued
        uint256 sharesBefore = pd.balanceOf(user1);
        vm.prank(user1);
        pd.cancelApprovedStakingWithdrawal(requestId);

        uint256 sharesAfter = pd.balanceOf(user1);
        uint256 remintedShares = sharesAfter - sharesBefore;

        // User originally burned 50 shares, but gets back fewer due to rate change
        assertTrue(remintedShares < 50 ether, "Re-minted shares should be less due to reward appreciation");
        // The "lost" shares represent the reward that accrued during the withdrawal period
        // which goes to remaining stakers (including dead shares). This is expected ERC4626 behavior.
    }

    function test_claimAutoCancel_afterRewards_correctSharesReminted() public {
        vm.prank(user1);
        pd.withdraw(user1, 50 ether);
        uint256 requestId = pd.userRequestIds(user1, 0);
        assertEq(pd.balanceOf(user1), 50 ether);

        // Rewards arrive before auto-cancel
        _simulateReward(pd, 20 ether);

        // Warp past 2*STAKE_LOCKUP → auto-cancel
        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);

        uint256 sharesBefore = pd.balanceOf(user1);
        vm.prank(user1);
        pd.claim(requestId);

        uint256 sharesAfter = pd.balanceOf(user1);
        uint256 remintedShares = sharesAfter - sharesBefore;

        // Auto-cancel formula: _convertToShares(_assets, totalSupply(), _totalAssets() - _assets)
        // _totalAssets() after CnStaking auto-cancel = staking - (unstaking - 50) + pureReward
        // The reminted shares reflect the current exchange rate
        assertTrue(remintedShares > 0, "Should re-mint some shares");
        assertTrue(remintedShares < 50 ether, "Fewer shares due to reward appreciation");
    }

    function test_withdraw_cancel_withdraw_again() public {
        // Withdraw → cancel → withdraw cycle
        vm.prank(user1);
        pd.withdraw(user1, 30 ether);
        uint256 id1 = pd.userRequestIds(user1, 0);

        vm.prank(user1);
        pd.cancelApprovedStakingWithdrawal(id1);

        // User should have ~100 shares again (might lose tiny rounding)
        uint256 sharesAfterCancel = pd.balanceOf(user1);
        assertTrue(sharesAfterCancel >= 99 ether, "Should have nearly all shares back");

        // Withdraw again
        vm.prank(user1);
        pd.withdraw(user1, 30 ether);
        uint256 id2 = pd.userRequestIds(user1, 1);
        assertTrue(id2 > id1, "Request ID should be monotonically increasing");

        // Claim the second withdrawal
        vm.warp(block.timestamp + STAKE_LOCKUP);
        uint256 balBefore = user1.balance;
        vm.prank(user1);
        pd.claim(id2);
        assertEq(user1.balance - balBefore, 30 ether);
    }

    function test_claim_afterManualCancel_reverts() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);
        uint256 requestId = pd.userRequestIds(user1, 0);

        // Manually cancel via PD
        vm.prank(user1);
        pd.cancelApprovedStakingWithdrawal(requestId);

        // Try to claim the canceled request
        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(user1);
        vm.expectRevert(ICnStaking.InvalidWithdrawalState.selector);
        pd.claim(requestId);
    }

    function test_getCurrentWithdrawalRequestState_afterClaimed() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);
        uint256 requestId = pd.userRequestIds(user1, 0);

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(user1);
        pd.claim(requestId);

        assertEq(
            uint256(pd.getCurrentWithdrawalRequestState(requestId)),
            uint256(IPublicDelegation.WithdrawalRequestState.Withdrawn)
        );
    }

    function test_getCurrentWithdrawalRequestState_afterCanceled() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);
        uint256 requestId = pd.userRequestIds(user1, 0);

        vm.prank(user1);
        pd.cancelApprovedStakingWithdrawal(requestId);

        assertEq(
            uint256(pd.getCurrentWithdrawalRequestState(requestId)),
            uint256(IPublicDelegation.WithdrawalRequestState.Canceled)
        );
    }

    function test_multipleUsers_withdrawAndClaim_independently() public {
        _stakeViaPD(pd, user2, 100 ether);

        // Both users withdraw
        vm.prank(user1);
        pd.withdraw(user1, 30 ether);
        uint256 id1 = pd.userRequestIds(user1, 0);

        vm.prank(user2);
        pd.withdraw(user2, 50 ether);
        uint256 id2 = pd.userRequestIds(user2, 0);

        assertEq(cn.unstaking(), 80 ether);

        // user1 claims, user2 cancels
        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256 user1Bal = user1.balance;
        vm.prank(user1);
        pd.claim(id1);
        assertEq(user1.balance - user1Bal, 30 ether);

        vm.prank(user2);
        pd.cancelApprovedStakingWithdrawal(id2);

        // user2 should get shares back
        assertTrue(pd.balanceOf(user2) > 90 ether);
        assertEq(cn.unstaking(), 0);
    }

    function test_redeem_thenTransferShares_newOwnerCanWithdraw() public {
        // user1 transfers shares to user2
        vm.prank(user1);
        pd.transfer(user2, 40 ether);

        // user2 can now withdraw using received shares
        vm.prank(user2);
        pd.withdraw(user2, 40 ether);

        uint256 requestId = pd.userRequestIds(user2, 0);

        vm.warp(block.timestamp + STAKE_LOCKUP);
        uint256 balBefore = user2.balance;
        vm.prank(user2);
        pd.claim(requestId);
        assertEq(user2.balance - balBefore, 40 ether);
    }
}

/* ================================================================
 *  PublicDelegation Redelegation Edge Cases
 * ================================================================ */

contract PD_Redelegation_EdgeCases is CnStakingBase {
    CnStakingV4 internal sourceCn;
    PublicDelegation internal sourcePd;
    CnStakingV4 internal targetCn;
    PublicDelegation internal targetPd;

    function setUp() public override {
        super.setUp();

        (sourceCn, sourcePd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 1000, // 10% commission
                gcName: "SourceGC"
            })
        );

        address targetOwner = makeAddr("targetOwner");
        (targetCn, targetPd) = _deployCnStakingWithPD(
            targetOwner,
            IPublicDelegation.PDConstructorArgs({
                owner: targetOwner,
                commissionTo: commissionTo,
                commissionRate: 500, // 5% commission
                gcName: "TargetGC"
            })
        );

        _stakeViaPD(sourcePd, user1, 100 ether);
    }

    function test_redelegateByAssets_sweepsRewardsFirst() public {
        _simulateReward(sourcePd, 20 ether);

        uint256 commissionBalBefore = commissionTo.balance;

        vm.prank(user1);
        sourcePd.redelegateByAssets(address(targetCn), 40 ether);

        // Commission should have been collected during sweep: 20 * 10% = 2
        assertEq(commissionTo.balance - commissionBalBefore, 2 ether);

        // Source staking: INITIAL_LOCKUP + 100 + 18 (reward minus commission) - 40 (redelegated)
        assertEq(sourceCn.staking(), INITIAL_LOCKUP + 78 ether);
    }

    function test_redelegateByShares_afterRewards_correctFloorAssets() public {
        // After rewards, exchange rate changes. redelegateByShares should use floor rounding.
        _simulateReward(sourcePd, 10 ether);

        // Trigger a sweep to move reward into staking
        sourcePd.sweep();
        // After sweep: staking = INITIAL_LOCKUP + 100 + 9 (10 - 1 commission) = INITIAL_LOCKUP + 109
        // totalSupply = INITIAL_LOCKUP + 100
        // rate = (INITIAL_LOCKUP + 109) / (INITIAL_LOCKUP + 100) ≈ 1.089...

        uint256 sharesToRedelegate = 50 ether;
        uint256 expectedAssets = sourcePd.previewRedeem(sharesToRedelegate);

        vm.prank(user1);
        sourcePd.redelegateByShares(address(targetCn), sharesToRedelegate);

        // Source should have lost exactly expectedAssets
        assertEq(sourceCn.staking(), INITIAL_LOCKUP + 109 ether - expectedAssets);
        assertEq(sourcePd.balanceOf(user1), 50 ether); // Had 100, redelegated 50
    }

    function test_redelegateByAssets_moreThanUserOwns_reverts() public {
        uint256 maxWithdraw = sourcePd.maxWithdraw(user1);

        vm.prank(user1);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        sourcePd.redelegateByAssets(address(targetCn), maxWithdraw + 1 ether);
    }

    function test_redelegateByShares_moreThanUserOwns_reverts() public {
        uint256 maxRedeem = sourcePd.maxRedeem(user1);

        vm.prank(user1);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        sourcePd.redelegateByShares(address(targetCn), maxRedeem + 1);
    }

    function test_redelegate_withPendingWithdrawal_respectsLimit() public {
        // Withdraw 50 via PD → CnStaking.unstaking = 50
        vm.prank(user1);
        sourcePd.withdraw(user1, 50 ether);
        assertEq(sourceCn.unstaking(), 50 ether);

        // Available for redelegation: staking - unstaking = (INITIAL_LOCKUP + 100) - 50
        uint256 available = sourceCn.staking() - sourceCn.unstaking();

        // Redelegate more than available → reverts (PD burns more shares than user owns)
        vm.prank(user1);
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        sourcePd.redelegateByAssets(address(targetCn), available + 1);

        // Redelegate exactly available → succeeds
        // But user1 only has 50 shares left. previewWithdraw(available) might need more.
        // With 1:1 rate: available ~= 51 ether (INITIAL_LOCKUP + 50), but user has 50 shares.
        // So user can redelegate up to ~50 ether worth.
        uint256 maxUserRedelegation = sourcePd.maxWithdraw(user1);
        assertGt(maxUserRedelegation, 0, "should have redelegation budget");
        vm.prank(user1);
        sourcePd.redelegateByAssets(address(targetCn), maxUserRedelegation);
    }
}

/* ================================================================
 *  PublicDelegation Commission Edge Cases
 * ================================================================ */

contract PD_Commission_EdgeCases is CnStakingBase {
    function test_commission_100percent() public {
        (CnStakingV4 cn, PublicDelegation pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 1e4, // 100%
                gcName: "FullCommission"
            })
        );

        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 10 ether);

        uint256 commissionBalBefore = commissionTo.balance;
        uint256 stakingBefore = cn.staking();

        pd.sweep();

        // All reward goes to commission
        assertEq(commissionTo.balance - commissionBalBefore, 10 ether);
        // No reward staked (all taken as commission)
        assertEq(cn.staking(), stakingBefore);

        // Shares should not appreciate (totalAssets unchanged)
        assertEq(pd.totalAssets(), INITIAL_LOCKUP + 100 ether);

        // reward() should return 0 since 100% is commission
        assertEq(pd.reward(), 0);
    }

    function test_commission_precisionSmallReward() public {
        (, PublicDelegation pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 3333, // 33.33%
                gcName: "PrecisionTest"
            })
        );

        _stakeViaPD(pd, user1, 100 ether);

        // Small reward: 3 wei
        _simulateReward(pd, 3);

        uint256 commissionBalBefore = commissionTo.balance;
        pd.sweep();

        // commission = floor(3 * 3333 / 10000) = floor(0.9999) = 0
        // Very small rewards may produce zero commission (floor rounding)
        assertEq(commissionTo.balance - commissionBalBefore, 0);
    }

    function test_commission_1wei_reward_with_high_rate() public {
        (, PublicDelegation pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 9999, // 99.99%
                gcName: "HighCommission"
            })
        );

        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 1);

        uint256 commissionBalBefore = commissionTo.balance;
        pd.sweep();

        // commission = floor(1 * 9999 / 10000) = floor(0.9999) = 0
        // Even 99.99% rate yields 0 commission on 1 wei
        assertEq(commissionTo.balance - commissionBalBefore, 0);
    }

    function test_updateCommissionRate_to100Percent() public {
        (, PublicDelegation pd) = _deployCnStakingWithPDDefaults();

        vm.prank(owner);
        pd.updateCommissionRate(1e4);

        assertEq(pd.commissionRate(), 1e4);
    }

    function test_updateCommissionRate_toZero() public {
        (, PublicDelegation pd) = _deployCnStakingWithPDDefaults();

        vm.prank(owner);
        pd.updateCommissionRate(0);

        assertEq(pd.commissionRate(), 0);
    }
}

/* ================================================================
 *  PublicDelegation ERC4626 Math Edge Cases
 * ================================================================ */

contract PD_ERC4626_EdgeCases is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0, // 0% for clean math
                gcName: "TestGC"
            })
        );

        _stakeViaPD(pd, user1, 100 ether);
    }

    function test_getters_afterRewards_nonOneToOneRatio() public {
        _simulateReward(pd, 50 ether);

        // totalSupply = INITIAL_LOCKUP + 100
        // totalAssets = INITIAL_LOCKUP + 100 + 50 = INITIAL_LOCKUP + 150
        uint256 totalAssets = pd.totalAssets();
        uint256 totalSupply = pd.totalSupply();

        assertEq(totalAssets, INITIAL_LOCKUP + 150 ether);
        assertEq(totalSupply, INITIAL_LOCKUP + 100 ether);

        // 1 share is worth more than 1 KAIA now
        uint256 oneShareValue = pd.convertToAssets(1 ether);
        assertTrue(oneShareValue > 1 ether);

        // 1 KAIA buys less than 1 share now
        uint256 oneKaiaShares = pd.convertToShares(1 ether);
        assertTrue(oneKaiaShares < 1 ether);
    }

    function test_previewWithdraw_ceilRounding_vs_previewRedeem_floorRounding() public {
        _simulateReward(pd, 50 ether);

        // Trigger sweep to lock in the rate
        pd.sweep();

        // previewWithdraw uses ceil rounding (user burns MORE shares)
        uint256 assets = 10 ether;
        uint256 withdrawShares = pd.previewWithdraw(assets);

        // previewRedeem uses floor rounding (user gets FEWER assets)
        uint256 redeemAssets = pd.previewRedeem(withdrawShares);

        // withdraw(assets) burns ceil shares → assets_from_shares ≥ assets
        assertTrue(redeemAssets >= assets, "Ceil/floor should ensure vault safety");
    }

    function test_convertToShares_roundTrip_neverProfits() public {
        _simulateReward(pd, 33 ether); // Create non-round exchange rate
        pd.sweep();

        uint256 originalAssets = 7 ether;

        // assets → shares → assets round-trip
        uint256 shares = pd.convertToShares(originalAssets);
        uint256 roundTripAssets = pd.convertToAssets(shares);

        // ERC4626 invariant: round-trip NEVER profits the user (floor rounding favors vault)
        assertTrue(roundTripAssets <= originalAssets, "Round-trip should never increase assets");
        // Loss is bounded by exchange rate (totalAssets/totalSupply).
        // With rate ~1.33, loss can be a few wei due to two floor divisions.
        assertTrue(shares > 0, "Should get some shares");
    }

    function test_maxWithdraw_maxRedeem_consistent() public {
        _simulateReward(pd, 50 ether);
        pd.sweep();

        uint256 maxW = pd.maxWithdraw(user1);
        uint256 maxR = pd.maxRedeem(user1);

        // maxRedeem should equal user's share balance
        assertEq(maxR, pd.balanceOf(user1));

        // maxWithdraw should equal the assets for maxRedeem shares
        assertEq(maxW, pd.previewRedeem(maxR));
    }
}

/* ================================================================
 *  Cross-Contract Interaction Edge Cases
 * ================================================================ */

contract CrossContract_EdgeCases is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TestGC"
            })
        );

        _stakeViaPD(pd, user1, 100 ether);
    }

    function test_directCnStaking_ownerCannotUnstake_whenPDSet() public {
        // Owner should not be able to approve/cancel/withdraw directly on CnStaking when PD is set
        vm.prank(owner);
        vm.expectRevert(ICnStaking.NotUnstakingManager.selector);
        cn.approveStakingWithdrawal(user1, 10 ether);
    }

    function test_directCnStaking_userCannotStake_whenPDSet() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        vm.expectRevert(ICnStaking.NotStaker.selector);
        cn.delegate{value: 10 ether}();
    }

    function test_fullLifecycle_stakeWithdrawClaimMultipleUsers() public {
        _stakeViaPD(pd, user2, 200 ether);

        // Rewards accumulate
        _simulateReward(pd, 30 ether);

        // user1 withdraws 50 ether
        vm.prank(user1);
        pd.withdraw(user1, 50 ether);
        uint256 id1 = pd.userRequestIds(user1, 0);

        // user2 withdraws 100 ether
        vm.prank(user2);
        pd.withdraw(user2, 100 ether);
        uint256 id2 = pd.userRequestIds(user2, 0);

        // More rewards
        _simulateReward(pd, 20 ether);

        // user1 claims
        vm.warp(block.timestamp + STAKE_LOCKUP);
        uint256 bal1Before = user1.balance;
        vm.prank(user1);
        pd.claim(id1);
        assertEq(user1.balance - bal1Before, 50 ether);

        // user2 cancels → gets shares back at current rate
        uint256 shares2Before = pd.balanceOf(user2);
        vm.prank(user2);
        pd.cancelApprovedStakingWithdrawal(id2);
        assertTrue(pd.balanceOf(user2) > shares2Before);

        // Invariant: total value is conserved (minus withdrawn)
        uint256 totalValue = cn.staking() + address(pd).balance;
        // Should be original deposits + rewards - withdrawn
        // 100 + INITIAL_LOCKUP + 200 + 30 + 20 - 50 = 300 + INITIAL_LOCKUP
        assertEq(totalValue, 300 ether + INITIAL_LOCKUP);
    }

    function test_fullRedelegation_lifecycle() public {
        CnStakingV4 targetCn;
        PublicDelegation targetPd;
        (targetCn, targetPd) = _deployCnStakingWithPD(
            makeAddr("targetOwner"),
            IPublicDelegation.PDConstructorArgs({
                owner: makeAddr("targetOwner"),
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TargetGC"
            })
        );

        uint256 sourceStakingBefore = cn.staking();
        uint256 targetStakingBefore = targetCn.staking();

        // Redelegate 60 ether from source to target
        vm.prank(user1);
        pd.redelegateByAssets(address(targetCn), 60 ether);

        // Source lost 60, target gained 60
        assertEq(cn.staking(), sourceStakingBefore - 60 ether);
        assertEq(targetCn.staking(), targetStakingBefore + 60 ether);

        // user1 has 60 shares in source, 60 shares in target (approx)
        assertEq(pd.balanceOf(user1), 40 ether);
        assertEq(targetPd.balanceOf(user1), 60 ether);

        // After cooldown, redelegate back
        vm.warp(block.timestamp + STAKE_LOCKUP);

        vm.prank(user1);
        targetPd.redelegateByAssets(address(cn), 30 ether);

        assertEq(cn.staking(), sourceStakingBefore - 30 ether);
        assertEq(targetCn.staking(), targetStakingBefore + 30 ether);
    }
}

/* ================================================================
 *  Getter Edge Cases
 * ================================================================ */

contract CnStaking_Getters_EdgeCases is CnStakingBase {
    CnStakingV4 internal cn;

    function setUp() public override {
        super.setUp();
        cn = _deployCnStaking(owner);

        vm.deal(user1, 100 ether);
        vm.prank(user1);
        cn.delegate{value: 100 ether}();
    }

    function test_getApprovedStakingWithdrawalIds_emptyRange() public view {
        // No withdrawals exist
        uint256[] memory ids = cn.getApprovedStakingWithdrawalIds(0, 0, ICnStaking.WithdrawalStakingState.Unknown);
        assertEq(ids.length, 0);
    }

    function test_getApprovedStakingWithdrawalIds_fromGTE_to() public {
        vm.prank(owner);
        cn.approveStakingWithdrawal(user1, 10 ether);

        // from >= count → empty
        uint256[] memory ids = cn.getApprovedStakingWithdrawalIds(5, 0, ICnStaking.WithdrawalStakingState.Unknown);
        assertEq(ids.length, 0);
    }

    function test_getApprovedStakingWithdrawalIds_rangeQuery() public {
        vm.startPrank(owner);
        cn.approveStakingWithdrawal(user1, 10 ether); // id 0
        cn.approveStakingWithdrawal(user1, 10 ether); // id 1
        cn.approveStakingWithdrawal(user1, 10 ether); // id 2
        cn.cancelApprovedStakingWithdrawal(1); // Cancel id 1
        vm.stopPrank();

        // Query range [0, 2) — ids 0 and 1
        uint256[] memory unknownInRange = cn.getApprovedStakingWithdrawalIds(
            0,
            2,
            ICnStaking.WithdrawalStakingState.Unknown
        );
        assertEq(unknownInRange.length, 1);
        assertEq(unknownInRange[0], 0);

        uint256[] memory canceledInRange = cn.getApprovedStakingWithdrawalIds(
            0,
            2,
            ICnStaking.WithdrawalStakingState.Canceled
        );
        assertEq(canceledInRange.length, 1);
        assertEq(canceledInRange[0], 1);
    }

    function test_getApprovedStakingWithdrawalInfo_nonExistentId() public view {
        (address to, uint256 value, uint256 withdrawableFrom, ICnStaking.WithdrawalStakingState state) = cn
            .getApprovedStakingWithdrawalInfo(999);

        // Non-existent: all zeros
        assertEq(to, address(0));
        assertEq(value, 0);
        assertEq(withdrawableFrom, 0);
        assertEq(uint256(state), uint256(ICnStaking.WithdrawalStakingState.Unknown));
    }
}

/* ================================================================
 *  Invariant: staking >= unstaking always holds
 * ================================================================ */

contract Invariant_StakingGE_Unstaking is CnStakingBase {
    CnStakingV4 internal cn;

    function setUp() public override {
        super.setUp();
        cn = _deployCnStaking(owner);

        vm.deal(user1, 1000 ether);
        vm.prank(user1);
        cn.delegate{value: 100 ether}();
    }

    function test_invariant_staking_gte_unstaking_afterMultipleOps() public {
        vm.startPrank(owner);

        // Approve 30
        cn.approveStakingWithdrawal(user1, 30 ether);
        assertTrue(cn.staking() >= cn.unstaking(), "invariant broken after approve");

        // Approve 40
        cn.approveStakingWithdrawal(user1, 40 ether);
        assertTrue(cn.staking() >= cn.unstaking(), "invariant broken after second approve");

        // Cancel first
        cn.cancelApprovedStakingWithdrawal(0);
        assertTrue(cn.staking() >= cn.unstaking(), "invariant broken after cancel");

        // Withdraw second
        vm.warp(block.timestamp + STAKE_LOCKUP);
        cn.withdrawApprovedStaking(1);
        assertTrue(cn.staking() >= cn.unstaking(), "invariant broken after withdraw");

        vm.stopPrank();

        // Delegate more
        vm.prank(user1);
        cn.delegate{value: 50 ether}();
        assertTrue(cn.staking() >= cn.unstaking(), "invariant broken after delegate");
    }

    function test_invariant_staking_gte_unstaking_afterAutoCancel() public {
        vm.prank(owner);
        cn.approveStakingWithdrawal(user1, 80 ether);

        // Auto-cancel
        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);
        vm.prank(owner);
        cn.withdrawApprovedStaking(0);

        assertTrue(cn.staking() >= cn.unstaking(), "invariant broken after auto-cancel");
        assertEq(cn.staking(), 100 ether);
        assertEq(cn.unstaking(), 0);
    }
}
