// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {STv3Base} from "./Base.t.sol";
import {IStakingTrackerV3} from "../../src/StakingTrackerV3/interfaces/IStakingTrackerV3.sol";
import {IRegistry} from "../../src/system/IRegistry.sol";

contract EdgeCasesTest is STv3Base {
    /* ========== WrappedKaia null check ========== */

    function test_createTracker_wKaiaNotRegistered_clPoolBalanceTreatedAsZero() public {
        // Setup CLRegistry with a pool for GC 1
        address pool = makeAddr("clPool1");
        uint256[] memory gcIds = new uint256[](1);
        gcIds[0] = 1;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        _setupCLRegistry(gcIds, pools);

        // Override WrappedKaia to return address(0) (not registered)
        vm.mockCall(
            REGISTRY_ADDRESS, abi.encodeCall(IRegistry.getActiveAddr, ("WrappedKaia")), abi.encode(address(0))
        );

        // createTracker should NOT revert — CLPool balance treated as 0
        uint256 trackerId = _createTracker(100);

        // GC 1 should only have CnStaking balance (no CLPool contribution)
        (uint256 cnBal, uint256 gcBal) = stv3.getTrackedGCBalance(trackerId, 1);
        assertEq(cnBal, MIN_STAKE);
        assertEq(gcBal, MIN_STAKE); // no CLPool balance added

        // CLPool should still be marked but with 0 balance
        assertTrue(stv3.isCLPool(trackerId, pool));
        assertEq(stv3.stakingToGCId(trackerId, pool), 1);
    }

    function test_refreshStake_wKaiaNotRegistered_clPoolBalanceTreatedAsZero() public {
        // Setup CLRegistry with a pool for GC 1, initially with balance
        address pool = makeAddr("clPool1");
        uint256[] memory gcIds = new uint256[](1);
        gcIds[0] = 1;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        _setupCLRegistry(gcIds, pools);
        _mockCLPoolBalance(pool, 10_000_000 ether);

        uint256 trackerId = _createTracker(100);

        // Verify initial state includes CLPool balance
        (, uint256 gcBal) = stv3.getTrackedGCBalance(trackerId, 1);
        assertEq(gcBal, MIN_STAKE + 10_000_000 ether);

        // Now WrappedKaia becomes unregistered
        vm.mockCall(
            REGISTRY_ADDRESS, abi.encodeCall(IRegistry.getActiveAddr, ("WrappedKaia")), abi.encode(address(0))
        );

        // refreshStake should NOT revert — returns 0 balance
        stv3.refreshStake(pool);

        // CLPool balance should now be 0
        (uint256 cnBal, uint256 gcBalAfter) = stv3.getTrackedGCBalance(trackerId, 1);
        assertEq(cnBal, MIN_STAKE);
        assertEq(gcBalAfter, MIN_STAKE); // CLPool balance dropped to 0
    }

    /* ========== CLRegistry array length validation ========== */

    function test_createTracker_clRegistryMismatchedArrays_reverts() public {
        // Setup a CLRegistry that returns mismatched arrays
        mockCLRegistry = makeAddr("clRegistry");
        vm.mockCall(
            REGISTRY_ADDRESS, abi.encodeCall(IRegistry.getActiveAddr, ("CLRegistry")), abi.encode(mockCLRegistry)
        );

        // Return 2 gcIds but 1 pool (mismatched)
        uint256[] memory gcIds = new uint256[](2);
        gcIds[0] = 1;
        gcIds[1] = 2;
        address[] memory pools = new address[](1);
        pools[0] = makeAddr("pool");
        address[] memory nodeIds = new address[](2);

        vm.mockCall(
            mockCLRegistry,
            abi.encodeWithSignature("getAllCLs()"),
            abi.encode(nodeIds, gcIds, pools)
        );

        vm.prank(owner);
        vm.expectRevert(IStakingTrackerV3.InvalidCLRegistry.selector);
        stv3.createTracker(block.number, block.number + 100);
    }
}
