// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CnStakingBase} from "./CnStakingBase.t.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {ICnStaking} from "../../src/CnStaking/CnStakingV4/interfaces/ICnStaking.sol";
import {PublicDelegation} from "../../src/PublicDelegation/PublicDelegation.sol";
import {IPublicDelegation} from "../../src/PublicDelegation/interfaces/IPublicDelegation.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/* ================================================================
 *  Initialization Tests
 * ================================================================ */

contract CnStakingV4_Initialization is CnStakingBase {
    function test_initialize_setsOwner() public {
        CnStakingV4 cn = _deployCnStaking(owner);

        assertEq(cn.owner(), owner);
        assertEq(cn.publicDelegation(), address(0));
        assertEq(cn.staking(), 0);
        assertEq(cn.unstaking(), 0);
        assertEq(cn.withdrawalRequestCount(), 0);
    }

    function test_initializeWithPD_setsAllFields() public {
        (CnStakingV4 cn, PublicDelegation pd) = _deployCnStakingWithPDDefaults();

        assertEq(cn.owner(), owner);
        assertEq(cn.publicDelegation(), address(pd));
    }

    function test_initialize_cannotCallTwice() public {
        CnStakingV4 cn = _deployCnStaking(owner);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        cn.initialize(owner);
    }

    function test_initializeWithPD_cannotCallTwice() public {
        (CnStakingV4 cn, ) = _deployCnStakingWithPDDefaults();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        cn.initializeWithPD(owner, address(1));
    }

    function test_initialize_revertsOnZeroOwner() public {
        // Factory always initializes, so test via raw BeaconProxy
        address rawProxy = address(new BeaconProxy(address(cnBeacon), ""));
        vm.expectRevert(ICnStaking.ZeroAddress.selector);
        CnStakingV4(payable(rawProxy)).initialize(address(0));
    }

    function test_constants() public {
        CnStakingV4 cn = _deployCnStaking(owner);

        assertEq(cn.VERSION(), 4);
        assertEq(keccak256(bytes(cn.CONTRACT_TYPE())), keccak256("CnStakingContract"));
        assertEq(cn.STAKE_LOCKUP(), 1 weeks);
    }
}

/* ================================================================
 *  Staking Tests (No PD)
 * ================================================================ */

contract CnStakingV4_Staking_NoPD is CnStakingBase {
    CnStakingV4 internal cn;

    function setUp() public override {
        super.setUp();
        cn = _deployCnStaking(owner);
    }

    function test_delegate_anyoneCanCall() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        cn.delegate{value: 10 ether}();

        assertEq(cn.staking(), 10 ether);
        assertEq(address(cn).balance, 10 ether);
    }

    function test_receive_anyoneCanCall() public {
        vm.deal(user1, 5 ether);
        vm.prank(user1);
        (bool ok, ) = address(cn).call{value: 5 ether}("");
        assertTrue(ok);

        assertEq(cn.staking(), 5 ether);
    }

    function test_delegate_multipleDeposits() public {
        vm.deal(user1, 20 ether);
        vm.prank(user1);
        cn.delegate{value: 10 ether}();

        vm.deal(user2, 20 ether);
        vm.prank(user2);
        cn.delegate{value: 5 ether}();

        assertEq(cn.staking(), 15 ether);
    }

    function test_delegate_revertsOnZeroValue() public {
        vm.expectRevert(ICnStaking.ZeroValue.selector);
        cn.delegate{value: 0}();
    }

    function test_receive_revertsOnZeroValue() public {
        vm.expectRevert(ICnStaking.InvalidValue.selector);
        address(cn).call{value: 0}("");
    }

    function test_delegate_emitsEvent() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);

        vm.expectEmit(true, false, false, true, address(cn));
        emit ICnStaking.DelegateKaia(user1, 10 ether);

        cn.delegate{value: 10 ether}();
    }
}

/* ================================================================
 *  Staking Tests (With PD)
 * ================================================================ */

contract CnStakingV4_Staking_WithPD is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPDDefaults();
    }

    function test_delegate_onlyPDCanCall() public {
        vm.deal(address(pd), 10 ether);
        vm.prank(address(pd));
        cn.delegate{value: 10 ether}();

        assertEq(cn.staking(), INITIAL_LOCKUP + 10 ether);
    }

    function test_delegate_revertsForNonPD() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        vm.expectRevert(ICnStaking.NotStaker.selector);
        cn.delegate{value: 10 ether}();
    }

    function test_receive_onlyPDCanCall() public {
        vm.deal(address(pd), 10 ether);
        vm.prank(address(pd));
        (bool ok, ) = address(cn).call{value: 10 ether}("");
        assertTrue(ok);
        assertEq(cn.staking(), INITIAL_LOCKUP + 10 ether);
    }

    function test_receive_revertsForNonPD() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        vm.expectRevert(ICnStaking.NotStaker.selector);
        address(cn).call{value: 10 ether}("");
    }
}

/* ================================================================
 *  Unstaking Tests (No PD)
 * ================================================================ */

contract CnStakingV4_Unstaking_NoPD is CnStakingBase {
    CnStakingV4 internal cn;

    function setUp() public override {
        super.setUp();
        cn = _deployCnStaking(owner);

        // Stake 100 ether
        vm.deal(user1, 100 ether);
        vm.prank(user1);
        cn.delegate{value: 100 ether}();
    }

    function test_approveStakingWithdrawal_ownerCanCall() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        assertEq(id, 0);
        assertEq(cn.unstaking(), 10 ether);
        assertEq(cn.withdrawalRequestCount(), 1);
    }

    function test_approveStakingWithdrawal_revertsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert(ICnStaking.NotUnstakingManager.selector);
        cn.approveStakingWithdrawal(user1, 10 ether);
    }

    function test_approveStakingWithdrawal_revertsOnZeroValue() public {
        vm.prank(owner);
        vm.expectRevert(ICnStaking.InvalidValue.selector);
        cn.approveStakingWithdrawal(user1, 0);
    }

    function test_approveStakingWithdrawal_revertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(ICnStaking.ZeroAddress.selector);
        cn.approveStakingWithdrawal(address(0), 10 ether);
    }

    function test_approveStakingWithdrawal_revertsOnInvalidValue() public {
        vm.prank(owner);
        vm.expectRevert(ICnStaking.InvalidValue.selector);
        cn.approveStakingWithdrawal(user1, 101 ether);
    }

    function test_approveStakingWithdrawal_emitsEvent() public {
        vm.prank(owner);

        vm.expectEmit(true, true, false, true, address(cn));
        emit ICnStaking.ApproveStakingWithdrawal(0, user1, 10 ether, block.timestamp + STAKE_LOCKUP);

        cn.approveStakingWithdrawal(user1, 10 ether);
    }

    function test_approveStakingWithdrawal_multipleRequests() public {
        vm.startPrank(owner);
        uint256 id0 = cn.approveStakingWithdrawal(user1, 10 ether);
        uint256 id1 = cn.approveStakingWithdrawal(user2, 20 ether);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(cn.unstaking(), 30 ether);
        assertEq(cn.withdrawalRequestCount(), 2);
    }

    function test_cancelApprovedStakingWithdrawal() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.prank(owner);
        cn.cancelApprovedStakingWithdrawal(id);

        assertEq(cn.unstaking(), 0);
        (, , , ICnStaking.WithdrawalStakingState state) = cn.getApprovedStakingWithdrawalInfo(id);
        assertEq(uint256(state), uint256(ICnStaking.WithdrawalStakingState.Canceled));
    }

    function test_cancelApprovedStakingWithdrawal_revertsForNonOwner() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.prank(user1);
        vm.expectRevert(ICnStaking.NotUnstakingManager.selector);
        cn.cancelApprovedStakingWithdrawal(id);
    }

    function test_cancelApprovedStakingWithdrawal_revertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert(ICnStaking.WithdrawalNotFound.selector);
        cn.cancelApprovedStakingWithdrawal(999);
    }

    function test_cancelApprovedStakingWithdrawal_revertsIfAlreadyCanceled() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.prank(owner);
        cn.cancelApprovedStakingWithdrawal(id);

        vm.prank(owner);
        vm.expectRevert(ICnStaking.InvalidWithdrawalState.selector);
        cn.cancelApprovedStakingWithdrawal(id);
    }

    function test_cancelApprovedStakingWithdrawal_emitsEvent() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.prank(owner);

        vm.expectEmit(true, true, false, true, address(cn));
        emit ICnStaking.CancelApprovedStakingWithdrawal(id, user1, 10 ether);

        cn.cancelApprovedStakingWithdrawal(id);
    }

    function test_withdrawApprovedStaking_executesAfterLockup() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.warp(block.timestamp + STAKE_LOCKUP);

        uint256 balBefore = user1.balance;
        vm.prank(owner);
        cn.withdrawApprovedStaking(id);

        assertEq(user1.balance - balBefore, 10 ether);
        assertEq(cn.staking(), 90 ether);
        assertEq(cn.unstaking(), 0);

        (, , , ICnStaking.WithdrawalStakingState state) = cn.getApprovedStakingWithdrawalInfo(id);
        assertEq(uint256(state), uint256(ICnStaking.WithdrawalStakingState.Transferred));
    }

    function test_withdrawApprovedStaking_autoCancelsAfterDoubleLockup() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        // Warp past 2 * STAKE_LOCKUP
        vm.warp(block.timestamp + 2 * STAKE_LOCKUP);

        uint256 balBefore = user1.balance;
        vm.prank(owner);
        cn.withdrawApprovedStaking(id);

        // No transfer happened
        assertEq(user1.balance, balBefore);
        // Staking not reduced (auto-cancel)
        assertEq(cn.staking(), 100 ether);
        assertEq(cn.unstaking(), 0);

        (, , , ICnStaking.WithdrawalStakingState state) = cn.getApprovedStakingWithdrawalInfo(id);
        assertEq(uint256(state), uint256(ICnStaking.WithdrawalStakingState.Canceled));
    }

    function test_withdrawApprovedStaking_revertsBeforeLockup() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.prank(owner);
        vm.expectRevert(ICnStaking.NotWithdrawableYet.selector);
        cn.withdrawApprovedStaking(id);
    }

    function test_withdrawApprovedStaking_revertsIfNotFound() public {
        vm.prank(owner);
        vm.expectRevert(ICnStaking.WithdrawalNotFound.selector);
        cn.withdrawApprovedStaking(999);
    }

    function test_withdrawApprovedStaking_revertsIfAlreadyTransferred() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(owner);
        cn.withdrawApprovedStaking(id);

        vm.prank(owner);
        vm.expectRevert(ICnStaking.InvalidWithdrawalState.selector);
        cn.withdrawApprovedStaking(id);
    }

    function test_withdrawApprovedStaking_emitsEvent() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.warp(block.timestamp + STAKE_LOCKUP);
        vm.prank(owner);

        vm.expectEmit(true, true, false, true, address(cn));
        emit ICnStaking.WithdrawApprovedStaking(id, user1, 10 ether);

        cn.withdrawApprovedStaking(id);
    }
}

/* ================================================================
 *  Unstaking Tests (With PD)
 * ================================================================ */

contract CnStakingV4_Unstaking_WithPD is CnStakingBase {
    CnStakingV4 internal cn;
    PublicDelegation internal pd;

    function setUp() public override {
        super.setUp();
        (cn, pd) = _deployCnStakingWithPDDefaults();

        // Stake 100 ether via PD
        _stakeViaPD(pd, user1, 100 ether);
    }

    function test_approveStakingWithdrawal_onlyPDCanCall() public {
        vm.prank(address(pd));
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);
        assertEq(id, 0);
    }

    function test_approveStakingWithdrawal_ownerCannotCallWhenPDSet() public {
        vm.prank(owner);
        vm.expectRevert(ICnStaking.NotUnstakingManager.selector);
        cn.approveStakingWithdrawal(user1, 10 ether);
    }

    function test_cancelApprovedStakingWithdrawal_onlyPDCanCall() public {
        vm.prank(address(pd));
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.prank(address(pd));
        cn.cancelApprovedStakingWithdrawal(id);
    }

    function test_withdrawApprovedStaking_onlyPDCanCall() public {
        vm.prank(address(pd));
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        vm.warp(block.timestamp + STAKE_LOCKUP);

        vm.prank(address(pd));
        cn.withdrawApprovedStaking(id);
    }
}

/* ================================================================
 *  Redelegation Tests
 * ================================================================ */

contract CnStakingV4_Redelegation is CnStakingBase {
    CnStakingV4 internal sourceCn;
    PublicDelegation internal sourcePd;
    CnStakingV4 internal targetCn;
    PublicDelegation internal targetPd;

    function setUp() public override {
        super.setUp();

        // Deploy source node
        (sourceCn, sourcePd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "SourceGC"
            })
        );

        // Deploy target node
        (targetCn, targetPd) = _deployCnStakingWithPD(
            makeAddr("targetOwner"),
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TargetGC"
            })
        );

        // Stake 100 ether in source via PD
        _stakeViaPD(sourcePd, user1, 100 ether);
    }

    function test_redelegate_works() public {
        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), 50 ether);

        assertEq(sourceCn.staking(), INITIAL_LOCKUP + 50 ether);
        // Target should have received the KAIA via handleRedelegation → PD.stakeFor
        assertEq(targetCn.staking(), INITIAL_LOCKUP + 50 ether);
    }

    function test_redelegate_revertsWhenPDNotSet() public {
        CnStakingV4 noPdCn = _deployCnStaking(makeAddr("noPdOwner"));

        vm.prank(user1);
        vm.expectRevert(ICnStaking.RedelegationDisabled.selector);
        noPdCn.redelegate(user1, address(targetCn), 10 ether);
    }

    function test_redelegate_revertsForNonPDCaller() public {
        vm.prank(user1);
        vm.expectRevert(ICnStaking.RedelegationDisabled.selector);
        sourceCn.redelegate(user1, address(targetCn), 10 ether);
    }

    function test_redelegate_revertsToSelf() public {
        vm.prank(address(sourcePd));
        vm.expectRevert(ICnStaking.InvalidTarget.selector);
        sourceCn.redelegate(user1, address(sourceCn), 10 ether);
    }

    function test_redelegate_revertsForNonFactoryTarget() public {
        // Deploy a CnStaking directly (not via factory) — not tracked as factory-deployed
        address rawProxy = address(new BeaconProxy(address(cnBeacon), ""));
        CnStakingV4(payable(rawProxy)).initialize(owner);

        vm.prank(address(sourcePd));
        vm.expectRevert(ICnStaking.InvalidTarget.selector);
        sourceCn.redelegate(user1, rawProxy, 10 ether);
    }

    function test_redelegate_revertsWhenFactoryNotRegistered() public {
        // Mock Registry to return address(0) for CnStakingFactory
        vm.mockCall(
            REGISTRY,
            abi.encodeWithSignature("getActiveAddr(string)", "CnStakingFactory"),
            abi.encode(address(0))
        );

        vm.prank(address(sourcePd));
        vm.expectRevert(ICnStaking.InvalidTarget.selector);
        sourceCn.redelegate(user1, address(targetCn), 10 ether);
    }

    function test_redelegate_revertsOnZeroValue() public {
        vm.prank(address(sourcePd));
        vm.expectRevert(ICnStaking.InvalidValue.selector);
        sourceCn.redelegate(user1, address(targetCn), 0);
    }

    function test_redelegate_revertsOnInvalidValue() public {
        vm.prank(address(sourcePd));
        vm.expectRevert(ICnStaking.InvalidValue.selector);
        sourceCn.redelegate(user1, address(targetCn), 200 ether);
    }

    function test_redelegate_cooldownEnforced() public {
        // Redelegate source → target: sets targetCn.lastRedelegation[user1]
        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), 50 ether);

        // user1 now has shares in targetPd. Try to redelegate target → source immediately.
        // Cooldown is on targetCn because handleRedelegation set lastRedelegation[user1].
        vm.prank(address(targetPd));
        vm.expectRevert(ICnStaking.RedelegationCooldown.selector);
        targetCn.redelegate(user1, address(sourceCn), 10 ether);
    }

    function test_redelegate_cooldownResetsAfterLockup() public {
        // Redelegate source → target
        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), 50 ether);

        // Warp past cooldown
        vm.warp(block.timestamp + STAKE_LOCKUP);

        // Now target → source should succeed
        vm.prank(address(targetPd));
        targetCn.redelegate(user1, address(sourceCn), 10 ether);

        assertEq(targetCn.staking(), INITIAL_LOCKUP + 40 ether);
        assertEq(sourceCn.staking(), INITIAL_LOCKUP + 60 ether);
    }

    function test_redelegate_emitsEvent() public {
        vm.prank(address(sourcePd));

        vm.expectEmit(true, true, false, true, address(sourceCn));
        emit ICnStaking.Redelegation(user1, address(targetCn), 50 ether);

        sourceCn.redelegate(user1, address(targetCn), 50 ether);
    }

    function test_redelegate_revertsOnZeroUser() public {
        vm.prank(address(sourcePd));
        vm.expectRevert(ICnStaking.ZeroAddress.selector);
        sourceCn.redelegate(address(0), address(targetCn), 10 ether);
    }
}

/* ================================================================
 *  HandleRedelegation Tests
 * ================================================================ */

contract CnStakingV4_HandleRedelegation is CnStakingBase {
    CnStakingV4 internal sourceCn;
    PublicDelegation internal sourcePd;
    CnStakingV4 internal targetCn;
    PublicDelegation internal targetPd;

    function setUp() public override {
        super.setUp();

        (sourceCn, sourcePd) = _deployCnStakingWithPD(
            makeAddr("sourceOwner"),
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "SourceGC"
            })
        );

        (targetCn, targetPd) = _deployCnStakingWithPD(
            owner,
            IPublicDelegation.PDConstructorArgs({
                owner: owner,
                commissionTo: commissionTo,
                commissionRate: 0,
                gcName: "TargetGC"
            })
        );

        _stakeViaPD(sourcePd, user1, 50 ether);
    }

    function test_handleRedelegation_revertsWhenPDNotSet() public {
        CnStakingV4 noPdCn = _deployCnStaking(makeAddr("noPdOwner"));

        // Use a factory-deployed CN as caller
        CnStakingV4 callerCn = _deployCnStaking(makeAddr("callerOwner"));
        vm.deal(address(callerCn), 10 ether);
        vm.prank(address(callerCn));
        vm.expectRevert(ICnStaking.RedelegationDisabled.selector);
        noPdCn.handleRedelegation{value: 10 ether}(user1);
    }

    function test_handleRedelegation_revertsForNonFactoryCaller() public {
        vm.deal(user1, 10 ether);
        vm.prank(user1);
        vm.expectRevert(ICnStaking.InvalidTarget.selector);
        targetCn.handleRedelegation{value: 10 ether}(user1);
    }

    function test_handleRedelegation_revertsOnZeroUser() public {
        // Use a factory-deployed CN as caller
        CnStakingV4 callerCn = _deployCnStaking(makeAddr("callerOwner"));
        vm.deal(address(callerCn), 10 ether);
        vm.prank(address(callerCn));
        vm.expectRevert(ICnStaking.ZeroAddress.selector);
        targetCn.handleRedelegation{value: 10 ether}(address(0));
    }

    function test_handleRedelegation_setsLastRedelegation() public {
        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), 25 ether);

        assertEq(targetCn.lastRedelegation(user1), block.timestamp);
    }

    function test_handleRedelegation_emitsEvent() public {
        vm.expectEmit(true, true, true, true, address(targetCn));
        emit ICnStaking.HandleRedelegation(user1, address(sourceCn), address(targetCn), 25 ether);

        vm.prank(address(sourcePd));
        sourceCn.redelegate(user1, address(targetCn), 25 ether);
    }
}

/* ================================================================
 *  Getter Tests
 * ================================================================ */

contract CnStakingV4_Getters is CnStakingBase {
    CnStakingV4 internal cn;

    function setUp() public override {
        super.setUp();
        cn = _deployCnStaking(owner);

        vm.deal(user1, 100 ether);
        vm.prank(user1);
        cn.delegate{value: 100 ether}();
    }

    function test_getApprovedStakingWithdrawalInfo() public {
        vm.prank(owner);
        uint256 id = cn.approveStakingWithdrawal(user1, 10 ether);

        (address to, uint256 value, uint256 withdrawableFrom, ICnStaking.WithdrawalStakingState state) = cn
            .getApprovedStakingWithdrawalInfo(id);

        assertEq(to, user1);
        assertEq(value, 10 ether);
        assertEq(withdrawableFrom, block.timestamp + STAKE_LOCKUP);
        assertEq(uint256(state), uint256(ICnStaking.WithdrawalStakingState.Unknown));
    }

    function test_getApprovedStakingWithdrawalIds_filterByState() public {
        vm.startPrank(owner);
        cn.approveStakingWithdrawal(user1, 10 ether); // id 0 — Unknown
        cn.approveStakingWithdrawal(user1, 20 ether); // id 1 — Unknown
        cn.cancelApprovedStakingWithdrawal(0); // id 0 → Canceled
        vm.stopPrank();

        uint256[] memory unknownIds = cn.getApprovedStakingWithdrawalIds(
            0,
            0,
            ICnStaking.WithdrawalStakingState.Unknown
        );
        assertEq(unknownIds.length, 1);
        assertEq(unknownIds[0], 1);

        uint256[] memory canceledIds = cn.getApprovedStakingWithdrawalIds(
            0,
            0,
            ICnStaking.WithdrawalStakingState.Canceled
        );
        assertEq(canceledIds.length, 1);
        assertEq(canceledIds[0], 0);
    }

    function test_lastRedelegation_defaultZero() public view {
        assertEq(cn.lastRedelegation(user1), 0);
    }
}
