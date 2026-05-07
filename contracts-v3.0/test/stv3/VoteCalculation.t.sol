// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {STv3Base} from "./Base.t.sol";
import {MockCnStaking} from "../../src/CnStaking/mocks/MockCnStaking.sol";

contract VoteCalculationTest is STv3Base {
    uint256 internal trackerId;

    function setUp() public override {
        super.setUp();
        trackerId = _createTracker(100);
    }

    function test_voteCap_singleEligible() public {
        // Drop 3 GCs below MIN_STAKE, leave only GC 0
        for (uint256 i = 1; i < 4; i++) {
            gc[i].staking.mockSetStaking(0);
            stv3.refreshStake(address(gc[i].staking));
        }

        (, , , uint256 totalVotes, uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        assertEq(numEligible, 1);

        // Single GC: voteCap = max(1-1, 1) = 1
        (, uint256 gcVotes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        assertEq(gcVotes, 1);
        assertEq(totalVotes, 1);
    }

    function test_voteCap_twoEligible() public {
        // Drop 2 GCs below MIN_STAKE
        for (uint256 i = 2; i < 4; i++) {
            gc[i].staking.mockSetStaking(0);
            stv3.refreshStake(address(gc[i].staking));
        }

        (, , , , uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        assertEq(numEligible, 2);

        // Each GC has MIN_STAKE, voteCap = 2-1 = 1
        for (uint256 i; i < 2; i++) {
            (, uint256 votes) = stv3.getTrackedGC(trackerId, gc[i].gcId);
            assertEq(votes, 1);
        }
    }

    function test_votePower_proportionalToBalance() public {
        // Give GC 0 triple stake
        gc[0].staking.mockSetStaking(MIN_STAKE * 3);
        stv3.refreshStake(address(gc[0].staking));

        (, uint256 gcVotes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        // votes = 3*MIN/MIN = 3, voteCap = 4-1 = 3 → 3
        assertEq(gcVotes, 3);
    }

    function test_votePower_exactlyAtMinStake() public {
        // GC at exactly MIN_STAKE
        gc[0].staking.mockSetStaking(MIN_STAKE);
        stv3.refreshStake(address(gc[0].staking));

        (, uint256 gcVotes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        assertEq(gcVotes, 1);
    }

    function test_votePower_justBelowMinStake() public {
        gc[0].staking.mockSetStaking(MIN_STAKE - 1);
        stv3.refreshStake(address(gc[0].staking));

        (, uint256 gcVotes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        assertEq(gcVotes, 0);
    }

    function test_votePower_zeroStake() public {
        gc[0].staking.mockSetStaking(0);
        stv3.refreshStake(address(gc[0].staking));

        (, uint256 gcVotes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        assertEq(gcVotes, 0);

        (, , , , uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        assertEq(numEligible, 3);
    }

    function test_votePower_clPoolAddsToVotePower() public {
        // Setup CLPool for GC 0
        address pool = makeAddr("clPool0");
        uint256[] memory gcIds = new uint256[](1);
        gcIds[0] = gc[0].gcId;
        address[] memory pools = new address[](1);
        pools[0] = pool;
        _setupCLRegistry(gcIds, pools);
        _mockCLPoolBalance(pool, MIN_STAKE * 2);

        // Create new tracker with CLPool
        vm.prank(owner);
        uint256 tid = stv3.createTracker(block.number, block.number + 200);

        // GC 0: cnBal = MIN_STAKE, gcBal = MIN_STAKE + 2*MIN_STAKE = 3*MIN_STAKE
        // votes = 3, voteCap = 3 → 3
        (, uint256 gcVotes) = stv3.getTrackedGC(tid, gc[0].gcId);
        assertEq(gcVotes, 3);
    }

    function test_votePower_allIneligible() public {
        // Drop all GCs below MIN_STAKE
        for (uint256 i; i < 4; i++) {
            gc[i].staking.mockSetStaking(0);
            stv3.refreshStake(address(gc[i].staking));
        }

        (, , , uint256 totalVotes, uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        assertEq(numEligible, 0);
        assertEq(totalVotes, 0);
    }

    function test_votePower_recalcOnEligibilityChange() public {
        // Give GC 0 massive stake (will be capped)
        gc[0].staking.mockSetStaking(MIN_STAKE * 10);
        stv3.refreshStake(address(gc[0].staking));

        // voteCap = 3, gc0 votes = 3
        (, uint256 gc0Votes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        assertEq(gc0Votes, 3);

        // Now drop GC 3 → numEligible goes from 4 to 3, voteCap = 2
        gc[3].staking.mockSetStaking(0);
        stv3.refreshStake(address(gc[3].staking));

        // gc0 should now be recapped to 2
        (, gc0Votes) = stv3.getTrackedGC(trackerId, gc[0].gcId);
        assertEq(gc0Votes, 2);

        (, , , , uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        assertEq(numEligible, 3);
    }
}
