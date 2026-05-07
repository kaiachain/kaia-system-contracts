// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {State, NodeInfo} from "../../src/types/Node.sol";

contract EpochTransitionTest is Base {
    /* ========== Validator demotion via processSystemTransition ========== */

    function test_epochTransition_valDemotion() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Diff: only genesis[3] changes (ValActive → ValInactive)
        _doSingleTransition(genesis[3].nodeId, State.ValInactive, block.timestamp + DEFAULT_IDLE_TIMEOUT);

        // Verify states
        _assertNodeState(genesis[3].nodeId, State.ValInactive);
        for (uint256 i = 0; i < 3; i++) {
            _assertNodeState(genesis[i].nodeId, State.ValActive);
        }
    }

    /* ========== Idle timeout: newly entering idle ========== */

    function test_idleTimeout_newlyEnteringIdle() public {
        _setupGenesisCommittee();

        // Diff: genesis[3] ValActive → ValInactive with idle timeout
        _doSingleTransition(genesis[3].nodeId, State.ValInactive, block.timestamp + DEFAULT_IDLE_TIMEOUT);

        NodeInfo memory info = abv2.getNodeInfo(genesis[3].nodeId);
        assertEq(info.timeoutAt, block.timestamp + DEFAULT_IDLE_TIMEOUT);
    }

    /* ========== ValActive clears timeout ========== */

    function test_valActive_clearsTimeout() public {
        _setupGenesisCommittee();

        // Pause genesis[0] → sets pause timeout
        _pauseVal(genesis[0]);
        assertTrue(abv2.getNodeInfo(genesis[0].nodeId).timeoutAt > 0);

        // Epoch: only genesis[0] changed (ValPaused → ValActive, timeout cleared)
        _doSingleTransition(genesis[0].nodeId, State.ValActive, 0);

        NodeInfo memory info = abv2.getNodeInfo(genesis[0].nodeId);
        assertEq(info.timeoutAt, 0, "ValActive should clear timeout");
    }

    /* ========== ValPaused keeps existing timeout (no diff needed) ========== */

    function test_valPaused_keepsTimeout() public {
        _setupGenesisCommittee();

        // Pause genesis[0] → sets pause timeout
        _pauseVal(genesis[0]);
        uint256 pauseTimeout = abv2.getNodeInfo(genesis[0].nodeId).timeoutAt;
        assertTrue(pauseTimeout > 0);

        // Epoch: no diff (empty system transition) — genesis[0] stays ValPaused
        _doEpochTransition(new address[](0), new State[](0));

        NodeInfo memory info = abv2.getNodeInfo(genesis[0].nodeId);
        assertEq(info.timeoutAt, pauseTimeout, "ValPaused should keep existing timeout");
    }

    /* ========== ValExiting removal via epoch ========== */

    function test_epochTransition_valExitingToRegistered() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Exit genesis[3]: ValActive → ValExiting
        _exitVal(genesis[3]);
        _assertNodeState(genesis[3].nodeId, State.ValExiting);

        // Epoch: genesis[3] exits (ValExiting → Registered)
        _doSingleTransition(genesis[3].nodeId, State.Registered, 0);

        _assertNodeState(genesis[3].nodeId, State.Registered);
        _assertRegistered(genesis[3].nodeId, true);
    }

    function test_epochTransition_valExitingToRegistered_clearsTimeout() public {
        _setupGenesisCommittee();

        // Pause genesis[3] (sets pause timeout), then exit (should clear timeout)
        _pauseVal(genesis[3]);
        assertTrue(abv2.getNodeInfo(genesis[3].nodeId).timeoutAt > 0);

        _exitVal(genesis[3]); // ValPaused → ValExiting, timeout cleared
        assertEq(abv2.getNodeInfo(genesis[3].nodeId).timeoutAt, 0, "exit should clear timeout");

        // Epoch: ValExiting → Registered
        _doSingleTransition(genesis[3].nodeId, State.Registered, 0);

        assertEq(abv2.getNodeInfo(genesis[3].nodeId).timeoutAt, 0);
    }

    /* ========== Candidate transitions ========== */

    function test_epochTransition_candReadyToCandTesting() public {
        _setupGenesisCommittee();
        NodeBundle memory n5 = _createNode(5);
        _readyCand(n5); // CandReady

        // Epoch: n5 → CandTesting
        _doSingleTransition(n5.nodeId, State.CandTesting, 0);

        _assertNodeState(n5.nodeId, State.CandTesting);
        assertTrue(abv2.getNodeState(n5.nodeId) != State.Registered);
    }

    function test_epochTransition_demotedCandidates() public {
        _setupGenesisCommittee();
        NodeBundle memory n5 = _createNode(5);

        // Activate n5 -> CandReady
        _readyCand(n5);
        _assertNodeState(n5.nodeId, State.CandReady);

        // Epoch: move n5 to CandTesting
        _doSingleTransition(n5.nodeId, State.CandTesting, 0);
        _assertNodeState(n5.nodeId, State.CandTesting);

        // Epoch 2: n5 fails testing -> back to Registered
        _doSingleTransition(n5.nodeId, State.Registered, 0);

        _assertRegistered(n5.nodeId, true);
        _assertNodeState(n5.nodeId, State.Registered);
    }

    /* ========== Multiple validators exit across epochs ========== */

    function test_epochTransition_multipleValidatorsToCandidate() public {
        _setupGenesisCommittee(); // 4 ValActive
        NodeBundle memory n5 = _createNode(5);
        _readyCand(n5);
        _doSingleTransition(n5.nodeId, State.ValActive, 0); // 5 VA, SF=5

        // Exit genesis[3]: ValActive → ValExiting (maxSlot(5)=1)
        _exitVal(genesis[3]);

        // Epoch 1: genesis[3] ValExiting → Registered (SF=4)
        _doSingleTransition(genesis[3].nodeId, State.Registered, 0);
        _assertRegistered(genesis[3].nodeId, true);

        // Exit genesis[2]: slot free again (SF=4, maxSlot(4)=1, VA=4, minActive(4)=3)
        _exitVal(genesis[2]);

        // Epoch 2: genesis[2] ValExiting → Registered
        _doSingleTransition(genesis[2].nodeId, State.Registered, 0);

        _assertRegistered(genesis[2].nodeId, true);
        _assertRegistered(genesis[3].nodeId, true);
    }

    /* ========== epochVACount assertions ========== */

    function test_epochVACount_setCorrectlyAfterGenesisEpoch() public {
        _setupGenesisCommittee(); // 4 ValActive via epoch

        // epochVACount = VA = 4
        assertEq(abv2.getEpochVACount(), 4, "epochVACount should be 4 after genesis committee");
    }

    function test_epochVACount_updatedAfterPauseAndEpoch() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Pause one: VA=3, VP=1
        _pauseVal(genesis[0]);

        // Epoch with no diff → epochVACount = VA only = 3
        _rollToNextEpoch();

        vm.expectEmit(false, false, false, true);
        emit IAddressBookV2.EpochTransitionProcessed(3);

        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(new address[](0), new State[](0), new uint256[](0), 3);

        // epochVACount = VA only = 3
        assertEq(abv2.getEpochVACount(), 3, "epochVACount = VA only");
    }

    /// @notice Documents new behavior from kaia#860: n<4 → maxSlot=0 → all exits and pauses blocked
    function test_epochVACount_lessThan4_blocksAllExitsAndPauses() public {
        _setupGenesisCommittee(); // 4 VA, SF=4

        // Exit genesis[3]: uses 1 slot (maxSlot(4)=1)
        _exitVal(genesis[3]);

        // Epoch: genesis[3] → Registered, SF=3 (3 VA remaining)
        _doSingleTransition(genesis[3].nodeId, State.Registered, 0);
        assertEq(abv2.getEpochVACount(), 3, "SF=3 after one validator exits");

        // maxSlot(3)=0 (n<4) → no exit or pause allowed
        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _exitVal(genesis[0]);

        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _pauseVal(genesis[0]);
    }

    /* ========== EpochTransitionProcessed event ========== */

    function test_epochTransition_emitsEpochTransitionProcessed() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Exit genesis[3], then process at epoch
        _exitVal(genesis[3]);

        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[3].nodeId;
        states[0] = State.Registered;

        _rollToNextEpoch();

        // After transition: VA(3) + VP(0) = 3
        vm.expectEmit(false, false, false, true);
        emit IAddressBookV2.EpochTransitionProcessed(3);

        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 3);

        assertEq(abv2.getEpochVACount(), 3);
    }

    function test_epochTransition_emitsEpochTransitionProcessed_emptyDiff() public {
        _setupGenesisCommittee(); // 4 ValActive

        _rollToNextEpoch();

        // Even with empty arrays, EpochTransitionProcessed is emitted at epoch block
        vm.expectEmit(false, false, false, true);
        emit IAddressBookV2.EpochTransitionProcessed(4);

        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(new address[](0), new State[](0), new uint256[](0), 4);
    }

    /* ========== Trust-boundary tests ========== */

    /// @notice Documents trust boundary: epoch diff can cross-state-boundary for candidates
    function test_epochTransition_trustBoundary_candidateDemotion_mechanicalTransition() public {
        _setupGenesisCommittee();
        NodeBundle memory n5 = _createNode(5);
        _readyCand(n5); // CandReady

        // Demote n5 via system transition
        _doSingleTransition(n5.nodeId, State.Registered, 0);

        // n5 should be Registered
        _assertNodeState(n5.nodeId, State.Registered);
        _assertRegistered(n5.nodeId, true);
    }

    /// @notice Documents trust boundary: epoch diff mechanically applies validator state changes
    ///         without isValidTransition checks — consensus client is trusted
    function test_epochTransition_trustBoundary_validatorDiff_bypassesTransitionCheck() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Epoch: directly move ValActive → ValInactive
        _doSingleTransition(genesis[3].nodeId, State.ValInactive, block.timestamp + DEFAULT_IDLE_TIMEOUT);
        _assertNodeState(genesis[3].nodeId, State.ValInactive);

        // Next epoch: ValInactive → ValActive directly (bypasses ValReady step)
        _doSingleTransition(genesis[3].nodeId, State.ValActive, 0);
        _assertNodeState(genesis[3].nodeId, State.ValActive);
    }
}
