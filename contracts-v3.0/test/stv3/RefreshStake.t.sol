// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {STv3Base} from "./Base.t.sol";
import {IStakingTrackerV3} from "../../src/StakingTrackerV3/interfaces/IStakingTrackerV3.sol";

contract RefreshStakeTest is STv3Base {
    uint256 internal trackerId;

    function setUp() public override {
        super.setUp();
        trackerId = _createTracker(100);
    }

    function test_refreshStake_updatesBalance() public {
        // Increase GC 0's staking
        gc[0].staking.mockSetStaking(MIN_STAKE * 2);

        stv3.refreshStake(address(gc[0].staking));

        (uint256 cnBal, uint256 gcBal) = stv3.getTrackedGCBalance(trackerId, gc[0].gcId);
        assertEq(cnBal, MIN_STAKE * 2);
        assertEq(gcBal, MIN_STAKE * 2);
    }

    function test_refreshStake_updatesVotes() public {
        // Give GC 0 more stake → more votes
        gc[0].staking.mockSetStaking(MIN_STAKE * 3);

        stv3.refreshStake(address(gc[0].staking));

        (, uint256 gcVotes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        // voteCap = 4-1 = 3, votes = 3*MIN/MIN = 3, capped at 3
        assertEq(gcVotes, 3);
    }

    function test_refreshStake_emitsEvent() public {
        gc[0].staking.mockSetStaking(MIN_STAKE * 2);

        vm.expectEmit(true, true, false, true);
        emit IStakingTrackerV3.RefreshStake(
            trackerId, gc[0].gcId, address(gc[0].staking), MIN_STAKE * 2, MIN_STAKE * 2, 2, 5
        );
        stv3.refreshStake(address(gc[0].staking));
    }

    function test_refreshStake_crossingEligibilityThreshold() public {
        // Drop GC 0 below MIN_STAKE → triggers full recalc
        gc[0].staking.mockSetStaking(MIN_STAKE - 1);

        stv3.refreshStake(address(gc[0].staking));

        (, , , uint256 totalVotes, uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        assertEq(numEligible, 3);

        // GC 0 has 0 votes
        (, uint256 gc0Votes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        assertEq(gc0Votes, 0);

        // Remaining GCs: voteCap = 3-1 = 2
        for (uint256 i = 1; i < 4; i++) {
            (, uint256 votes) = stv3.getTrackedGC(trackerId, gc[i].gcId);
            assertEq(votes, 1);
        }
        assertEq(totalVotes, 3);
    }

    function test_refreshStake_regainEligibility() public {
        // Drop then restore GC 0
        gc[0].staking.mockSetStaking(MIN_STAKE - 1);
        stv3.refreshStake(address(gc[0].staking));

        gc[0].staking.mockSetStaking(MIN_STAKE);
        stv3.refreshStake(address(gc[0].staking));

        (, , , uint256 totalVotes, uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        assertEq(numEligible, 4);
        assertEq(totalVotes, 4);
    }

    function test_refreshStake_unknownStaking() public {
        // Address not in any tracker — should not revert, just no-op
        stv3.refreshStake(makeAddr("unknownStaking"));

        // Nothing changed
        (, , , uint256 totalVotes, ) = stv3.getTrackerSummary(trackerId);
        assertEq(totalVotes, 4);
    }

    function test_refreshStake_addressZero() public {
        // Voting contract calls refreshStake(address(0)) to clean up expired trackers
        stv3.refreshStake(address(0));

        // Tracker still live
        uint256[] memory liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 1);
    }

    function test_refreshStake_clPoolBalance() public {
        // Setup CLPool for GC 1
        address pool = makeAddr("clPool1");
        uint256[] memory gcIds = new uint256[](1);
        gcIds[0] = 1;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        _setupCLRegistry(gcIds, pools);
        _mockCLPoolBalance(pool, 10_000_000 ether);

        // Re-create tracker with CLPool
        vm.prank(owner);
        uint256 tid = stv3.createTracker(block.number, block.number + 200);

        // Verify initial state
        (uint256 cnBal, uint256 gcBal) = stv3.getTrackedGCBalance(tid, 1);
        assertEq(cnBal, MIN_STAKE);
        assertEq(gcBal, MIN_STAKE + 10_000_000 ether);

        // Update CLPool balance
        _mockCLPoolBalance(pool, 20_000_000 ether);
        stv3.refreshStake(pool);

        (cnBal, gcBal) = stv3.getTrackedGCBalance(tid, 1);
        assertEq(cnBal, MIN_STAKE); // CnStaking unchanged
        assertEq(gcBal, MIN_STAKE + 20_000_000 ether);
    }

    function test_refreshStake_clPoolDoesNotAffectEligibility() public {
        // CLPool balance changes don't trigger full vote recalc
        address pool = makeAddr("clPool1");
        uint256[] memory gcIds = new uint256[](1);
        gcIds[0] = 1;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        _setupCLRegistry(gcIds, pools);
        _mockCLPoolBalance(pool, 0);

        vm.prank(owner);
        uint256 tid = stv3.createTracker(block.number, block.number + 200);

        // Set CLPool to zero then back — should not affect numEligible
        _mockCLPoolBalance(pool, 0);
        stv3.refreshStake(pool);

        (, , , , uint256 numEligible) = stv3.getTrackerSummary(tid);
        assertEq(numEligible, 4);
    }

    function test_refreshStake_multipleTrackers() public {
        vm.prank(owner);
        uint256 tid2 = stv3.createTracker(block.number, block.number + 200);

        gc[0].staking.mockSetStaking(MIN_STAKE * 2);
        stv3.refreshStake(address(gc[0].staking));

        // Both trackers should be updated
        (uint256 cnBal1, ) = stv3.getTrackedGCBalance(trackerId, gc[0].gcId);
        (uint256 cnBal2, ) = stv3.getTrackedGCBalance(tid2, gc[0].gcId);
        assertEq(cnBal1, MIN_STAKE * 2);
        assertEq(cnBal2, MIN_STAKE * 2);
    }

    function test_refreshStake_voteCapApplied() public {
        // Give GC 0 massive stake
        gc[0].staking.mockSetStaking(MIN_STAKE * 100);

        stv3.refreshStake(address(gc[0].staking));

        (, uint256 gcVotes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        // voteCap = 4-1 = 3, votes = 100, capped at 3
        assertEq(gcVotes, 3);
    }
}
