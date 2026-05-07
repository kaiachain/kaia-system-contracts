// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {STv3Base} from "./Base.t.sol";
import {IStakingTrackerV3} from "../../src/StakingTrackerV3/interfaces/IStakingTrackerV3.sol";

contract TrackerLifecycleTest is STv3Base {
    function test_trackerRetires_onRefreshStake() public {
        uint256 trackerId = _createTracker(10);

        // Advance past trackEnd
        vm.roll(block.number + 11);

        // refreshStake should retire the expired tracker
        vm.expectEmit(true, false, false, false);
        emit IStakingTrackerV3.RetireTracker(trackerId);
        stv3.refreshStake(address(0));

        uint256[] memory liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 0);

        // allTrackerIds should still contain it
        uint256[] memory allIds = stv3.getAllTrackerIds();
        assertEq(allIds.length, 1);
        assertEq(allIds[0], trackerId);
    }

    function test_trackerRetires_multipleExpired() public {
        uint256 tid1 = _createTracker(10);
        uint256 tid2 = _createTracker(20);

        // Advance past both
        vm.roll(block.number + 21);

        stv3.refreshStake(address(0));

        uint256[] memory liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 0);

        // Both should have been retired
        uint256[] memory allIds = stv3.getAllTrackerIds();
        assertEq(allIds.length, 2);
    }

    function test_trackerRetires_partialExpiry() public {
        uint256 tid1 = _createTracker(10);
        uint256 tid2 = _createTracker(20);

        // Advance past first but not second
        vm.roll(block.number + 11);

        stv3.refreshStake(address(0));

        uint256[] memory liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 1);
        assertEq(liveIds[0], tid2);
    }

    function test_trackerLive_boundaryConditions() public {
        uint256 startBlock = block.number;
        _createTracker(10);

        // At trackStart — should be live
        uint256[] memory liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 1);

        // At trackEnd - 1 — should still be live
        vm.roll(startBlock + 9);
        stv3.refreshStake(address(0));
        liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 1);

        // At trackEnd — should be retired
        vm.roll(startBlock + 10);
        stv3.refreshStake(address(0));
        liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 0);
    }

    function test_updateAfterRetire_noOp() public {
        uint256 trackerId = _createTracker(10);

        // Advance and retire
        vm.roll(block.number + 11);
        stv3.refreshStake(address(0));

        // Change staking
        gc[0].staking.mockSetStaking(MIN_STAKE * 2);

        // refreshStake should not revert even though tracker is retired
        stv3.refreshStake(address(gc[0].staking));

        // Tracker data should remain unchanged (from creation time)
        (uint256 cnBal, ) = stv3.getTrackedGCBalance(trackerId, gc[0].gcId);
        assertEq(cnBal, MIN_STAKE); // Still original value
    }

    function test_swapAndPop_preservesOrder() public {
        // Create 3 trackers with different end blocks
        _createTracker(10);
        uint256 tid2 = _createTracker(20);
        uint256 tid3 = _createTracker(30);

        assertEq(stv3.getLiveTrackerIds().length, 3);

        // Expire first tracker
        vm.roll(block.number + 11);
        stv3.refreshStake(address(0));

        uint256[] memory liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 2);
        // After swap-and-pop: [tid1, tid2, tid3] → [tid3, tid2] (tid3 swapped into tid1's position)
        assertEq(liveIds[0], tid3);
        assertEq(liveIds[1], tid2);
    }
}
