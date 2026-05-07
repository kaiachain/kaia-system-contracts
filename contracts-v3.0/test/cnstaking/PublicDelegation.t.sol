// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CnStakingBase} from "./CnStakingBase.t.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {ICnStaking} from "../../src/CnStaking/CnStakingV4/interfaces/ICnStaking.sol";
import {PublicDelegation} from "../../src/PublicDelegation/PublicDelegation.sol";
import {IPublicDelegation} from "../../src/PublicDelegation/interfaces/IPublicDelegation.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/* ================================================================
 *  Initialization Tests
 * ================================================================ */

contract PD_Initialization is CnStakingBase {
    function test_initialize_setsAllFields() public {
        (CnStakingV4 cn, PublicDelegation pd) = _deployCnStakingWithPDDefaults();

        assertEq(pd.baseCnStaking(), address(cn));
        assertEq(pd.commissionTo(), commissionTo);
        assertEq(pd.commissionRate(), 1000);
        assertEq(pd.owner(), owner);
        assertEq(pd.name(), "TestGC Public Delegated KAIA");
        assertEq(pd.symbol(), "TestGC-pdKAIA");
    }

    function test_constants() public {
        (, PublicDelegation pd) = _deployCnStakingWithPDDefaults();

        assertEq(pd.VERSION(), 2);
        assertEq(keccak256(bytes(pd.CONTRACT_TYPE())), keccak256("PublicDelegation"));
        assertEq(pd.MAX_COMMISSION_RATE(), 1e4);
        assertEq(pd.COMMISSION_DENOMINATOR(), 1e4);
    }

    function test_initialize_cannotCallTwice() public {
        (, PublicDelegation pd) = _deployCnStakingWithPDDefaults();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        pd.initialize(
            address(1),
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "X"
            })
        );
    }

    function test_initialize_revertsOnHighCommission() public {
        vm.expectRevert(IPublicDelegation.CommissionRateTooHigh.selector);
        factory.deployCnStakingWithPD{value: INITIAL_LOCKUP}(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 1e4 + 1,
                gcName: "X"
            })
        );
    }
}

/* ================================================================
 *  Staking Tests
 * ================================================================ */

contract PD_Staking is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0, // 0% commission for simple math
                gcName: "TestGC"
            })
        );
    }

    function test_stake_firstDepositor_1to1() public {
        _stakeViaPD(pd, user1, 100 ether);

        assertEq(pd.balanceOf(user1), 100 ether);
        assertEq(pd.totalSupply(), INITIAL_LOCKUP + 100 ether);
        assertEq(cn.staking(), INITIAL_LOCKUP + 100 ether);
    }

    function test_stake_secondDepositor_sameRate() public {
        _stakeViaPD(pd, user1, 100 ether);
        _stakeViaPD(pd, user2, 50 ether);

        assertEq(pd.balanceOf(user1), 100 ether);
        assertEq(pd.balanceOf(user2), 50 ether);
        assertEq(pd.totalSupply(), INITIAL_LOCKUP + 150 ether);
    }

    function test_stake_afterReward_fewerShares() public {
        _stakeViaPD(pd, user1, 100 ether);

        // Simulate 10 ether reward (sent to PD as block reward)
        _simulateReward(pd, 10 ether);

        // After reward: totalSupply = INITIAL_LOCKUP + 100, totalAssets = INITIAL_LOCKUP + 100 + 10
        // user2 stakes 110 ether → shares = previewDeposit(110 ether)
        uint256 expectedShares = pd.previewDeposit(110 ether);
        _stakeViaPD(pd, user2, 110 ether);

        assertEq(pd.balanceOf(user2), expectedShares);
        // user2 gets fewer shares than deposited due to reward appreciation
        assertTrue(expectedShares < 110 ether, "shares should be less than deposit amount");
    }

    function test_stakeFor_mintsToRecipient() public {
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        pd.stakeFor{value: 100 ether}(user2);

        assertEq(pd.balanceOf(user1), 0);
        assertEq(pd.balanceOf(user2), 100 ether);
    }

    function test_stakeFor_revertsOnZeroRecipient() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        vm.expectRevert(IPublicDelegation.ZeroAddress.selector);
        pd.stakeFor{value: 10 ether}(address(0));
    }

    function test_stake_revertsOnTooSmallAmount() public {
        _stakeViaPD(pd, user1, 100 ether);
        // Simulate large reward so exchange rate is very high
        _simulateReward(pd, 1000 ether);

        // Stake very small amount → shares would be 0
        vm.deal(user2, 1);
        vm.prank(user2);
        vm.expectRevert(IPublicDelegation.StakeAmountTooLow.selector);
        pd.stake{value: 1}();
    }

    function test_receive_worksLikeStake() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        (bool ok, ) = address(pd).call{value: 10 ether}("");
        assertTrue(ok);

        assertEq(pd.balanceOf(user1), 10 ether);
    }

    function test_stake_emitsEvent() public {
        vm.deal(user1, 50 ether);
        vm.prank(user1);

        vm.expectEmit(true, false, false, true, address(pd));
        emit IPublicDelegation.Staked(user1, 50 ether, 50 ether);

        pd.stake{value: 50 ether}();
    }
}

/* ================================================================
 *  Commission Tests
 * ================================================================ */

contract PD_Commission is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 1000, // 10%
                gcName: "TestGC"
            })
        );
    }

    function test_commission_deductedOnStake() public {
        _stakeViaPD(pd, user1, 100 ether);

        // Simulate 10 ether reward
        _simulateReward(pd, 10 ether);

        uint256 commissionBalBefore = commissionTo.balance;

        // Trigger sweep via another stake
        _stakeViaPD(pd, user2, 50 ether);

        // Commission = 10 * 10% = 1 ether
        assertEq(commissionTo.balance - commissionBalBefore, 1 ether);
    }

    function test_commission_sweep_called_on_sweep() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 20 ether);

        uint256 commissionBalBefore = commissionTo.balance;
        pd.sweep();
        // Commission = 20 * 10% = 2 ether
        assertEq(commissionTo.balance - commissionBalBefore, 2 ether);
    }

    function test_updateCommissionTo_sweepsFirst() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 10 ether);

        address newCommissionTo = makeAddr("newCommissionTo");
        uint256 oldCommissionBal = commissionTo.balance;

        vm.prank(owner);
        pd.updateCommissionTo(newCommissionTo);

        // Old commissionTo should have received commission from sweep
        assertEq(commissionTo.balance - oldCommissionBal, 1 ether);
        assertEq(pd.commissionTo(), newCommissionTo);
    }

    function test_updateCommissionRate_sweepsFirst() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 10 ether);

        uint256 commissionBalBefore = commissionTo.balance;

        vm.prank(owner);
        pd.updateCommissionRate(2000); // 10% → 20%

        // Sweep should use old rate (10%) for the 10 ether reward
        assertEq(commissionTo.balance - commissionBalBefore, 1 ether);
        assertEq(pd.commissionRate(), 2000);
    }

    function test_updateCommissionRate_revertsOnTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(IPublicDelegation.CommissionRateTooHigh.selector);
        pd.updateCommissionRate(1e4 + 1);
    }

    function test_updateCommissionTo_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IPublicDelegation.ZeroAddress.selector);
        pd.updateCommissionTo(address(0));
    }

    function test_updateCommissionTo_onlyOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        pd.updateCommissionTo(user1);
    }

    function test_updateCommissionRate_onlyOwner() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user1));
        pd.updateCommissionRate(500);
    }

    function test_updateCommissionTo_emitsEvent() public {
        vm.prank(owner);

        vm.expectEmit(true, true, false, false, address(pd));
        emit IPublicDelegation.UpdateCommissionTo(commissionTo, user1);

        pd.updateCommissionTo(user1);
    }

    function test_updateCommissionRate_emitsEvent() public {
        vm.prank(owner);

        vm.expectEmit(true, true, false, false, address(pd));
        emit IPublicDelegation.UpdateCommissionRate(1000, 500);

        pd.updateCommissionRate(500);
    }
}

/* ================================================================
 *  Withdrawal Tests
 * ================================================================ */

contract PD_Withdrawal is CnStakingBase {
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

    function test_withdraw_byAssets() public {
        vm.prank(user1);
        pd.withdraw(user1, 40 ether);

        // 40 ether withdrawn, shares burned = ceil(40 * 100 / 100) = 40
        assertEq(pd.balanceOf(user1), 60 ether);
        assertEq(cn.unstaking(), 40 ether);
    }

    function test_redeem_byShares() public {
        vm.prank(user1);
        pd.redeem(user1, 30 ether);

        // 30 shares redeemed → assets = floor(30 * 100 / 100) = 30
        assertEq(pd.balanceOf(user1), 70 ether);
        assertEq(cn.unstaking(), 30 ether);
    }

    function test_withdraw_revertsOnZeroRecipient() public {
        vm.prank(user1);
        vm.expectRevert(IPublicDelegation.ZeroAddress.selector);
        pd.withdraw(address(0), 10 ether);
    }

    function test_withdraw_revertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(IPublicDelegation.WithdrawalAmountTooLow.selector);
        pd.withdraw(user1, 0);
    }

    function test_withdraw_emitsRedeemed() public {
        vm.prank(user1);

        vm.expectEmit(true, true, false, true, address(pd));
        emit IPublicDelegation.Redeemed(user1, user1, 10 ether, 10 ether);

        pd.withdraw(user1, 10 ether);
    }

    function test_withdraw_requestTracking() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);

        assertEq(pd.getUserRequestCount(user1), 1);
        uint256 requestId = pd.userRequestIds(user1, 0);
        assertEq(pd.requestIdToOwner(requestId), user1);
    }

    function test_cancelApprovedStakingWithdrawal_remintsShares() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);

        uint256 requestId = pd.userRequestIds(user1, 0);

        // Cancel should re-mint shares
        vm.prank(user1);
        pd.cancelApprovedStakingWithdrawal(requestId);

        assertEq(pd.balanceOf(user1), 100 ether);
        assertEq(cn.unstaking(), 0);
    }

    function test_cancelApprovedStakingWithdrawal_revertsForNonOwner() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);

        uint256 requestId = pd.userRequestIds(user1, 0);

        vm.prank(user2);
        vm.expectRevert(IPublicDelegation.NotRequestOwner.selector);
        pd.cancelApprovedStakingWithdrawal(requestId);
    }

    function test_claim_executesWithdrawal() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);

        uint256 requestId = pd.userRequestIds(user1, 0);

        // Warp past lockup
        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256 balBefore = user1.balance;
        vm.prank(user1);
        pd.claim(requestId);

        assertEq(user1.balance - balBefore, 10 ether);
    }

    function test_claim_autoCancelsWhenExpired() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);

        uint256 requestId = pd.userRequestIds(user1, 0);

        // Warp past 2 * lockup
        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);

        uint256 sharesBefore = pd.balanceOf(user1);
        vm.prank(user1);
        pd.claim(requestId);

        // Shares re-minted (auto-cancel)
        assertTrue(pd.balanceOf(user1) > sharesBefore);
        // Approximately back to 100 ether in shares
        assertEq(pd.balanceOf(user1), 100 ether);
    }

    function test_claim_revertsForNonOwner() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);

        uint256 requestId = pd.userRequestIds(user1, 0);

        vm.warp(block.timestamp + STAKE_LOCKUP);

        vm.prank(user2);
        vm.expectRevert(IPublicDelegation.NotRequestOwner.selector);
        pd.claim(requestId);
    }

    function test_withdraw_toDifferentRecipient() public {
        vm.prank(user1);
        pd.withdraw(user2, 10 ether);

        uint256 requestId = pd.userRequestIds(user1, 0);

        vm.warp(block.timestamp + STAKE_LOCKUP);

        vm.prank(user1);
        pd.claim(requestId);

        // user2 should have received the KAIA
        assertEq(user2.balance, 10 ether);
    }
}

/* ================================================================
 *  Redelegation Tests
 * ================================================================ */

contract PD_Redelegation is CnStakingBase {
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

    function test_redelegateByAssets() public {
        vm.prank(user1);
        sourcePd.redelegateByAssets(address(targetCn), 40 ether);

        // Source should have INITIAL_LOCKUP + 60 ether staked
        assertEq(sourceCn.staking(), INITIAL_LOCKUP + 60 ether);
        // Target should have INITIAL_LOCKUP + 40 ether staked
        assertEq(targetCn.staking(), INITIAL_LOCKUP + 40 ether);

        // user1 should have 60 shares in source PD
        assertEq(sourcePd.balanceOf(user1), 60 ether);
        // user1 should have 40 shares in target PD
        assertEq(targetPd.balanceOf(user1), 40 ether);
    }

    function test_redelegateByShares() public {
        vm.prank(user1);
        sourcePd.redelegateByShares(address(targetCn), 30 ether);

        assertEq(sourceCn.staking(), INITIAL_LOCKUP + 70 ether);
        assertEq(targetCn.staking(), INITIAL_LOCKUP + 30 ether);
        assertEq(sourcePd.balanceOf(user1), 70 ether);
        assertEq(targetPd.balanceOf(user1), 30 ether);
    }

    function test_redelegateByAssets_revertsOnZero() public {
        vm.prank(user1);
        vm.expectRevert(IPublicDelegation.RedelegateAmountTooLow.selector);
        sourcePd.redelegateByAssets(address(targetCn), 0);
    }

    function test_redelegateByShares_revertsOnZero() public {
        vm.prank(user1);
        vm.expectRevert(IPublicDelegation.RedelegateAmountTooLow.selector);
        sourcePd.redelegateByShares(address(targetCn), 0);
    }

    function test_redelegate_emitsEvent() public {
        vm.prank(user1);

        vm.expectEmit(true, true, false, true, address(sourcePd));
        emit IPublicDelegation.Redelegated(user1, address(targetCn), 50 ether);

        sourcePd.redelegateByAssets(address(targetCn), 50 ether);
    }
}

/* ================================================================
 *  ERC20 Transferability Tests
 * ================================================================ */

contract PD_ERC20 is CnStakingBase {
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

    function test_transfer_works() public {
        vm.prank(user1);
        pd.transfer(user2, 40 ether);

        assertEq(pd.balanceOf(user1), 60 ether);
        assertEq(pd.balanceOf(user2), 40 ether);
    }

    function test_transferFrom_works() public {
        vm.prank(user1);
        pd.approve(user2, 30 ether);

        vm.prank(user2);
        pd.transferFrom(user1, user2, 30 ether);

        assertEq(pd.balanceOf(user1), 70 ether);
        assertEq(pd.balanceOf(user2), 30 ether);
    }

    function test_transfer_recipientCanWithdraw() public {
        vm.prank(user1);
        pd.transfer(user2, 40 ether);

        // user2 can withdraw with their transferred shares
        vm.prank(user2);
        pd.withdraw(user2, 40 ether);

        assertEq(pd.balanceOf(user2), 0);
        assertEq(cn.unstaking(), 40 ether);
    }
}

/* ================================================================
 *  Getter Tests
 * ================================================================ */

contract PD_Getters is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 1000, // 10%
                gcName: "TestGC"
            })
        );

        _stakeViaPD(pd, user1, 100 ether);
    }

    function test_totalAssets() public view {
        assertEq(pd.totalAssets(), INITIAL_LOCKUP + 100 ether);
    }

    function test_totalAssets_withReward() public {
        _simulateReward(pd, 10 ether);
        // totalAssets = staking + pureReward = 101 + (10 - 10*10%) = 101 + 9 = 110
        assertEq(pd.totalAssets(), INITIAL_LOCKUP + 109 ether);
    }

    function test_convertToShares() public view {
        // 1:1 ratio (100 supply, 100 assets)
        assertEq(pd.convertToShares(50 ether), 50 ether);
    }

    function test_convertToAssets() public view {
        assertEq(pd.convertToAssets(50 ether), 50 ether);
    }

    function test_previewDeposit() public view {
        assertEq(pd.previewDeposit(50 ether), 50 ether);
    }

    function test_previewWithdraw() public view {
        // Ceil rounding
        assertEq(pd.previewWithdraw(50 ether), 50 ether);
    }

    function test_previewRedeem() public view {
        assertEq(pd.previewRedeem(50 ether), 50 ether);
    }

    function test_maxRedeem() public view {
        assertEq(pd.maxRedeem(user1), 100 ether);
        assertEq(pd.maxRedeem(user2), 0);
    }

    function test_maxWithdraw() public view {
        assertEq(pd.maxWithdraw(user1), 100 ether);
        assertEq(pd.maxWithdraw(user2), 0);
    }

    function test_reward() public {
        assertEq(pd.reward(), 0);

        _simulateReward(pd, 10 ether);
        // reward = pureReward = 10 - 10*10% = 9
        assertEq(pd.reward(), 9 ether);
    }

    function test_getCurrentWithdrawalRequestState() public {
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);
        uint256 id = pd.userRequestIds(user1, 0);

        // Initially: Requested
        assertEq(
            uint256(pd.getCurrentWithdrawalRequestState(id)),
            uint256(IPublicDelegation.WithdrawalRequestState.Requested)
        );

        // After lockup: Withdrawable
        vm.warp(block.timestamp + STAKE_LOCKUP);
        assertEq(
            uint256(pd.getCurrentWithdrawalRequestState(id)),
            uint256(IPublicDelegation.WithdrawalRequestState.Withdrawable)
        );

        // After 2*lockup: PendingCancel (+1 to avoid exact boundary: via_ir CSE caches block.timestamp
        // before external calls, causing block.timestamp == _withdrawableUntil to evaluate as Withdrawable)
        vm.warp(block.timestamp + STAKE_LOCKUP + 1);
        assertEq(
            uint256(pd.getCurrentWithdrawalRequestState(id)),
            uint256(IPublicDelegation.WithdrawalRequestState.PendingCancel)
        );
    }

    function test_getCurrentWithdrawalRequestState_undefined() public view {
        assertEq(
            uint256(pd.getCurrentWithdrawalRequestState(999)),
            uint256(IPublicDelegation.WithdrawalRequestState.Undefined)
        );
    }

    function test_getUserRequestIds() public {
        vm.startPrank(user1);
        pd.withdraw(user1, 10 ether);
        pd.withdraw(user1, 20 ether);
        vm.stopPrank();

        uint256[] memory ids = pd.getUserRequestIds(user1);
        assertEq(ids.length, 2);
    }

    function test_getUserRequestIdsWithState() public {
        vm.startPrank(user1);
        pd.withdraw(user1, 10 ether);
        pd.withdraw(user1, 20 ether);
        vm.stopPrank();

        uint256[] memory requested = pd.getUserRequestIdsWithState(
            user1,
            IPublicDelegation.WithdrawalRequestState.Requested
        );
        assertEq(requested.length, 2);

        // Warp and check Withdrawable
        vm.warp(block.timestamp + STAKE_LOCKUP);
        uint256[] memory withdrawable = pd.getUserRequestIdsWithState(
            user1,
            IPublicDelegation.WithdrawalRequestState.Withdrawable
        );
        assertEq(withdrawable.length, 2);
    }
}

/* ================================================================
 *  Sweep Tests
 * ================================================================ */

contract PD_Sweep is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 1000, // 10%
                gcName: "TestGC"
            })
        );

        _stakeViaPD(pd, user1, 100 ether);
    }

    function test_sweep_stakesReward() public {
        _simulateReward(pd, 20 ether);

        uint256 stakingBefore = cn.staking();
        pd.sweep();

        // Reward 20, commission 2, net staked = 18
        assertEq(cn.staking() - stakingBefore, 18 ether);
    }

    function test_sweep_noReward_noOp() public {
        uint256 stakingBefore = cn.staking();
        pd.sweep();
        assertEq(cn.staking(), stakingBefore);
    }

    function test_sweep_zeroCommission() public {
        // Redeploy with 0% commission
        address targetOwner = makeAddr("targetOwner");
        (CnStakingV4 cn2, PublicDelegation pd2) = _deployCnStakingWithPD(
            targetOwner,
            IPublicDelegation.PDConstructorArgs({
                owner: targetOwner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TestGC2"
            })
        );

        _stakeViaPD(pd2, user1, 100 ether);
        _simulateReward(pd2, 10 ether);

        uint256 stakingBefore = cn2.staking();
        pd2.sweep();

        // All reward staked, no commission
        assertEq(cn2.staking() - stakingBefore, 10 ether);
        assertEq(commissionTo.balance, 0);
    }
}

/* ================================================================
 *  Commission Recipient Failure Tests (Finding #1 fix)
 * ================================================================ */

/// @dev Contract that reverts on receive — simulates a bricked commissionTo
contract RevertingReceiver {
    receive() external payable {
        revert("I refuse KAIA");
    }
}

contract PD_CommissionFailure is CnStakingBase {
    CnStakingV4 cn;
    PublicDelegation pd;
    RevertingReceiver revertingRecipient;

    function setUp() public override {
        super.setUp();
        revertingRecipient = new RevertingReceiver();

        // Deploy PD with the reverting contract as commissionTo
        (cn, pd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: address(revertingRecipient),
                commissionRate: 1000, // 10%
                gcName: "TestGC"
            })
        );
    }

    function test_stake_succeedsWhenCommissionToReverts() public {
        // Stake should succeed even when commissionTo reverts
        _stakeViaPD(pd, user1, 100 ether);

        // Simulate reward
        _simulateReward(pd, 10 ether);

        // Another stake triggers sweep — commission transfer fails but tx succeeds
        uint256 stakingBefore = cn.staking();
        _stakeViaPD(pd, user2, 50 ether);

        // Commission (1 ether) stays in PD balance, rest was staked
        // Staked: reward(10) + deposit(50) - commission(1) = 59 ether
        assertEq(cn.staking() - stakingBefore, 59 ether);
        assertEq(address(revertingRecipient).balance, 0); // commission not received
    }

    function test_sweep_succeedsWhenCommissionToReverts() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 20 ether);

        // Sweep should succeed, commission stays in PD balance
        pd.sweep();

        assertEq(address(revertingRecipient).balance, 0);
    }

    function test_withdraw_succeedsWhenCommissionToReverts() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 10 ether);

        // Withdraw should succeed
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);
    }

    function test_updateCommissionTo_succeedsWhenCommissionToReverts() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 10 ether);

        // Owner can update commissionTo even though current one reverts
        address newCommissionTo = makeAddr("newCommissionTo");
        vm.prank(owner);
        pd.updateCommissionTo(newCommissionTo);

        assertEq(pd.commissionTo(), newCommissionTo);

        // Now commission should go to the new address
        // Note: 1 ether failed commission from the sweep inside updateCommissionTo
        // is still in PD balance, so next sweep sees it as additional reward
        _simulateReward(pd, 10 ether);
        uint256 newBalBefore = newCommissionTo.balance;
        pd.sweep();
        // reward = 10 ether (new) + 1 ether (failed commission) = 11 ether
        // commission = 11 * 10% = 1.1 ether
        assertEq(newCommissionTo.balance - newBalBefore, 1.1 ether);
    }

    function test_updateCommissionRate_succeedsWhenCommissionToReverts() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 10 ether);

        // Owner can set rate to 0 even though commissionTo reverts
        vm.prank(owner);
        pd.updateCommissionRate(0);

        assertEq(pd.commissionRate(), 0);
    }

    function test_sendCommission_emitsEventWithSuccess() public {
        // Deploy with a working commissionTo — use different owner to avoid CREATE2 collision
        address owner2 = makeAddr("owner2");
        address workingCommissionTo = makeAddr("workingCommissionTo");
        (, PublicDelegation pd2) = _deployCnStakingWithPD(
            owner2,
            IPublicDelegation.PDConstructorArgs({
                owner: owner2,
                commissionTo: workingCommissionTo,
                commissionRate: 1000,
                gcName: "TestGC2"
            })
        );

        _stakeViaPD(pd2, user1, 100 ether);
        _simulateReward(pd2, 10 ether);

        // Expect success=true when commission transfer works
        vm.expectEmit(true, false, false, true);
        emit IPublicDelegation.SendCommission(workingCommissionTo, 1 ether, true);
        pd2.sweep();
    }

    function test_sendCommission_emitsEventWithFailure() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 10 ether);

        // Expect success=false when commission transfer fails
        vm.expectEmit(true, false, false, true);
        emit IPublicDelegation.SendCommission(address(revertingRecipient), 1 ether, false);
        pd.sweep();
    }

    function test_failedCommission_isSweepedNextTime() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 10 ether);

        // First sweep: commission (1 ether) fails, stays in PD balance
        pd.sweep();

        // Now fix commissionTo — the sweep inside updateCommissionTo sees 1 ether
        // as reward, tries to send 0.1 ether commission → still to reverting recipient → fails
        // After update: PD balance = 0.1 ether (commission on commission failed too)
        address newCommissionTo = makeAddr("newCommissionTo");
        vm.prank(owner);
        pd.updateCommissionTo(newCommissionTo);

        // The remaining 0.1 ether is treated as reward
        // Commission = 0.1 * 10% = 0.01 ether
        uint256 newBalBefore = newCommissionTo.balance;
        pd.sweep();
        assertEq(newCommissionTo.balance - newBalBefore, 0.01 ether);
    }

    function test_redeem_succeedsWhenCommissionToReverts() public {
        _stakeViaPD(pd, user1, 100 ether);
        _simulateReward(pd, 10 ether);

        uint256 shares = pd.balanceOf(user1);
        vm.prank(user1);
        pd.redeem(user1, shares / 2);
    }

    function test_cancelWithdrawal_succeedsWhenCommissionToReverts() public {
        _stakeViaPD(pd, user1, 100 ether);

        // Create withdrawal
        vm.prank(user1);
        pd.withdraw(user1, 10 ether);

        _simulateReward(pd, 10 ether);

        // Cancel should succeed
        uint256 requestId = pd.userRequestIds(user1, 0);
        vm.prank(user1);
        pd.cancelApprovedStakingWithdrawal(requestId);
    }
}
