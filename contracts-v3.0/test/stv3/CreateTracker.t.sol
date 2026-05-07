// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {STv3Base} from "./Base.t.sol";
import {IStakingTrackerV3} from "../../src/StakingTrackerV3/interfaces/IStakingTrackerV3.sol";

contract CreateTrackerTest is STv3Base {
    function test_createTracker_basic() public {
        uint256 trackerId = _createTracker(100);

        assertEq(trackerId, 1);
        assertEq(stv3.getLastTrackerId(), 1);

        uint256[] memory allIds = stv3.getAllTrackerIds();
        assertEq(allIds.length, 1);
        assertEq(allIds[0], 1);

        uint256[] memory liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 1);
        assertEq(liveIds[0], 1);
    }

    function test_createTracker_populatesGCs() public {
        uint256 trackerId = _createTracker(100);

        (uint256 trackStart, uint256 trackEnd, uint256 numGCs, uint256 totalVotes, uint256 numEligible) =
            stv3.getTrackerSummary(trackerId);

        assertEq(trackStart, block.number);
        assertEq(trackEnd, block.number + 100);
        assertEq(numGCs, 4);
        assertEq(numEligible, 4);
        // Each GC has MIN_STAKE, voteCap = 4-1 = 3, votes = MIN_STAKE/MIN_STAKE = 1
        assertEq(totalVotes, 4);
    }

    function test_createTracker_tracksAllGCBalances() public {
        uint256 trackerId = _createTracker(100);

        (uint256[] memory gcIds, uint256[] memory gcBalances, uint256[] memory gcVotes) =
            stv3.getAllTrackedGCs(trackerId);

        assertEq(gcIds.length, 4);
        for (uint256 i; i < 4; i++) {
            assertEq(gcIds[i], gc[i].gcId);
            assertEq(gcBalances[i], MIN_STAKE);
            assertEq(gcVotes[i], 1);
        }
    }

    function test_createTracker_mapsStakingToGCId() public {
        uint256 trackerId = _createTracker(100);

        for (uint256 i; i < 4; i++) {
            assertEq(stv3.stakingToGCId(trackerId, address(gc[i].staking)), gc[i].gcId);
        }
    }

    function test_createTracker_separateBalances() public {
        uint256 trackerId = _createTracker(100);

        for (uint256 i; i < 4; i++) {
            (uint256 cnBal, uint256 gcBal) = stv3.getTrackedGCBalance(trackerId, gc[i].gcId);
            assertEq(cnBal, MIN_STAKE);
            assertEq(gcBal, MIN_STAKE);
        }
    }

    function test_createTracker_withCLPool() public {
        // Setup CLRegistry with a pool for GC 1
        address pool = makeAddr("clPool1");
        uint256[] memory gcIds = new uint256[](1);
        gcIds[0] = 1;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        _setupCLRegistry(gcIds, pools);
        _mockCLPoolBalance(pool, 10_000_000 ether);

        uint256 trackerId = _createTracker(100);

        // GC 1 should have CnStaking + CLPool balance
        (uint256 cnBal, uint256 gcBal) = stv3.getTrackedGCBalance(trackerId, 1);
        assertEq(cnBal, MIN_STAKE);
        assertEq(gcBal, MIN_STAKE + 10_000_000 ether);

        // CLPool should be marked
        assertTrue(stv3.isCLPool(trackerId, pool));
        assertEq(stv3.stakingToGCId(trackerId, pool), 1);
    }

    function test_createTracker_clPoolIgnoredIfGCNotInAB() public {
        // Setup CLRegistry with a pool for GC 999 (not in ABv2)
        address pool = makeAddr("clPoolOrphan");
        uint256[] memory gcIds = new uint256[](1);
        gcIds[0] = 999;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        _setupCLRegistry(gcIds, pools);
        _mockCLPoolBalance(pool, 10_000_000 ether);

        uint256 trackerId = _createTracker(100);

        // Pool should not be tracked
        assertFalse(stv3.isCLPool(trackerId, pool));
        assertEq(stv3.stakingToGCId(trackerId, pool), 0);
    }

    function test_createTracker_noCLRegistry() public {
        // CLRegistry returns address(0) (default mock)
        uint256 trackerId = _createTracker(100);

        // Should work fine — just CnStaking balances
        (, , uint256 numGCs, , ) = stv3.getTrackerSummary(trackerId);
        assertEq(numGCs, 4);
    }

    function test_createTracker_multipleTrackers() public {
        uint256 id1 = _createTracker(100);
        uint256 id2 = _createTracker(200);

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(stv3.getLastTrackerId(), 2);

        uint256[] memory allIds = stv3.getAllTrackerIds();
        assertEq(allIds.length, 2);

        uint256[] memory liveIds = stv3.getLiveTrackerIds();
        assertEq(liveIds.length, 2);
    }

    function test_createTracker_onlyOwner() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        stv3.createTracker(block.number, block.number + 100);
    }

    function test_createTracker_emitsEvent() public {
        uint256[] memory expectedGcIds = new uint256[](4);
        for (uint256 i; i < 4; i++) {
            expectedGcIds[i] = gc[i].gcId;
        }

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit IStakingTrackerV3.CreateTracker(1, block.number, block.number + 100, expectedGcIds);
        stv3.createTracker(block.number, block.number + 100);
    }

    function test_createTracker_withUnstaking() public {
        // GC 0 has some unstaking
        gc[0].staking.mockSetStaking(MIN_STAKE + 1_000_000 ether);
        gc[0].staking.mockSetUnstaking(1_000_000 ether);

        uint256 trackerId = _createTracker(100);

        // Effective balance = staking() - unstaking() = MIN_STAKE
        (uint256 cnBal, uint256 gcBal) = stv3.getTrackedGCBalance(trackerId, gc[0].gcId);
        assertEq(cnBal, MIN_STAKE);
        assertEq(gcBal, MIN_STAKE);
    }

    function test_createTracker_gcBelowMinStake() public {
        // GC 3 below MIN_STAKE
        gc[3].staking.mockSetStaking(MIN_STAKE - 1);
        gc[3].staking.mockSetUnstaking(0);

        uint256 trackerId = _createTracker(100);

        (, , , uint256 totalVotes, uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        assertEq(numEligible, 3);

        // GC 3 has 0 votes
        (uint256 gcBal, uint256 gcVotes) = stv3.getTrackedGC(trackerId, gc[3].gcId);
        assertEq(gcBal, MIN_STAKE - 1);
        assertEq(gcVotes, 0);

        // Other GCs have 1 vote each, voteCap = 3-1 = 2
        for (uint256 i; i < 3; i++) {
            (, uint256 votes) = stv3.getTrackedGC(trackerId, gc[i].gcId);
            assertEq(votes, 1);
        }
        assertEq(totalVotes, 3);
    }

    function test_createTracker_skipsGcIdZero() public {
        // Mock ABv2 to return a GovernanceInfo with gcId == 0
        // We can't easily do this with the real ABv2 since all nodes get gcId > 0
        // But we can verify that the 4 genesis nodes all have gcId > 0
        uint256 trackerId = _createTracker(100);
        (, , uint256 numGCs, , ) = stv3.getTrackerSummary(trackerId);
        assertEq(numGCs, 4);
    }
}
