// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {ABv2ConfigLib, ConfigSlot} from "../../src/libraries/ABv2ConfigLib.sol";

/// @title StorageSlotTest
/// @notice Verifies that ABv2ConfigLib slot offsets match the actual ABv2Storage struct layout.
///         Catches offset drift when fields are added, removed, or reordered.
contract StorageSlotTest is Base {
    bytes32 constant BASE = ABv2ConfigLib.STORAGE_LOCATION;

    function _loadSlot(uint256 offset) internal view returns (uint256) {
        bytes32 slot = bytes32(uint256(BASE) + offset);
        return uint256(vm.load(ABV2_ADDRESS, slot));
    }

    function _loadSlotAddress(uint256 offset) internal view returns (address) {
        return address(uint160(_loadSlot(offset)));
    }

    function test_slot_pfsThreshold() public view {
        assertEq(_loadSlot(10), abv2.getPfsThreshold(), "PFS_THRESHOLD offset mismatch");
    }

    function test_slot_cfsThreshold() public view {
        assertEq(_loadSlot(11), abv2.getCfsThreshold(), "CFS_THRESHOLD offset mismatch");
    }

    function test_slot_pauseTimeout() public view {
        (uint256 pauseTimeout, ) = abv2.getTimeouts();
        assertEq(_loadSlot(12), pauseTimeout, "PAUSE_TIMEOUT offset mismatch");
    }

    function test_slot_idleTimeout() public view {
        (, uint256 idleTimeout) = abv2.getTimeouts();
        assertEq(_loadSlot(13), idleTimeout, "IDLE_TIMEOUT offset mismatch");
    }

    function test_slot_maxNodeCount() public view {
        (uint256 maxValCount, ) = abv2.getMaxCounts();
        assertEq(_loadSlot(14), maxValCount, "MAX_NODE_COUNT offset mismatch");
    }

    function test_slot_maxCandReadyCount() public view {
        (, uint256 maxReadyCandCount) = abv2.getMaxCounts();
        assertEq(_loadSlot(15), maxReadyCandCount, "MAX_CAND_READY_COUNT offset mismatch");
    }

    function test_slot_epochVACount() public {
        _setupGenesisCommittee(); // epochVACount = 4
        assertEq(_loadSlot(16), abv2.getEpochVACount(), "epochVACount offset mismatch");
    }

    function test_slot_maxValActivePausedCount() public view {
        assertEq(_loadSlot(17), abv2.getMaxValActivePausedCount(), "MAX_VAL_ACTIVE_PAUSED_COUNT offset mismatch");
    }

    function test_slot_kefAddress() public view {
        (address kef, , ) = abv2.getFundAddresses();
        assertEq(_loadSlotAddress(18), kef, "KEF_ADDRESS offset mismatch");
    }

    function test_slot_kifAddress() public view {
        (, address kif, ) = abv2.getFundAddresses();
        assertEq(_loadSlotAddress(19), kif, "KIF_ADDRESS offset mismatch");
    }

    function test_slot_kpfAddress() public view {
        (, , address kpf) = abv2.getFundAddresses();
        assertEq(_loadSlotAddress(20), kpf, "KPF_ADDRESS offset mismatch");
    }

    function test_slot_suspender() public view {
        assertEq(_loadSlotAddress(21), abv2.getSuspender(), "SUSPENDER offset mismatch");
    }

    function test_slot_configurator() public view {
        assertEq(_loadSlotAddress(22), abv2.getConfigurator(), "CONFIGURATOR offset mismatch");
    }
}
