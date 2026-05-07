// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {AddressBookV2Harness} from "../base/AddressBookV2Harness.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IRegistry} from "../../src/system/IRegistry.sol";
import {SystemCallable} from "../../src/system/SystemCallable.sol";
import {State, NodeInfo} from "../../src/types/Node.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SystemTransitionsTest is Base {
    /* ========== Happy path: single transition ========== */

    function test_processSystemTransition_single() public {
        _setupGenesisCommittee(); // 4 ValActive

        _doSingleTransition(genesis[0].nodeId, State.ValPaused, block.timestamp + DEFAULT_PAUSE_TIMEOUT);

        _assertNodeState(genesis[0].nodeId, State.ValPaused);
        NodeInfo memory info = abv2.getNodeInfo(genesis[0].nodeId);
        assertEq(info.timeoutAt, block.timestamp + DEFAULT_PAUSE_TIMEOUT);
    }

    /* ========== Happy path: batch transition ========== */

    function test_processSystemTransition_batch() public {
        _setupGenesisCommittee(); // 4 ValActive

        address[] memory ids = new address[](2);
        State[] memory states = new State[](2);
        uint256[] memory timeouts = new uint256[](2);
        ids[0] = genesis[0].nodeId;
        states[0] = State.ValPaused;
        timeouts[0] = block.timestamp + DEFAULT_PAUSE_TIMEOUT;
        ids[1] = genesis[1].nodeId;
        states[1] = State.ValExiting;
        timeouts[1] = 0;

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        _assertNodeState(genesis[0].nodeId, State.ValPaused);
        _assertNodeState(genesis[1].nodeId, State.ValExiting);
    }

    /* ========== Empty arrays ========== */

    function test_processSystemTransition_emptyArrays() public {
        _setupGenesisCommittee();

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(new address[](0), new State[](0), new uint256[](0), 0);

        // All nodes unchanged
        for (uint256 i = 0; i < 4; i++) {
            _assertNodeState(genesis[i].nodeId, State.ValActive);
        }
    }

    /* ========== epochVACount: updated at epoch block ========== */

    function test_processSystemTransition_epochVACount_atEpochBlock() public {
        _setupGenesisCommittee(); // epochVACount = 4

        // Pause one: VA→VP
        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[0].nodeId;
        states[0] = State.ValPaused;
        timeouts[0] = block.timestamp + DEFAULT_PAUSE_TIMEOUT;

        _rollToNextEpoch();

        // Expect EpochTransitionProcessed with epochVACount = VA(3) only
        vm.expectEmit(false, false, false, true);
        emit IAddressBookV2.EpochTransitionProcessed(3);

        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 3);

        // epochVACount = VA only = 3 (ValPaused excluded)
        assertEq(abv2.getEpochVACount(), 3, "epochVACount = VA only");
    }

    function test_processSystemTransition_epochVACount_notUpdatedAtNonEpochBlock() public {
        _setupGenesisCommittee(); // epochVACount = 4

        // Exit one at a non-epoch block
        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[0].nodeId;
        states[0] = State.ValExiting;
        timeouts[0] = 0;

        vm.roll(block.number + 1); // Non-epoch block
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        // epochVACount should NOT be updated (still 4 from genesis setup)
        assertEq(abv2.getEpochVACount(), 4, "epochVACount should not update at non-epoch block");

        // But the actual state counts have changed
        assertEq(abv2.getStateCount(State.ValActive), 3);
        assertEq(abv2.getStateCount(State.ValExiting), 1);
    }

    function test_processSystemTransition_epochVACount_decreasesWhenExitingProcessed() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Exit genesis[3]: VA→VE
        _exitVal(genesis[3]);

        // Epoch: VE → Registered
        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[3].nodeId;
        states[0] = State.Registered;
        timeouts[0] = 0;

        _rollToNextEpoch();

        // Expect EpochTransitionProcessed with epochVACount = VA(3)
        vm.expectEmit(false, false, false, true);
        emit IAddressBookV2.EpochTransitionProcessed(3);

        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 3);

        // epochVACount = VA(3)
        assertEq(abv2.getEpochVACount(), 3, "epochVACount decreases after exit processed");
    }

    /* ========== Event emission ========== */

    function test_processSystemTransition_emitsEvent() public {
        _setupGenesisCommittee();

        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[0].nodeId;
        states[0] = State.ValPaused;
        timeouts[0] = block.timestamp + DEFAULT_PAUSE_TIMEOUT;

        _rollToNextEpoch();

        // At epoch block: both EpochTransitionProcessed and SystemTransitionProcessed emitted
        vm.expectEmit(false, false, false, true);
        emit IAddressBookV2.EpochTransitionProcessed(3); // VA only = 3

        vm.expectEmit(false, false, false, true);
        emit IAddressBookV2.SystemTransitionProcessed(ids, states);

        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 3);
    }

    function test_processSystemTransition_emitsEvent_emptyArrays() public {
        _setupGenesisCommittee();

        _rollToNextEpoch();

        // At epoch block: EpochTransitionProcessed emitted even with empty arrays
        vm.expectEmit(false, false, false, true);
        emit IAddressBookV2.EpochTransitionProcessed(4); // VA(4) = 4

        vm.expectEmit(false, false, false, true);
        emit IAddressBookV2.SystemTransitionProcessed(new address[](0), new State[](0));

        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(new address[](0), new State[](0), new uint256[](0), 4);
    }

    /* ========== Input validation ========== */

    function test_processSystemTransition_revert_InvalidInput_lengthMismatch_states() public {
        _setupGenesisCommittee();

        address[] memory ids = new address[](1);
        ids[0] = genesis[0].nodeId;

        _rollToNextEpoch();
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, new State[](0), new uint256[](1), 0);
    }

    function test_processSystemTransition_revert_InvalidInput_lengthMismatch_timeouts() public {
        _setupGenesisCommittee();

        address[] memory ids = new address[](1);
        ids[0] = genesis[0].nodeId;
        State[] memory states = new State[](1);
        states[0] = State.ValPaused;

        _rollToNextEpoch();
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, new uint256[](0), 0);
    }

    /* ========== Access control ========== */

    function test_processSystemTransition_revert_OnlySystemTx() public {
        _rollToNextEpoch();
        vm.expectRevert(SystemCallable.OnlySystemTx.selector);
        abv2.processSystemTransition(new address[](0), new State[](0), new uint256[](0), 0);
    }

    /* ========== Trust boundary: nonexistent nodeId ========== */

    function test_processSystemTransition_trustBoundary_nonexistentNodeId_silentlySkipped() public {
        _setupGenesisCommittee(); // 4 ValActive

        address phantom = makeAddr("phantom");

        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = phantom;
        states[0] = State.ValActive;
        timeouts[0] = 0;

        // Should not revert — ABv2._transition returns early on oldState == Unknown
        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        // phantom still Unknown (no state change occurred)
        assertEq(uint256(abv2.getNodeState(phantom)), uint256(State.Unknown));

        // State counts unchanged: still 4 ValActive
        assertEq(abv2.getStateCount(State.ValActive), 4);
        assertEq(abv2.getStateCount(State.Unknown), 0, "Unknown stateCount should remain 0");
    }

    /* ========== Trust boundary: duplicate nodeId ========== */

    function test_processSystemTransition_trustBoundary_duplicateNodeId_appliedTwice() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Pass genesis[3] twice: first VA→VI, then VI→Registered
        address[] memory ids = new address[](2);
        State[] memory states = new State[](2);
        uint256[] memory timeouts = new uint256[](2);
        ids[0] = genesis[3].nodeId;
        states[0] = State.ValInactive;
        timeouts[0] = block.timestamp + DEFAULT_IDLE_TIMEOUT;
        ids[1] = genesis[3].nodeId;
        states[1] = State.Registered;
        timeouts[1] = 0;

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        // Node ended up in Registered after both transitions applied sequentially
        _assertNodeState(genesis[3].nodeId, State.Registered);
        _assertRegistered(genesis[3].nodeId, true);
    }

    /* ========== _transition: newState == Unknown → no-op ========== */

    function test_processSystemTransition_targetUnknown_isNoOp() public {
        _setupGenesisCommittee(); // 4 ValActive

        uint256 prevActive = abv2.getStateCount(State.ValActive);
        uint256 prevUnknown = abv2.getStateCount(State.Unknown);

        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[0].nodeId;
        states[0] = State.Unknown;

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        _assertNodeState(genesis[0].nodeId, State.ValActive);
        assertEq(abv2.getStateCount(State.ValActive), prevActive, "ValActive count unchanged");
        assertEq(abv2.getStateCount(State.Unknown), prevUnknown, "Unknown count unchanged");
    }

    /* ========== _transition: oldState == newState → no-op ========== */

    function test_processSystemTransition_sameState_isNoOp() public {
        _setupGenesisCommittee(); // 4 ValActive

        uint256 prevActive = abv2.getStateCount(State.ValActive);

        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[0].nodeId;
        states[0] = State.ValActive;

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        _assertNodeState(genesis[0].nodeId, State.ValActive);
        assertEq(abv2.getStateCount(State.ValActive), prevActive);
    }

    /* ========== _transition: active-to-active (no set boundary crossing) ========== */

    function test_processSystemTransition_activeToActive_noSetChange() public {
        _setupGenesisCommittee(); // 4 ValActive

        uint256 prevActiveSetLen = abv2.getAllNodesLength();

        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[0].nodeId;
        states[0] = State.ValPaused;
        timeouts[0] = block.timestamp + DEFAULT_PAUSE_TIMEOUT;

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        assertEq(abv2.getAllNodesLength(), prevActiveSetLen, "allNodes length unchanged for active-to-active");
        _assertRegistered(genesis[0].nodeId, false);
    }

    /* ========== Chained transitions for same node in one batch ========== */

    function test_processSystemTransition_chainedSameNode() public {
        _setupGenesisCommittee();

        address[] memory ids = new address[](3);
        State[] memory states = new State[](3);
        uint256[] memory timeouts = new uint256[](3);
        ids[0] = genesis[0].nodeId;
        states[0] = State.ValPaused;
        timeouts[0] = block.timestamp + 100;
        ids[1] = genesis[0].nodeId;
        states[1] = State.ValInactive;
        timeouts[1] = block.timestamp + 200;
        ids[2] = genesis[0].nodeId;
        states[2] = State.Registered;

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        _assertNodeState(genesis[0].nodeId, State.Registered);
        _assertRegistered(genesis[0].nodeId, true);
        assertEq(abv2.getStateCount(State.ValActive), 3);
        assertEq(abv2.getStateCount(State.Registered), 1);
        assertEq(abv2.getStateCount(State.ValPaused), 0);
        assertEq(abv2.getStateCount(State.ValInactive), 0);
    }

    /* ========== CandTesting state via system transition ========== */

    function test_processSystemTransition_toCandTesting() public {
        _readyCand(genesis[0]); // Registered → CandReady

        _doSingleTransition(genesis[0].nodeId, State.CandTesting, 0);

        _assertNodeState(genesis[0].nodeId, State.CandTesting);
        assertEq(abv2.getStateCount(State.CandTesting), 1);
    }

    /* ========== Non-epoch block: no epochVACount update ========== */

    function test_processSystemTransition_nonEpochBlock_noEpochEvent() public {
        _setupGenesisCommittee();
        uint256 prevSlotFactor = abv2.getEpochVACount();

        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[0].nodeId;
        states[0] = State.ValPaused;
        timeouts[0] = block.timestamp + DEFAULT_PAUSE_TIMEOUT;

        vm.roll(block.number + 1);
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        assertEq(abv2.getEpochVACount(), prevSlotFactor, "epochVACount unchanged at non-epoch");
    }

    /* ========== Empty at epoch: still snapshots epochVACount ========== */

    function test_processSystemTransition_emptyAtEpoch_updatesSlotFactor() public {
        _setupGenesisCommittee(); // 4 ValActive

        _pauseVal(genesis[0]); // VA=3, VP=1

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(new address[](0), new State[](0), new uint256[](0), 3);

        assertEq(abv2.getEpochVACount(), 3, "epochVACount = VA only");
    }

    /* ========== Large batch ========== */

    function test_processSystemTransition_largeBatch_20nodes() public {
        vm.prank(owner);
        abv2.updateMaxNodeCount(200);
        vm.prank(owner);
        abv2.updateMaxCandReadyCount(200);

        NodeBundle[] memory nodes = new NodeBundle[](20);
        for (uint256 i = 0; i < 20; i++) {
            nodes[i] = _createNode(i + 5);
            _readyCand(nodes[i]);
        }

        address[] memory ids = new address[](20);
        State[] memory states = new State[](20);
        uint256[] memory timeouts = new uint256[](20);
        for (uint256 i = 0; i < 20; i++) {
            ids[i] = nodes[i].nodeId;
            states[i] = State.ValActive;
        }

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        assertEq(abv2.getStateCount(State.ValActive), 20);
        assertEq(abv2.getStateCount(State.CandReady), 0);
    }

    /* ========== Timeout passthrough ========== */

    function test_processSystemTransition_timeoutPassthrough() public {
        _setupGenesisCommittee(); // 4 ValActive

        uint256 customTimeout = block.timestamp + 12345;

        _doSingleTransition(genesis[0].nodeId, State.ValPaused, customTimeout);

        NodeInfo memory info = abv2.getNodeInfo(genesis[0].nodeId);
        assertEq(info.timeoutAt, customTimeout, "timeout should be passed through exactly");
    }
}
