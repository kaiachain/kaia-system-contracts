// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {Profile} from "../../src/types/Node.sol";

contract SuspendTest is Base {
    /* ========== suspendValidator ========== */

    function test_suspendValidator_success() public {
        _setupGenesisCommittee();

        vm.expectEmit(true, false, false, false);
        emit IAddressBookV2.ValidatorSuspended(genesis[0].nodeId);

        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        // Check suspended list
        address[] memory suspended = abv2.getSuspendedValidators();
        assertEq(suspended.length, 1);
        assertEq(suspended[0], genesis[0].nodeId);
    }

    function test_suspendValidator_multiple() public {
        _setupGenesisCommittee();

        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        vm.prank(owner);
        abv2.suspendValidator(genesis[1].nodeId);

        address[] memory suspended = abv2.getSuspendedValidators();
        assertEq(suspended.length, 2);
    }

    function test_suspendValidator_revert_AlreadySuspended() public {
        _setupGenesisCommittee();

        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        vm.expectRevert(IAddressBookV2.AlreadySuspended.selector);
        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);
    }

    function test_suspendValidator_revert_OnlySuspender() public {
        _setupGenesisCommittee();
        address nonOwner = makeAddr("nonOwner");

        vm.expectRevert(IAddressBookV2.OnlySuspender.selector);
        vm.prank(nonOwner);
        abv2.suspendValidator(genesis[0].nodeId);
    }

    /* ========== unsuspendValidator ========== */

    function test_unsuspendValidator_success() public {
        _setupGenesisCommittee();

        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        vm.expectEmit(true, false, false, false);
        emit IAddressBookV2.ValidatorUnsuspended(genesis[0].nodeId);

        vm.prank(owner);
        abv2.unsuspendValidator(genesis[0].nodeId);

        address[] memory suspended = abv2.getSuspendedValidators();
        assertEq(suspended.length, 0);
    }

    function test_unsuspendValidator_revert_NotSuspended() public {
        _setupGenesisCommittee();

        vm.expectRevert(IAddressBookV2.NotSuspended.selector);
        vm.prank(owner);
        abv2.unsuspendValidator(genesis[0].nodeId);
    }

    function test_unsuspendValidator_revert_OnlySuspender() public {
        _setupGenesisCommittee();
        address nonOwner = makeAddr("nonOwner");

        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        vm.expectRevert(IAddressBookV2.OnlySuspender.selector);
        vm.prank(nonOwner);
        abv2.unsuspendValidator(genesis[0].nodeId);
    }

    /* ========== suspendValidator: non-existent node ========== */

    function test_suspendValidator_nonExistentNode_succeeds() public {
        address phantom = makeAddr("phantom");

        vm.prank(owner);
        abv2.suspendValidator(phantom);

        address[] memory suspended = abv2.getSuspendedValidators();
        assertEq(suspended.length, 1);
        assertEq(suspended[0], phantom);
    }

    /* ========== suspendValidator: Registered excluded from profiles ========== */

    function test_suspendValidator_registered_excludedFromProfiles() public {
        // Registered nodes are excluded from profiles regardless of suspension
        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        Profile[] memory profiles = abv2.getAllProfiles();
        assertEq(profiles.length, 0);
    }

    /* ========== suspend + unsuspend: profiles restored ========== */

    function test_suspend_unsuspend_profilesRestored() public {
        _setupGenesisCommittee();
        uint256 profilesBefore = abv2.getAllProfiles().length;

        // getAllProfiles() now includes suspended — length unchanged by suspend/unsuspend
        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);
        assertEq(abv2.getAllProfiles().length, profilesBefore);
        assertEq(abv2.getSuspendedValidators().length, 1);

        vm.prank(owner);
        abv2.unsuspendValidator(genesis[0].nodeId);
        assertEq(abv2.getAllProfiles().length, profilesBefore);
        assertEq(abv2.getSuspendedValidators().length, 0);
    }

    /* ========== suspend then unsuspend round-trip ========== */

    function test_suspend_unsuspend_roundTrip() public {
        _setupGenesisCommittee();

        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);
        assertEq(abv2.getSuspendedValidators().length, 1);

        vm.prank(owner);
        abv2.unsuspendValidator(genesis[0].nodeId);
        assertEq(abv2.getSuspendedValidators().length, 0);

        // Can suspend again after unsuspending
        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);
        assertEq(abv2.getSuspendedValidators().length, 1);
    }
}
