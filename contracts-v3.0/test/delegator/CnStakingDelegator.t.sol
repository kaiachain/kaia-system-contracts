// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CnStakingBase} from "../cnstaking/CnStakingBase.t.sol";
import {CnStakingDelegator} from "../../src/Delegator/CnStakingDelegator.sol";
import {ICnStakingDelegator} from "../../src/Delegator/interfaces/ICnStakingDelegator.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {ICnStaking} from "../../src/CnStaking/CnStakingV4/interfaces/ICnStaking.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract CnStakingDelegatorTest is CnStakingBase {
    CnStakingDelegator internal d; // delegator contract
    CnStakingV4 internal cn;
    address internal delegator;
    address internal delegatee;

    function setUp() public override {
        super.setUp();
        delegator = makeAddr("delegator");
        delegatee = makeAddr("delegatee");

        // Deploy CN without PD; test contract is temp owner
        cn = _deployCnStaking(address(this));

        // Deploy CnStakingDelegator
        d = new CnStakingDelegator(delegator, delegatee, address(cn));

        // Transfer CN ownership to the delegator contract
        cn.transferOwnership(address(d));
    }

    /* ========================================================
                          CONSTRUCTOR
    ======================================================== */

    function testConstructor_rolesAssigned() public view {
        assertTrue(d.hasRole(d.DELEGATOR_ROLE(), delegator));
        assertTrue(d.hasRole(d.DELEGATEE_ROLE(), delegatee));
        assertEq(address(d.CN()), address(cn));
        assertEq(d.delegation(), 0);
    }

    function testConstructor_nullDelegator_reverts() public {
        vm.expectRevert(ICnStakingDelegator.ZeroAddress.selector);
        new CnStakingDelegator(address(0), delegatee, address(cn));
    }

    function testConstructor_nullDelegatee_reverts() public {
        vm.expectRevert(ICnStakingDelegator.ZeroAddress.selector);
        new CnStakingDelegator(delegator, address(0), address(cn));
    }

    function testConstructor_nullCn_reverts() public {
        vm.expectRevert(ICnStakingDelegator.ZeroAddress.selector);
        new CnStakingDelegator(delegator, delegatee, address(0));
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
                d.DELEGATOR_ROLE()
            )
        );
        vm.prank(delegatee);
        d.delegate{value: 1 ether}();
    }

    function testWithdrawDelegation_notDelegator_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegatee,
                d.DELEGATOR_ROLE()
            )
        );
        vm.prank(delegatee);
        d.withdrawDelegation(delegatee, 1 ether);
    }

    function testClaimDelegation_notDelegator_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegatee,
                d.DELEGATOR_ROLE()
            )
        );
        vm.prank(delegatee);
        d.claimDelegation(0);
    }

    function testWithdrawStaking_notDelegatee_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegator,
                d.DELEGATEE_ROLE()
            )
        );
        vm.prank(delegator);
        d.withdrawStaking(delegator, 1 ether);
    }

    function testClaimStaking_notDelegatee_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegator,
                d.DELEGATEE_ROLE()
            )
        );
        vm.prank(delegator);
        d.claimStaking(0);
    }

    function testTransferCnOwnership_notDelegator_reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                delegatee,
                d.DELEGATOR_ROLE()
            )
        );
        vm.prank(delegatee);
        d.transferCnOwnership(delegatee);
    }

    /* ========================================================
                        ROLE MANAGEMENT
    ======================================================== */

    function testTransferDelegator() public {
        address newDelegator = makeAddr("newDelegator");
        vm.prank(delegator);
        d.transferDelegator(newDelegator);

        assertTrue(d.hasRole(d.DELEGATOR_ROLE(), newDelegator));
        assertFalse(d.hasRole(d.DELEGATOR_ROLE(), delegator));

        // Old delegator can't operate
        vm.deal(delegator, 1 ether);
        vm.prank(delegator);
        vm.expectRevert();
        d.delegate{value: 1 ether}();

        // New delegator can operate
        vm.deal(newDelegator, 1 ether);
        vm.prank(newDelegator);
        d.delegate{value: 1 ether}();
        assertEq(d.delegation(), 1 ether);
    }

    function testTransferDelegatee() public {
        address newDelegatee = makeAddr("newDelegatee");
        vm.prank(delegatee);
        d.transferDelegatee(newDelegatee);

        assertTrue(d.hasRole(d.DELEGATEE_ROLE(), newDelegatee));
        assertFalse(d.hasRole(d.DELEGATEE_ROLE(), delegatee));
    }

    function testTransferDelegator_nullAddress_reverts() public {
        vm.prank(delegator);
        vm.expectRevert(ICnStakingDelegator.ZeroAddress.selector);
        d.transferDelegator(address(0));
    }

    function testTransferDelegatee_nullAddress_reverts() public {
        vm.prank(delegatee);
        vm.expectRevert(ICnStakingDelegator.ZeroAddress.selector);
        d.transferDelegatee(address(0));
    }

    function testTransferDelegator_toSelf_reverts() public {
        vm.prank(delegator);
        vm.expectRevert(ICnStakingDelegator.SameAddress.selector);
        d.transferDelegator(delegator);
    }

    function testTransferDelegatee_toSelf_reverts() public {
        vm.prank(delegatee);
        vm.expectRevert(ICnStakingDelegator.SameAddress.selector);
        d.transferDelegatee(delegatee);
    }

    /* ========================================================
                    DELEGATION
    ======================================================== */

    function testDelegate_basic() public {
        vm.deal(delegator, 100 ether);
        vm.prank(delegator);
        d.delegate{value: 100 ether}();

        assertEq(d.delegation(), 100 ether);
        assertEq(cn.staking(), 100 ether);
        assertEq(address(cn).balance, 100 ether);
    }

    function testDelegate_zeroValue_reverts() public {
        vm.prank(delegator);
        vm.expectRevert(ICnStakingDelegator.ZeroValue.selector);
        d.delegate{value: 0}();
    }

    function testDelegate_multipleAccumulates() public {
        vm.deal(delegator, 300 ether);

        vm.prank(delegator);
        d.delegate{value: 100 ether}();
        assertEq(d.delegation(), 100 ether);

        vm.prank(delegator);
        d.delegate{value: 200 ether}();
        assertEq(d.delegation(), 300 ether);
        assertEq(cn.staking(), 300 ether);
    }

    /* ========================================================
              WITHDRAW & CLAIM DELEGATION
    ======================================================== */

    function testWithdrawDelegation_basic() public {
        _delegatorStake(100 ether);

        vm.prank(delegator);
        d.withdrawDelegation(delegator, 40 ether);

        assertEq(d.delegation(), 60 ether);
        assertEq(cn.unstaking(), 40 ether);
        assertEq(d.delegationWithdrawalIds().length, 1);
    }

    function testWithdrawDelegation_exceedsPrincipal_reverts() public {
        _delegatorStake(100 ether);

        vm.prank(delegator);
        vm.expectRevert(ICnStakingDelegator.InsufficientDelegation.selector);
        d.withdrawDelegation(delegator, 101 ether);
    }

    function testWithdrawDelegation_exactPrincipal() public {
        _delegatorStake(100 ether);

        vm.prank(delegator);
        d.withdrawDelegation(delegator, 100 ether);

        assertEq(d.delegation(), 0);
        assertEq(cn.unstaking(), 100 ether);
    }

    function testClaimDelegation_executeAfterLockup() public {
        _delegatorStake(100 ether);

        vm.prank(delegator);
        d.withdrawDelegation(delegator, 40 ether);
        uint256 id = d.delegationWithdrawalIds()[0];

        // Warp past STAKE_LOCKUP but before 2*STAKE_LOCKUP
        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256 balBefore = delegator.balance;
        vm.prank(delegator);
        d.claimDelegation(id);

        assertEq(delegator.balance, balBefore + 40 ether);
        assertEq(d.delegation(), 60 ether); // unchanged
        assertEq(cn.staking(), 60 ether);
        assertEq(cn.unstaking(), 0);
    }

    function testClaimDelegation_autoCancelAfterDoubleLockup() public {
        _delegatorStake(100 ether);

        vm.prank(delegator);
        d.withdrawDelegation(delegator, 40 ether);
        uint256 id = d.delegationWithdrawalIds()[0];

        // Warp past 2*STAKE_LOCKUP → auto-cancel
        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);

        uint256 balBefore = delegator.balance;
        vm.prank(delegator);
        d.claimDelegation(id);

        // No transfer happened
        assertEq(delegator.balance, balBefore);
        // Principal restored
        assertEq(d.delegation(), 100 ether);
        // CN state: unstaking cleared, staking intact
        assertEq(cn.staking(), 100 ether);
        assertEq(cn.unstaking(), 0);
    }

    function testClaimDelegation_invalidId_reverts() public {
        vm.prank(delegator);
        vm.expectRevert(ICnStakingDelegator.InvalidWithdrawalId.selector);
        d.claimDelegation(999);
    }

    function testClaimDelegation_beforeLockup_reverts() public {
        _delegatorStake(100 ether);

        vm.prank(delegator);
        d.withdrawDelegation(delegator, 40 ether);
        uint256 id = d.delegationWithdrawalIds()[0];

        // Don't warp — still in lockup
        vm.prank(delegator);
        vm.expectRevert(ICnStaking.NotWithdrawableYet.selector);
        d.claimDelegation(id);
    }

    function testClaimDelegation_doubleClaim_reverts() public {
        _delegatorStake(100 ether);

        vm.prank(delegator);
        d.withdrawDelegation(delegator, 40 ether);
        uint256 id = d.delegationWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(delegator);
        d.claimDelegation(id);

        // Second claim: ID already removed from set
        vm.prank(delegator);
        vm.expectRevert(ICnStakingDelegator.InvalidWithdrawalId.selector);
        d.claimDelegation(id);
    }

    /* ========================================================
              WITHDRAW & CLAIM STAKING (VALIDATOR)
    ======================================================== */

    function testWithdrawStaking_basic() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        assertEq(d.withdrawableStaking(), 50 ether);

        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 30 ether);

        assertEq(cn.unstaking(), 30 ether);
        assertEq(d.withdrawableStaking(), 20 ether);
        assertEq(d.stakingWithdrawalIds().length, 1);
    }

    function testWithdrawStaking_exceedsAvailable_reverts() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        vm.prank(delegatee);
        vm.expectRevert(ICnStakingDelegator.InsufficientStaking.selector);
        d.withdrawStaking(delegatee, 51 ether);
    }

    function testWithdrawStaking_nothingAvailable_reverts() public {
        _delegatorStake(100 ether);
        // No validator stake → withdrawableStaking = 0

        assertEq(d.withdrawableStaking(), 0);

        vm.prank(delegatee);
        vm.expectRevert(ICnStakingDelegator.InsufficientStaking.selector);
        d.withdrawStaking(delegatee, 1);
    }

    function testWithdrawStaking_exactAmount() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 50 ether);

        assertEq(d.withdrawableStaking(), 0);
    }

    function testClaimStaking_executeAfterLockup() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 30 ether);
        uint256 id = d.stakingWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256 balBefore = delegatee.balance;
        vm.prank(delegatee);
        d.claimStaking(id);

        assertEq(delegatee.balance, balBefore + 30 ether);
        assertEq(cn.staking(), 120 ether);
        assertEq(cn.unstaking(), 0);
        assertEq(d.withdrawableStaking(), 20 ether);
    }

    function testClaimStaking_autoCancelAfterDoubleLockup() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 30 ether);
        uint256 id = d.stakingWithdrawalIds()[0];

        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);

        uint256 balBefore = delegatee.balance;
        vm.prank(delegatee);
        d.claimStaking(id);

        // No transfer
        assertEq(delegatee.balance, balBefore);
        // Self-adjusts: unstaking goes back to 0, so withdrawable restores
        assertEq(cn.unstaking(), 0);
        assertEq(d.withdrawableStaking(), 50 ether);
        // Principal unaffected
        assertEq(d.delegation(), 100 ether);
    }

    function testClaimStaking_invalidId_reverts() public {
        vm.prank(delegatee);
        vm.expectRevert(ICnStakingDelegator.InvalidWithdrawalId.selector);
        d.claimStaking(999);
    }

    /* ========================================================
                    MATH & ACCOUNTING
    ======================================================== */

    function testWithdrawableStaking_formula() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        // staking=150, unstaking=0, delegation=100 → withdrawable=50
        assertEq(d.withdrawableStaking(), 150 ether - 0 - 100 ether);
        assertEq(d.withdrawableStaking(), 50 ether);
    }

    function testWithdrawableStaking_afterDelegationWithdrawal() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        // Delegation withdrawal shouldn't affect validator's available
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 30 ether);

        // staking=150, unstaking=30, delegation=70 → withdrawable=50
        assertEq(d.withdrawableStaking(), 50 ether);
    }

    function testWithdrawableStaking_afterStakingWithdrawal() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        // Staking withdrawal shouldn't affect delegation
        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 20 ether);

        assertEq(d.delegation(), 100 ether);
        // staking=150, unstaking=20, delegation=100 → withdrawable=30
        assertEq(d.withdrawableStaking(), 30 ether);
    }

    function testWithdrawableStaking_thirdPartyStaking() public {
        _delegatorStake(100 ether);

        // Third party stakes directly to CN (permissionless without PD)
        address thirdParty = makeAddr("thirdParty");
        vm.deal(thirdParty, 25 ether);
        vm.prank(thirdParty);
        cn.delegate{value: 25 ether}();

        // Third party's stake adds to validator's withdrawable
        assertEq(d.withdrawableStaking(), 25 ether);
        assertEq(d.delegation(), 100 ether);
    }

    function testConcurrentWithdrawals_noInterference() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        // Both withdraw simultaneously
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 40 ether);

        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 30 ether);

        // State: staking=150, unstaking=70, delegation=60
        assertEq(cn.staking(), 150 ether);
        assertEq(cn.unstaking(), 70 ether);
        assertEq(d.delegation(), 60 ether);
        assertEq(d.withdrawableStaking(), 20 ether); // 150-70-60

        // Both claim after lockup
        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256 delegationId = d.delegationWithdrawalIds()[0];
        uint256 stakingId = d.stakingWithdrawalIds()[0];

        vm.prank(delegator);
        d.claimDelegation(delegationId);

        vm.prank(delegatee);
        d.claimStaking(stakingId);

        // State: staking=80, unstaking=0, delegation=60
        assertEq(cn.staking(), 80 ether);
        assertEq(cn.unstaking(), 0);
        assertEq(d.delegation(), 60 ether);
        assertEq(d.withdrawableStaking(), 20 ether);
    }

    function testDelegationAutoCancel_validatorUnaffected() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        // Delegator creates withdrawal that will auto-cancel
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 40 ether);
        uint256 id = d.delegationWithdrawalIds()[0];

        // Before cancel: delegation=60, withdrawable=50 (150-40-60=50)
        assertEq(d.withdrawableStaking(), 50 ether);

        // Auto-cancel
        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);
        vm.prank(delegator);
        d.claimDelegation(id);

        // After cancel: delegation=100 (restored), staking=150, unstaking=0
        assertEq(d.delegation(), 100 ether);
        assertEq(d.withdrawableStaking(), 50 ether); // unchanged for validator
    }

    function testStakingAutoCancel_delegationUnaffected() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 30 ether);
        uint256 id = d.stakingWithdrawalIds()[0];

        // Auto-cancel
        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);
        vm.prank(delegatee);
        d.claimStaking(id);

        // Principal unchanged, withdrawable restored
        assertEq(d.delegation(), 100 ether);
        assertEq(d.withdrawableStaking(), 50 ether);
    }

    /* ========================================================
              FULL DRAIN — BOTH SIDES TO ZERO
    ======================================================== */

    function testFullDrain_delegationFirst() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        // Drain delegation
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 100 ether);
        uint256 delId = d.delegationWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(delegator);
        d.claimDelegation(delId);

        assertEq(d.delegation(), 0);
        assertEq(cn.staking(), 50 ether);
        assertEq(d.withdrawableStaking(), 50 ether);

        // Drain validator staking
        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 50 ether);
        uint256 stakId = d.stakingWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(delegatee);
        d.claimStaking(stakId);

        assertEq(cn.staking(), 0);
        assertEq(cn.unstaking(), 0);
        assertEq(d.delegation(), 0);
        assertEq(d.withdrawableStaking(), 0);
    }

    function testFullDrain_validatorFirst() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        // Drain validator staking
        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 50 ether);
        uint256 stakId = d.stakingWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(delegatee);
        d.claimStaking(stakId);

        assertEq(d.withdrawableStaking(), 0);

        // Drain delegation
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 100 ether);
        uint256 delId = d.delegationWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(delegator);
        d.claimDelegation(delId);

        assertEq(cn.staking(), 0);
        assertEq(d.delegation(), 0);
        assertEq(d.withdrawableStaking(), 0);
    }

    /* ========================================================
              MULTI-CYCLE STAKE/UNSTAKE
    ======================================================== */

    function testMultiCycle_stakeUnstakeCancelRestake() public {
        // Cycle 1: stake
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        // Cycle 2: partial withdraw + claim
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 30 ether);
        uint256 id0 = d.delegationWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(delegator);
        d.claimDelegation(id0);
        // delegation=70, staking=120

        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 20 ether);
        uint256 id1 = d.stakingWithdrawalIds()[0];

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(delegatee);
        d.claimStaking(id1);
        // delegation=70, staking=100, withdrawable=30

        assertEq(d.delegation(), 70 ether);
        assertEq(cn.staking(), 100 ether);
        assertEq(d.withdrawableStaking(), 30 ether);

        // Cycle 3: withdraw delegation + auto-cancel
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 40 ether);
        uint256 id2 = d.delegationWithdrawalIds()[0];

        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);
        vm.prank(delegator);
        d.claimDelegation(id2);
        // delegation restored: 70-40+40=70

        assertEq(d.delegation(), 70 ether);
        assertEq(cn.staking(), 100 ether);
        assertEq(d.withdrawableStaking(), 30 ether);

        // Cycle 4: re-stake more
        _delegatorStake(50 ether);
        _validatorStake(20 ether);
        // delegation=120, staking=170, withdrawable=50

        assertEq(d.delegation(), 120 ether);
        assertEq(cn.staking(), 170 ether);
        assertEq(d.withdrawableStaking(), 50 ether);
    }

    /* ========================================================
                    MULTIPLE PENDING WITHDRAWALS
    ======================================================== */

    function testMultiplePendingWithdrawals() public {
        _delegatorStake(200 ether);
        _validatorStake(100 ether);

        // Create 3 delegation withdrawals
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 50 ether);
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 30 ether);
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 20 ether);

        assertEq(d.delegationWithdrawalIds().length, 3);
        assertEq(d.delegation(), 100 ether); // 200 - 50 - 30 - 20
        assertEq(cn.unstaking(), 100 ether);

        // Create 2 staking withdrawals
        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 40 ether);
        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 60 ether);

        assertEq(d.stakingWithdrawalIds().length, 2);
        assertEq(cn.unstaking(), 200 ether);
        assertEq(d.withdrawableStaking(), 0); // 300 - 200 - 100 = 0

        // Claim all after lockup
        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256[] memory delIds = d.delegationWithdrawalIds();
        for (uint256 i = 0; i < delIds.length; i++) {
            vm.prank(delegator);
            d.claimDelegation(delIds[i]);
        }

        uint256[] memory stakIds = d.stakingWithdrawalIds();
        for (uint256 i = 0; i < stakIds.length; i++) {
            vm.prank(delegatee);
            d.claimStaking(stakIds[i]);
        }

        assertEq(cn.staking(), 100 ether); // 300 - 100 - 100
        assertEq(cn.unstaking(), 0);
        assertEq(d.delegation(), 100 ether);
        assertEq(d.withdrawableStaking(), 0);
    }

    /* ========================================================
            CROSS-ROLE ID ISOLATION
    ======================================================== */

    function testCrossRoleIdIsolation() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        vm.prank(delegator);
        d.withdrawDelegation(delegator, 30 ether);
        uint256 delId = d.delegationWithdrawalIds()[0];

        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 20 ether);
        uint256 stakId = d.stakingWithdrawalIds()[0];

        // Delegator can't claim staking IDs
        vm.prank(delegator);
        vm.expectRevert(ICnStakingDelegator.InvalidWithdrawalId.selector);
        d.claimDelegation(stakId);

        // Delegatee can't claim delegation IDs
        vm.prank(delegatee);
        vm.expectRevert(ICnStakingDelegator.InvalidWithdrawalId.selector);
        d.claimStaking(delId);
    }

    /* ========================================================
                    ADMIN — TRANSFER CN OWNERSHIP
    ======================================================== */

    function testTransferCnOwnership() public {
        vm.prank(delegator);
        d.transferCnOwnership(delegatee);

        assertEq(cn.owner(), delegatee);
    }

    function testTransferCnOwnership_nonDelegatee_reverts() public {
        address notDelegatee = makeAddr("notDelegatee");

        vm.prank(delegator);
        vm.expectRevert(ICnStakingDelegator.NotDelegatee.selector);
        d.transferCnOwnership(notDelegatee);
    }

    function testTransferCnOwnership_withDelegation_reverts() public {
        _delegatorStake(100 ether);

        address newOwner = makeAddr("newOwner");
        vm.prank(delegator);
        vm.expectRevert(ICnStakingDelegator.DelegationNotEmpty.selector);
        d.transferCnOwnership(newOwner);
    }

    function testAfterOwnershipTransfer_operationsRevert() public {
        // Only validator stakes (no delegation), so ownership transfer is allowed
        _validatorStake(50 ether);

        vm.prank(delegator);
        d.transferCnOwnership(delegatee);

        // Delegation still works (permissionless staking)
        vm.deal(delegator, 10 ether);
        vm.prank(delegator);
        d.delegate{value: 10 ether}();

        // But withdrawal reverts (not owner anymore)
        vm.prank(delegator);
        vm.expectRevert(ICnStaking.NotUnstakingManager.selector);
        d.withdrawDelegation(delegator, 10 ether);

        vm.prank(delegatee);
        vm.expectRevert(ICnStaking.NotUnstakingManager.selector);
        d.withdrawStaking(delegatee, 10 ether);
    }

    /* ========================================================
                    VALIDATOR DIRECT STAKE ONLY
    ======================================================== */

    function testValidatorOnlyStake_noDelegation() public {
        // Only validator stakes, no delegation
        _validatorStake(50 ether);

        assertEq(d.delegation(), 0);
        assertEq(d.withdrawableStaking(), 50 ether);

        // Validator can withdraw everything
        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 50 ether);

        vm.warp(block.timestamp + STAKE_LOCKUP);
        uint256 stakId = d.stakingWithdrawalIds()[0];
        vm.prank(delegatee);
        d.claimStaking(stakId);

        assertEq(cn.staking(), 0);
        assertEq(d.withdrawableStaking(), 0);
    }

    /* ========================================================
              GETTER ARRAYS
    ======================================================== */

    function testGetterArrays() public {
        _delegatorStake(100 ether);
        _validatorStake(50 ether);

        // Create multiple withdrawals
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 10 ether);
        vm.prank(delegator);
        d.withdrawDelegation(delegator, 20 ether);

        vm.prank(delegatee);
        d.withdrawStaking(delegatee, 5 ether);

        uint256[] memory delIds = d.delegationWithdrawalIds();
        uint256[] memory stakIds = d.stakingWithdrawalIds();

        assertEq(delIds.length, 2);
        assertEq(stakIds.length, 1);

        // IDs should be unique and sequential
        assertTrue(delIds[0] != delIds[1]);
        assertTrue(delIds[0] != stakIds[0]);
    }

    /* ========================================================
                    HELPERS
    ======================================================== */

    function _delegatorStake(uint256 _amount) internal {
        vm.deal(delegator, _amount);
        vm.prank(delegator);
        d.delegate{value: _amount}();
    }

    function _validatorStake(uint256 _amount) internal {
        vm.deal(delegatee, _amount);
        vm.prank(delegatee);
        cn.delegate{value: _amount}();
    }
}
