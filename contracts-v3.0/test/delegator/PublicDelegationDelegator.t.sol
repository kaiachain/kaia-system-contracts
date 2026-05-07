// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CnStakingBase} from "../cnstaking/CnStakingBase.t.sol";
import {PublicDelegationDelegator} from "../../src/Delegator/PublicDelegationDelegator.sol";
import {IPublicDelegationDelegator} from "../../src/Delegator/interfaces/IPublicDelegationDelegator.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {PublicDelegation} from "../../src/PublicDelegation/PublicDelegation.sol";
import {IPublicDelegation} from "../../src/PublicDelegation/interfaces/IPublicDelegation.sol";
import {ICnStaking} from "../../src/CnStaking/CnStakingV4/interfaces/ICnStaking.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract PublicDelegationDelegatorTest is CnStakingBase {
    PublicDelegationDelegator internal pdd; // PD delegator contract
    CnStakingV4 internal cn;
    PublicDelegation internal pd;
    address internal delegator;
    address internal delegatee;

    function setUp() public override {
        super.setUp();
        delegator = makeAddr("delegator");
        delegatee = makeAddr("delegatee");

        // Deploy CN with PD (10% commission)
        (cn, pd) = _deployCnStakingWithPDDefaults();

        // Deploy PublicDelegationDelegator
        pdd = new PublicDelegationDelegator(delegator, delegatee, address(pd));
    }

    /* ========================================================
                          CONSTRUCTOR
    ======================================================== */

    function testConstructor_rolesAssigned() public view {
        assertTrue(pdd.hasRole(pdd.DELEGATOR_ROLE(), delegator));
        assertTrue(pdd.hasRole(pdd.DELEGATEE_ROLE(), delegatee));
        assertEq(address(pdd.PD()), address(pd));
        assertEq(pdd.delegation(), 0);
    }

    function testConstructor_nullDelegator_reverts() public {
        vm.expectRevert(IPublicDelegationDelegator.ZeroAddress.selector);
        new PublicDelegationDelegator(address(0), delegatee, address(pd));
    }

    function testConstructor_nullDelegatee_reverts() public {
        vm.expectRevert(IPublicDelegationDelegator.ZeroAddress.selector);
        new PublicDelegationDelegator(delegator, address(0), address(pd));
    }

    function testConstructor_nullPD_reverts() public {
        vm.expectRevert(IPublicDelegationDelegator.ZeroAddress.selector);
        new PublicDelegationDelegator(delegator, delegatee, address(0));
    }

    /* ========================================================
                        ACCESS CONTROL
    ======================================================== */

    function testDelegate_notDelegator_reverts() public {
        vm.deal(delegatee, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegatee,
                pdd.DELEGATOR_ROLE()
            )
        );
        vm.prank(delegatee);
        pdd.delegate{value: 1 ether}();
    }

    function testWithdrawDelegation_notDelegator_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegatee,
                pdd.DELEGATOR_ROLE()
            )
        );
        vm.prank(delegatee);
        pdd.withdrawDelegation(delegatee, 1 ether);
    }

    function testClaimDelegation_notDelegator_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegatee,
                pdd.DELEGATOR_ROLE()
            )
        );
        vm.prank(delegatee);
        pdd.claimDelegation(0);
    }

    function testWithdrawReward_notDelegatee_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegator,
                pdd.DELEGATEE_ROLE()
            )
        );
        vm.prank(delegator);
        pdd.withdrawReward(delegator, 1 ether);
    }

    function testClaimReward_notDelegatee_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegator,
                pdd.DELEGATEE_ROLE()
            )
        );
        vm.prank(delegator);
        pdd.claimReward(0);
    }

    /* ========================================================
                        ROLE MANAGEMENT
    ======================================================== */

    function testTransferDelegator() public {
        address newDelegator = makeAddr("newDelegator");
        vm.prank(delegator);
        pdd.transferDelegator(newDelegator);

        assertTrue(pdd.hasRole(pdd.DELEGATOR_ROLE(), newDelegator));
        assertFalse(pdd.hasRole(pdd.DELEGATOR_ROLE(), delegator));
    }

    function testTransferDelegatee() public {
        address newDelegatee = makeAddr("newDelegatee");
        vm.prank(delegatee);
        pdd.transferDelegatee(newDelegatee);

        assertTrue(pdd.hasRole(pdd.DELEGATEE_ROLE(), newDelegatee));
        assertFalse(pdd.hasRole(pdd.DELEGATEE_ROLE(), delegatee));
    }

    function testTransferDelegator_nullAddress_reverts() public {
        vm.prank(delegator);
        vm.expectRevert(IPublicDelegationDelegator.ZeroAddress.selector);
        pdd.transferDelegator(address(0));
    }

    function testTransferDelegatee_nullAddress_reverts() public {
        vm.prank(delegatee);
        vm.expectRevert(IPublicDelegationDelegator.ZeroAddress.selector);
        pdd.transferDelegatee(address(0));
    }

    function testTransferDelegator_toSelf_reverts() public {
        vm.prank(delegator);
        vm.expectRevert(IPublicDelegationDelegator.SameAddress.selector);
        pdd.transferDelegator(delegator);
    }

    function testTransferDelegatee_toSelf_reverts() public {
        vm.prank(delegatee);
        vm.expectRevert(IPublicDelegationDelegator.SameAddress.selector);
        pdd.transferDelegatee(delegatee);
    }

    /* ========================================================
                        DELEGATION
    ======================================================== */

    function testDelegate_basic() public {
        _pddDelegatorStake(100 ether);

        assertEq(pdd.delegation(), 100 ether);
        // PDD should have pdKAIA shares
        assertTrue(pd.balanceOf(address(pdd)) > 0);
    }

    function testDelegate_zeroValue_reverts() public {
        vm.prank(delegator);
        vm.expectRevert(IPublicDelegationDelegator.ZeroValue.selector);
        pdd.delegate{value: 0}();
    }

    function testDelegate_multipleAccumulates() public {
        _pddDelegatorStake(100 ether);
        _pddDelegatorStake(200 ether);

        assertEq(pdd.delegation(), 300 ether);
    }

    /* ========================================================
              WITHDRAW & CLAIM DELEGATION
    ======================================================== */

    function testWithdrawDelegation_basic() public {
        _pddDelegatorStake(100 ether);

        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 40 ether);

        assertEq(pdd.delegation(), 60 ether);
        assertEq(pdd.delegationWithdrawalIds().length, 1);
    }

    function testWithdrawDelegation_exceedsDelegation_reverts() public {
        _pddDelegatorStake(100 ether);

        vm.prank(delegator);
        vm.expectRevert(IPublicDelegationDelegator.InsufficientDelegation.selector);
        pdd.withdrawDelegation(delegator, 101 ether);
    }

    function testClaimDelegation_executeAfterLockup() public {
        _pddDelegatorStake(100 ether);

        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 40 ether);
        uint256 id = pdd.delegationWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256 balBefore = delegator.balance;
        vm.prank(delegator);
        pdd.claimDelegation(id);

        assertEq(delegator.balance, balBefore + 40 ether);
        assertEq(pdd.delegation(), 60 ether); // unchanged
    }

    function testClaimDelegation_autoCancelAfterDoubleLockup() public {
        _pddDelegatorStake(100 ether);

        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 40 ether);
        uint256 id = pdd.delegationWithdrawalIds()[0];

        // Auto-cancel
        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);

        uint256 balBefore = delegator.balance;
        vm.prank(delegator);
        pdd.claimDelegation(id);

        // No transfer
        assertEq(delegator.balance, balBefore);
        // Delegation restored
        assertEq(pdd.delegation(), 100 ether);
    }

    function testClaimDelegation_invalidId_reverts() public {
        vm.prank(delegator);
        vm.expectRevert(IPublicDelegationDelegator.InvalidWithdrawalId.selector);
        pdd.claimDelegation(999);
    }

    function testClaimDelegation_beforeLockup_reverts() public {
        _pddDelegatorStake(100 ether);

        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 40 ether);
        uint256 id = pdd.delegationWithdrawalIds()[0];

        // Don't warp — still in lockup
        vm.prank(delegator);
        vm.expectRevert(ICnStaking.NotWithdrawableYet.selector);
        pdd.claimDelegation(id);
    }

    function testClaimDelegation_doubleClaim_reverts() public {
        _pddDelegatorStake(100 ether);

        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 40 ether);
        uint256 id = pdd.delegationWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(delegator);
        pdd.claimDelegation(id);

        // Second claim: ID already removed from set
        vm.prank(delegator);
        vm.expectRevert(IPublicDelegationDelegator.InvalidWithdrawalId.selector);
        pdd.claimDelegation(id);
    }

    /* ========================================================
              REWARD WITHDRAWAL
    ======================================================== */

    function testWithdrawableReward_noReward() public {
        _pddDelegatorStake(100 ether);

        // No rewards accumulated → withdrawableReward ≈ 0
        assertEq(pdd.withdrawableReward(), 0);
    }

    function testWithdrawableReward_afterReward() public {
        _pddDelegatorStake(100 ether);

        // Simulate 10 ether reward (10% commission → 9 ether pure reward, minus dead share dilution)
        _simulateReward(pd, 10 ether);

        uint256 reward = pdd.withdrawableReward();
        assertEq(reward, _delegateeReward(10 ether));
    }

    function testWithdrawReward_basic() public {
        _pddDelegatorStake(100 ether);
        _simulateReward(pd, 10 ether);

        uint256 reward = pdd.withdrawableReward();

        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, reward);

        assertEq(pdd.rewardWithdrawalIds().length, 1);
        // After withdrawing all reward, withdrawable should be 0
        assertEq(pdd.withdrawableReward(), 0);
    }

    function testWithdrawReward_exceedsAvailable_reverts() public {
        _pddDelegatorStake(100 ether);
        _simulateReward(pd, 10 ether);

        uint256 reward = pdd.withdrawableReward();

        vm.prank(delegatee);
        vm.expectRevert(IPublicDelegationDelegator.InsufficientReward.selector);
        pdd.withdrawReward(delegatee, reward + 1 ether);
    }

    function testWithdrawReward_noReward_reverts() public {
        _pddDelegatorStake(100 ether);

        vm.prank(delegatee);
        vm.expectRevert(IPublicDelegationDelegator.InsufficientReward.selector);
        pdd.withdrawReward(delegatee, 1 ether);
    }

    function testClaimReward_executeAfterLockup() public {
        _pddDelegatorStake(100 ether);
        _simulateReward(pd, 10 ether);

        uint256 reward = pdd.withdrawableReward();
        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, reward);
        uint256 id = pdd.rewardWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256 balBefore = delegatee.balance;
        vm.prank(delegatee);
        pdd.claimReward(id);

        assertEq(delegatee.balance, balBefore + reward);
    }

    function testClaimReward_autoCancelAfterDoubleLockup() public {
        _pddDelegatorStake(100 ether);
        _simulateReward(pd, 10 ether);

        uint256 reward = pdd.withdrawableReward();
        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, reward);
        uint256 id = pdd.rewardWithdrawalIds()[0];

        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);

        uint256 balBefore = delegatee.balance;
        vm.prank(delegatee);
        pdd.claimReward(id);

        // No transfer
        assertEq(delegatee.balance, balBefore);
    }

    function testClaimReward_invalidId_reverts() public {
        vm.prank(delegatee);
        vm.expectRevert(IPublicDelegationDelegator.InvalidWithdrawalId.selector);
        pdd.claimReward(999);
    }

    /* ========================================================
              CROSS-ROLE ID ISOLATION
    ======================================================== */

    function testCrossRoleIdIsolation() public {
        _pddDelegatorStake(100 ether);
        _simulateReward(pd, 10 ether);

        // Create delegation withdrawal
        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 20 ether);
        uint256 delId = pdd.delegationWithdrawalIds()[0];

        // Create reward withdrawal
        uint256 reward = pdd.withdrawableReward();
        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, reward);
        uint256 rewId = pdd.rewardWithdrawalIds()[0];

        // Can't claim with wrong role
        vm.prank(delegator);
        vm.expectRevert(IPublicDelegationDelegator.InvalidWithdrawalId.selector);
        pdd.claimDelegation(rewId);

        vm.prank(delegatee);
        vm.expectRevert(IPublicDelegationDelegator.InvalidWithdrawalId.selector);
        pdd.claimReward(delId);
    }

    /* ========================================================
              DELEGATION + REWARD INTERLEAVING
    ======================================================== */

    function testInterleaved_delegateAndReward() public {
        // Phase 1: Stake and accumulate reward
        _pddDelegatorStake(100 ether);
        _simulateReward(pd, 20 ether);

        uint256 reward1 = pdd.withdrawableReward();
        assertEq(reward1, _delegateeReward(20 ether));

        // Phase 2: Withdraw some delegation
        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 30 ether);

        // Reward should still be available (actually it should increase slightly
        // because PD.withdraw burns shares but delegation tracking decreases independently)
        // After withdrawDelegation: delegation=70, shares burned for 30 ether worth
        // The remaining shares still cover delegation(70) + accumulated reward portion

        // Phase 3: Withdraw reward
        uint256 reward2 = pdd.withdrawableReward();
        assertEq(reward2, reward1);

        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, reward2);

        // Phase 4: Claim both
        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256 delId = pdd.delegationWithdrawalIds()[0];
        uint256 rewId = pdd.rewardWithdrawalIds()[0];

        vm.prank(delegator);
        pdd.claimDelegation(delId);

        vm.prank(delegatee);
        pdd.claimReward(rewId);
    }

    function testRewardAccumulatesBetweenOperations() public {
        _pddDelegatorStake(100 ether);

        // No reward yet
        assertEq(pdd.withdrawableReward(), 0);

        // First reward: 10 ether → 9 ether pure (10% commission), minus dead share dilution
        _simulateReward(pd, 10 ether);
        uint256 reward1 = pdd.withdrawableReward();
        assertEq(reward1, _delegateeReward(10 ether));

        // More reward: total pd balance now 20 ether
        _simulateReward(pd, 10 ether);
        uint256 reward2 = pdd.withdrawableReward();
        assertEq(reward2, _delegateeReward(20 ether));
        assertGt(reward2, reward1);
    }

    /* ========================================================
              FULL DRAIN DELEGATION + ALL REWARD
    ======================================================== */

    function testFullDrain_delegationThenReward() public {
        _pddDelegatorStake(100 ether);
        _simulateReward(pd, 20 ether);

        // Drain all delegation
        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 100 ether);
        uint256 delId = pdd.delegationWithdrawalIds()[0];

        assertEq(pdd.delegation(), 0);

        // After draining delegation, all remaining maxWithdraw is reward.
        // Can't use _delegateeReward here because sweep+burn changed share ratio.
        // Compute expected reward independently from PD/CN state.
        uint256 rewardAfterDrain = pdd.withdrawableReward();
        assertEq(rewardAfterDrain, _expectedReward());

        // Drain reward
        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, rewardAfterDrain);

        // Claim both
        vm.warp(block.timestamp + STAKE_LOCKUP);

        vm.prank(delegator);
        pdd.claimDelegation(delId);

        uint256 rewId = pdd.rewardWithdrawalIds()[0];
        vm.prank(delegatee);
        pdd.claimReward(rewId);

        // Everything withdrawn — maxWithdraw should be 0
        assertEq(pd.maxWithdraw(address(pdd)), 0);
    }

    /* ========================================================
              MULTIPLE PENDING WITHDRAWALS
    ======================================================== */

    function testMultiplePendingWithdrawals() public {
        _pddDelegatorStake(200 ether);
        _simulateReward(pd, 30 ether);

        // Multiple delegation withdrawals
        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 50 ether);
        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 30 ether);

        assertEq(pdd.delegationWithdrawalIds().length, 2);
        assertEq(pdd.delegation(), 120 ether);

        // Multiple reward withdrawals
        uint256 r1 = pdd.withdrawableReward() / 2;
        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, r1);

        uint256 r2 = pdd.withdrawableReward();
        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, r2);

        assertEq(pdd.rewardWithdrawalIds().length, 2);

        // Claim all
        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256[] memory delIds = pdd.delegationWithdrawalIds();
        for (uint256 i = 0; i < delIds.length; i++) {
            vm.prank(delegator);
            pdd.claimDelegation(delIds[i]);
        }

        uint256[] memory rewIds = pdd.rewardWithdrawalIds();
        for (uint256 i = 0; i < rewIds.length; i++) {
            vm.prank(delegatee);
            pdd.claimReward(rewIds[i]);
        }

        assertEq(pdd.delegation(), 120 ether);
    }

    /* ========================================================
              MIXED: AUTO-CANCEL DELEGATION + EXECUTE REWARD
    ======================================================== */

    function testMixed_autoCancelDelegation_executeReward() public {
        _pddDelegatorStake(100 ether);
        _simulateReward(pd, 20 ether);

        uint256 reward = pdd.withdrawableReward();

        // Start delegation withdrawal
        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 50 ether);
        uint256 delId = pdd.delegationWithdrawalIds()[0];

        // Start reward withdrawal
        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, reward);
        uint256 rewId = pdd.rewardWithdrawalIds()[0];

        // Claim reward (within window)
        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(delegatee);
        pdd.claimReward(rewId);

        // Auto-cancel delegation (past double lockup)
        vm.warp(block.timestamp + STAKE_LOCKUP); // now at 2*STAKE_LOCKUP from start
        vm.prank(delegator);
        pdd.claimDelegation(delId);

        // Delegation should be restored
        assertEq(pdd.delegation(), 100 ether);
    }

    /* ========================================================
              REWARD AFTER PARTIAL DELEGATION WITHDRAWAL
    ======================================================== */

    function testRewardCalculation_afterPartialWithdrawal() public {
        _pddDelegatorStake(100 ether);
        _simulateReward(pd, 20 ether);

        uint256 rewardBefore = pdd.withdrawableReward();

        // Withdraw some delegation
        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 30 ether);

        // After withdrawal, delegation=70 but shares were burned
        // withdrawableReward = maxWithdraw(pdd) - delegation
        uint256 rewardAfter = pdd.withdrawableReward();

        // Reward should still be positive
        assertEq(rewardAfter, rewardBefore);
    }

    /* ========================================================
              MULTI-CYCLE
    ======================================================== */

    function testMultiCycle_stakeRewardWithdrawRestake() public {
        // Cycle 1: initial stake
        _pddDelegatorStake(100 ether);

        // Cycle 2: reward + partial withdrawal
        _simulateReward(pd, 10 ether);
        vm.prank(delegator);
        pdd.withdrawDelegation(delegator, 30 ether);

        vm.warp(block.timestamp + STAKE_LOCKUP);
        uint256 delId = pdd.delegationWithdrawalIds()[0];
        vm.prank(delegator);
        pdd.claimDelegation(delId);

        assertEq(pdd.delegation(), 70 ether);

        // Cycle 3: more reward + reward withdrawal
        // Sweep+burn occurred in cycle 2, so _delegateeReward(total) won't match.
        // Verify against independent state computation instead.
        _simulateReward(pd, 15 ether);
        uint256 reward = pdd.withdrawableReward();
        assertEq(reward, _expectedReward());

        vm.prank(delegatee);
        pdd.withdrawReward(delegatee, reward);

        vm.warp(block.timestamp + STAKE_LOCKUP);
        uint256 rewId = pdd.rewardWithdrawalIds()[0];
        vm.prank(delegatee);
        pdd.claimReward(rewId);

        // Cycle 4: restake more
        _pddDelegatorStake(50 ether);
        assertEq(pdd.delegation(), 120 ether);
    }

    /* ========================================================
              OTHER STAKERS IN PD
    ======================================================== */

    function testOtherStakersInPD_rewardDilution() public {
        _pddDelegatorStake(100 ether);

        // Another staker stakes directly in PD (same amount, same exchange rate)
        _stakeViaPD(pd, user1, 100 ether);

        // Simulate reward (split between pdd, user1, and dead shares)
        _simulateReward(pd, 20 ether);

        // PDD gets proportional share: pureReward * pddShares / totalSupply
        // pddShares=100e18, user1Shares=100e18, deadShares=1e9
        uint256 pddReward = pdd.withdrawableReward();
        assertEq(pddReward, _delegateeReward(20 ether));

        // Also verify user1 gets roughly the same as PDD (both staked 100 ether)
        uint256 user1MaxWithdraw = pd.maxWithdraw(user1);
        assertEq(user1MaxWithdraw - 100 ether, pddReward);
    }

    /* ========================================================
                    HELPERS
    ======================================================== */

    /// @dev Compute expected reward for simple cases (no sweep/burn between reward and check).
    /// Formula: pureReward * pddShares / totalSupply (exact when exchange rate hasn't changed).
    function _delegateeReward(uint256 _totalReward) internal view returns (uint256) {
        uint256 rewardAfterCommission = _totalReward - (_totalReward * pd.commissionRate()) / 10000;
        return (rewardAfterCommission * pd.balanceOf(address(pdd))) / pd.totalSupply();
    }

    /// @dev Compute expected reward from PD/CN state (works after sweep+burn).
    /// Independently recomputes maxWithdraw from low-level components, then subtracts delegation.
    function _expectedReward() internal view returns (uint256) {
        uint256 shares = pd.balanceOf(address(pdd));
        uint256 supply = pd.totalSupply();
        uint256 assets = pd.totalAssets();
        uint256 expectedMaxWithdraw = (shares * assets) / supply;
        return expectedMaxWithdraw - pdd.delegation();
    }

    function _pddDelegatorStake(uint256 _amount) internal {
        vm.deal(delegator, _amount);
        vm.prank(delegator);
        pdd.delegate{value: _amount}();
    }
}
