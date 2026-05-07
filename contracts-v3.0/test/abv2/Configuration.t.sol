// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {
    IAddressBookV2,
    UINT_CFG_PAUSE_TIMEOUT,
    UINT_CFG_IDLE_TIMEOUT,
    UINT_CFG_PFS_THRESHOLD,
    UINT_CFG_CFS_THRESHOLD,
    UINT_CFG_MAX_NODE_COUNT,
    UINT_CFG_MAX_VAL_ACTIVE_PAUSED,
    UINT_CFG_MAX_CAND_READY,
    ADDR_CFG_KEF,
    ADDR_CFG_KIF,
    ADDR_CFG_KPF
} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";

contract ConfigurationTest is Base {
    // NOTE: initialize validation tests (zero config values) moved to InitializeValidators.t.sol
    // as they now test ABv2DataContract constructor reverts.

    address internal nonOwner;

    function setUp() public override {
        super.setUp();
        nonOwner = makeAddr("nonOwner");
    }

    /* ========== updatePauseTimeout: same value ========== */

    function test_updatePauseTimeout_sameValue() public {
        (uint256 currentPause,) = abv2.getTimeouts();

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.UintConfigUpdated(UINT_CFG_PAUSE_TIMEOUT, currentPause, currentPause);

        vm.prank(owner);
        abv2.updatePauseTimeout(currentPause);
    }

    /* ========== updatePauseTimeout ========== */

    function test_updatePauseTimeout_success() public {
        uint256 newTimeout = 12 hours;

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.UintConfigUpdated(UINT_CFG_PAUSE_TIMEOUT, DEFAULT_PAUSE_TIMEOUT, newTimeout);

        vm.prank(owner);
        abv2.updatePauseTimeout(newTimeout);

        (uint256 pauseTimeout,) = abv2.getTimeouts();
        assertEq(pauseTimeout, newTimeout);
    }

    function test_updatePauseTimeout_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updatePauseTimeout(0);
    }

    function test_updatePauseTimeout_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updatePauseTimeout(1 hours);
    }

    /* ========== updateIdleTimeout ========== */

    function test_updateIdleTimeout_success() public {
        uint256 newTimeout = 14 days;

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.UintConfigUpdated(UINT_CFG_IDLE_TIMEOUT, DEFAULT_IDLE_TIMEOUT, newTimeout);

        vm.prank(owner);
        abv2.updateIdleTimeout(newTimeout);

        (, uint256 idleTimeout) = abv2.getTimeouts();
        assertEq(idleTimeout, newTimeout);
    }

    function test_updateIdleTimeout_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updateIdleTimeout(0);
    }

    function test_updateIdleTimeout_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updateIdleTimeout(1 days);
    }

    /* ========== updatePfsThreshold ========== */

    function test_updatePfsThreshold_success() public {
        uint256 newThreshold = 5;

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.UintConfigUpdated(UINT_CFG_PFS_THRESHOLD, DEFAULT_PFS_THRESHOLD, newThreshold);

        vm.prank(owner);
        abv2.updatePfsThreshold(newThreshold);

        assertEq(abv2.getPfsThreshold(), newThreshold);
    }

    function test_updatePfsThreshold_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updatePfsThreshold(0);
    }

    function test_updatePfsThreshold_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updatePfsThreshold(3);
    }

    /* ========== updateCfsThreshold ========== */

    function test_updateCfsThreshold_success() public {
        uint256 newThreshold = 500;

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.UintConfigUpdated(UINT_CFG_CFS_THRESHOLD, 300, newThreshold);

        vm.prank(owner);
        abv2.updateCfsThreshold(newThreshold);

        assertEq(abv2.getCfsThreshold(), newThreshold);
    }

    function test_updateCfsThreshold_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updateCfsThreshold(0);
    }

    function test_updateCfsThreshold_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updateCfsThreshold(500);
    }

    /* ========== updateMaxNodeCount ========== */

    function test_updateMaxNodeCount_success() public {
        uint256 newCount = 50;

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.UintConfigUpdated(UINT_CFG_MAX_NODE_COUNT, DEFAULT_MAX_NODE_COUNT, newCount);

        vm.prank(owner);
        abv2.updateMaxNodeCount(newCount);

        (uint256 maxValCount,) = abv2.getMaxCounts();
        assertEq(maxValCount, newCount);
    }

    function test_updateMaxNodeCount_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updateMaxNodeCount(0);
    }

    function test_updateMaxNodeCount_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updateMaxNodeCount(50);
    }

    /* ========== updateMaxCandReadyCount ========== */

    function test_updateMaxCandReadyCount_success() public {
        uint256 newCount = 10;

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.UintConfigUpdated(UINT_CFG_MAX_CAND_READY, DEFAULT_MAX_READY_CAND_COUNT, newCount);

        vm.prank(owner);
        abv2.updateMaxCandReadyCount(newCount);

        (, uint256 maxReadyCandCount) = abv2.getMaxCounts();
        assertEq(maxReadyCandCount, newCount);
    }

    function test_updateMaxCandReadyCount_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updateMaxCandReadyCount(0);
    }

    function test_updateMaxCandReadyCount_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updateMaxCandReadyCount(5);
    }

    /* ========== updateKefAddress ========== */

    function test_updateKefAddress_success() public {
        address newAddr = makeAddr("newKef");

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.AddressConfigUpdated(ADDR_CFG_KEF, DEFAULT_KEF_ADDRESS, newAddr);

        vm.prank(owner);
        abv2.updateKefAddress(newAddr);

        (address kef,,) = abv2.getFundAddresses();
        assertEq(kef, newAddr);
    }

    function test_updateKefAddress_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updateKefAddress(address(0));
    }

    function test_updateKefAddress_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updateKefAddress(makeAddr("newKef"));
    }

    /* ========== updateKifAddress ========== */

    function test_updateKifAddress_success() public {
        address newAddr = makeAddr("newKif");

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.AddressConfigUpdated(ADDR_CFG_KIF, DEFAULT_KIF_ADDRESS, newAddr);

        vm.prank(owner);
        abv2.updateKifAddress(newAddr);

        (, address kif,) = abv2.getFundAddresses();
        assertEq(kif, newAddr);
    }

    function test_updateKifAddress_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updateKifAddress(address(0));
    }

    function test_updateKifAddress_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updateKifAddress(makeAddr("newKif"));
    }

    /* ========== updateKpfAddress ========== */

    function test_updateKpfAddress_success() public {
        address newAddr = makeAddr("newKpf");

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.AddressConfigUpdated(ADDR_CFG_KPF, DEFAULT_KPF_ADDRESS, newAddr);

        vm.prank(owner);
        abv2.updateKpfAddress(newAddr);

        (,, address kpf) = abv2.getFundAddresses();
        assertEq(kpf, newAddr);
    }

    function test_updateKpfAddress_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updateKpfAddress(address(0));
    }

    function test_updateKpfAddress_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updateKpfAddress(makeAddr("newKpf"));
    }

    /* ========== updateMaxValActivePausedCount ========== */

    function test_updateMaxValActivePausedCount_success() public {
        uint256 newCount = 30;

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.UintConfigUpdated(UINT_CFG_MAX_VAL_ACTIVE_PAUSED, DEFAULT_MAX_NODE_COUNT, newCount);

        vm.prank(owner);
        abv2.updateMaxValActivePausedCount(newCount);

        assertEq(abv2.getMaxValActivePausedCount(), newCount);
    }

    function test_updateMaxValActivePausedCount_revert_zero() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(owner);
        abv2.updateMaxValActivePausedCount(0);
    }

    function test_updateMaxValActivePausedCount_revert_OnlyConfigurator() public {
        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonOwner);
        abv2.updateMaxValActivePausedCount(30);
    }

    /* ========== getSlotLimitsFor ========== */

    function test_getSlotLimitsFor_zero() public view {
        (uint256 maxSlot, uint256 minActive) = abv2.getSlotLimitsFor(0);
        assertEq(maxSlot, 0, "sf=0: maxSlot");
        assertEq(minActive, 0, "sf=0: minActive");
    }

    function test_getSlotLimitsFor_four() public view {
        // minActive=ceil(8/3)=3, totalBudget=1, maxSlot=ceil(1/2)=1
        (uint256 maxSlot, uint256 minActive) = abv2.getSlotLimitsFor(4);
        assertEq(maxSlot, 1, "sf=4: maxSlot");
        assertEq(minActive, 3, "sf=4: minActive");
    }

    function test_getSlotLimitsFor_ten() public view {
        // minActive=ceil(20/3)=7, totalBudget=3, maxSlot=ceil(3/2)=2
        (uint256 maxSlot, uint256 minActive) = abv2.getSlotLimitsFor(10);
        assertEq(maxSlot, 2, "sf=10: maxSlot");
        assertEq(minActive, 7, "sf=10: minActive");
    }
}
