// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {State, NodeInfo} from "../../src/types/Node.sol";

contract UserTransitionsTest is Base {
    /* ========== HELPERS ========== */

    /// @dev Sets up 3 ValActive + 1 ValInactive (genesis[3]) with idle timeout.
    function _setupWithOneIdle() internal {
        _setupGenesisCommittee(); // 4 ValActive

        // Diff: only genesis[3] changes (ValActive → ValInactive with idle timeout)
        _doSingleTransition(genesis[3].nodeId, State.ValInactive, block.timestamp + DEFAULT_IDLE_TIMEOUT);
    }

    /* ========== readyValidator ========== */

    function test_readyValidator_success() public {
        _setupWithOneIdle(); // genesis[3] = ValInactive

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.StateChanged(genesis[3].nodeId, State.ValInactive, State.ValReady);

        _readyVal(genesis[3]);
        _assertNodeState(genesis[3].nodeId, State.ValReady);
    }

    function test_readyValidator_revert_OnlyNodeId() public {
        _setupWithOneIdle();

        vm.expectRevert(IAddressBookV2.OnlyNodeId.selector);
        vm.prank(makeAddr("nonNodeId"));
        abv2.readyValidator(genesis[3].nodeId);
    }

    function test_readyValidator_revert_StakingTooLow() public {
        _setupWithOneIdle();
        genesis[3].staking.mockSetStaking(MIN_STAKE - 1);

        vm.expectRevert(IAddressBookV2.StakingTooLow.selector);
        _readyVal(genesis[3]);
    }

    function test_readyValidator_revert_InvalidState() public {
        _setupGenesisCommittee();
        // genesis[0] is ValActive, not ValInactive
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _readyVal(genesis[0]);
    }

    /* ========== unreadyValidator ========== */

    function test_unreadyValidator_success() public {
        _setupWithOneIdle();
        _readyVal(genesis[3]); // ValInactive → ValReady

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.StateChanged(genesis[3].nodeId, State.ValReady, State.ValInactive);

        _unreadyVal(genesis[3]); // ValReady → ValInactive
        _assertNodeState(genesis[3].nodeId, State.ValInactive);
    }

    function test_unreadyValidator_revert_OnlyNodeId() public {
        _setupWithOneIdle();
        _readyVal(genesis[3]);

        vm.expectRevert(IAddressBookV2.OnlyNodeId.selector);
        vm.prank(makeAddr("nonNodeId"));
        abv2.unreadyValidator(genesis[3].nodeId);
    }

    function test_unreadyValidator_revert_InvalidState() public {
        _setupWithOneIdle();
        // genesis[3] is ValInactive (not ValReady)
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _unreadyVal(genesis[3]);
    }

    /* ========== pause ========== */

    function test_pause_success() public {
        _setupGenesisCommittee();

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.StateChanged(genesis[0].nodeId, State.ValActive, State.ValPaused);

        _pauseVal(genesis[0]);
        _assertNodeState(genesis[0].nodeId, State.ValPaused);

        // Pause timeout should be set
        NodeInfo memory info = abv2.getNodeInfo(genesis[0].nodeId);
        assertEq(info.timeoutAt, block.timestamp + DEFAULT_PAUSE_TIMEOUT);
    }

    function test_pause_revert_OnlyNodeId() public {
        _setupGenesisCommittee();

        vm.expectRevert(IAddressBookV2.OnlyNodeId.selector);
        vm.prank(makeAddr("nonNodeId"));
        abv2.pause(genesis[0].nodeId);
    }

    function test_pause_revert_SlotsFull() public {
        _setupGenesisCommittee(); // N=4, F=1, maxPaused=1
        _pauseVal(genesis[0]); // 1/1 used

        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _pauseVal(genesis[1]);
    }

    function test_pause_revert_InvalidState() public {
        _setupWithOneIdle();
        // genesis[3] is ValInactive, not ValActive
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _pauseVal(genesis[3]);
    }

    /* ========== resume ========== */

    function test_resume_success() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]);

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.StateChanged(genesis[0].nodeId, State.ValPaused, State.ValActive);

        _resumeVal(genesis[0]);
        _assertNodeState(genesis[0].nodeId, State.ValActive);

        // Timeout should be cleared
        NodeInfo memory info = abv2.getNodeInfo(genesis[0].nodeId);
        assertEq(info.timeoutAt, 0);
    }

    function test_resume_revert_OnlyNodeId() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]);

        vm.expectRevert(IAddressBookV2.OnlyNodeId.selector);
        vm.prank(makeAddr("nonNodeId"));
        abv2.resume(genesis[0].nodeId);
    }

    function test_resume_revert_InvalidState() public {
        _setupGenesisCommittee();
        // genesis[0] is ValActive, not ValPaused
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _resumeVal(genesis[0]);
    }

    function test_resume_revert_TimeoutExpired() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]); // ValActive → ValPaused (timeout = now + pauseTimeout)

        // Advance time past the pause timeout
        vm.warp(block.timestamp + DEFAULT_PAUSE_TIMEOUT);

        // Resume should fail: timeout has expired, system transition pending
        vm.expectRevert(IAddressBookV2.TimeoutExpired.selector);
        _resumeVal(genesis[0]);
    }

    function test_resume_success_beforeTimeout() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]);

        // Advance time to just before the timeout
        vm.warp(block.timestamp + DEFAULT_PAUSE_TIMEOUT - 1);

        // Resume should succeed: timeout has not expired yet
        _resumeVal(genesis[0]);
        _assertNodeState(genesis[0].nodeId, State.ValActive);
    }

    /* ========== exit ========== */

    function test_exit_success_fromValActive() public {
        _setupGenesisCommittee();

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.StateChanged(genesis[0].nodeId, State.ValActive, State.ValExiting);

        _exitVal(genesis[0]);
        _assertNodeState(genesis[0].nodeId, State.ValExiting);
    }

    function test_exit_success_fromValPaused() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]); // ValActive → ValPaused (timeout set)

        _exitVal(genesis[0]); // ValPaused → ValExiting
        _assertNodeState(genesis[0].nodeId, State.ValExiting);

        // Timeout should be cleared (was set during pause)
        NodeInfo memory info = abv2.getNodeInfo(genesis[0].nodeId);
        assertEq(info.timeoutAt, 0);
    }

    function test_exit_revert_TimeoutExpired_fromValPaused() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]); // ValActive → ValPaused

        // Advance time past the pause timeout
        vm.warp(block.timestamp + DEFAULT_PAUSE_TIMEOUT);

        // Exit should fail: timeout expired, system transition takes precedence
        vm.expectRevert(IAddressBookV2.TimeoutExpired.selector);
        _exitVal(genesis[0]);
    }

    function test_exit_success_fromValPaused_beforeTimeout() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]);

        // Advance time to just before the timeout
        vm.warp(block.timestamp + DEFAULT_PAUSE_TIMEOUT - 1);

        // Exit should succeed: timeout has not expired yet
        _exitVal(genesis[0]);
        _assertNodeState(genesis[0].nodeId, State.ValExiting);
    }

    function test_exit_revert_OnlyNodeId() public {
        _setupGenesisCommittee();

        vm.expectRevert(IAddressBookV2.OnlyNodeId.selector);
        vm.prank(makeAddr("nonNodeId"));
        abv2.exit(genesis[0].nodeId);
    }

    function test_exit_revert_SlotsFull() public {
        _setupGenesisCommittee(); // N=4, F=1, maxExiting=1
        _exitVal(genesis[0]); // 1/1 used

        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _exitVal(genesis[1]);
    }

    function test_exit_revert_SlotsFull_minActive() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Epoch: move 2 nodes to ValPaused, leaving 2 ValActive
        // epochVACount = VA(2) = 2 (VP excluded), maxSlot(2)=0 (n<4) → blocks any exit
        address[] memory changedIds = new address[](2);
        State[] memory changedStates = new State[](2);
        changedIds[0] = genesis[2].nodeId;
        changedIds[1] = genesis[3].nodeId;
        changedStates[0] = State.ValPaused;
        changedStates[1] = State.ValPaused;
        _doEpochTransition(changedIds, changedStates);

        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _exitVal(genesis[0]);
    }

    function test_exit_success_minActive_boundary() public {
        _setupGenesisCommittee(); // 4 ValActive

        // epochVACount = 4, minActive(4) = 3, maxSlot = 1
        // VA(4) > 3 → exit allowed. After exit: VA=3 = minActive(3). Good.
        _exitVal(genesis[0]);
        _assertNodeState(genesis[0].nodeId, State.ValExiting);
    }

    function test_exit_revert_InvalidState_fromValInactive() public {
        _setupWithOneIdle();
        // genesis[3] is ValInactive — exit only accepts ValActive/ValPaused
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _exitVal(genesis[3]);
    }

    function test_exit_revert_InvalidState_fromCandidate() public {
        _setupGenesisCommittee();
        NodeBundle memory n5 = _createNode(5);

        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _exitVal(n5);
    }

    function test_exit_revert_InvalidState_fromValReady() public {
        _setupWithOneIdle();
        _readyVal(genesis[3]); // ValInactive → ValReady

        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _exitVal(genesis[3]);
    }

    function test_exit_revert_InvalidState_doubleExit() public {
        _setupGenesisCommittee(); // N=4, maxExiting=1
        _exitVal(genesis[0]); // fills 1/1 exit slot

        // Same node: InvalidState fires first (state check before slot check)
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _exitVal(genesis[0]);
    }

    function test_pause_revert_SlotsFull_minActive() public {
        _setupGenesisCommittee(); // N=4, f=1, maxSlot=1, minActive=3

        // Exit one validator: VA=3, VE=1
        _exitVal(genesis[0]);
        _assertNodeState(genesis[0].nodeId, State.ValExiting);

        // Try to pause: VP=0 < maxSlot=1 (slot available), but VA=3 <= minActive=3 → SlotsFull
        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _pauseVal(genesis[1]);
    }

    /* ========== Pause + exit slot dynamics with N=7 ========== */

    function test_pauseExitSlotDynamics_7validators() public {
        // Raise limits to allow 7 candidates in pipeline
        vm.prank(owner);
        abv2.updateMaxCandReadyCount(7);

        // Create 3 more nodes beyond the 4 genesis
        NodeBundle memory n5 = _createNode(5);
        NodeBundle memory n6 = _createNode(6);
        NodeBundle memory n7 = _createNode(7);

        // Activate all 7 (Registered → CandReady)
        for (uint256 i = 0; i < 4; i++) _readyCand(genesis[i]);
        _readyCand(n5);
        _readyCand(n6);
        _readyCand(n7);

        // System transition: all 7 → ValActive
        address[] memory ids = new address[](7);
        State[] memory states = new State[](7);
        uint256[] memory timeouts = new uint256[](7);
        for (uint256 i = 0; i < 4; i++) {
            ids[i] = genesis[i].nodeId;
            states[i] = State.ValActive;
        }
        ids[4] = n5.nodeId;
        states[4] = State.ValActive;
        ids[5] = n6.nodeId;
        states[5] = State.ValActive;
        ids[6] = n7.nodeId;
        states[6] = State.ValActive;
        _doSystemTransition(ids, states, timeouts);

        // Restore default
        vm.prank(owner);
        abv2.updateMaxCandReadyCount(DEFAULT_MAX_READY_CAND_COUNT);

        // N=7: f=2, maxSlot=1, minActive=5
        assertEq(abv2.getEpochVACount(), 7);
        assertEq(abv2.getStateCount(State.ValActive), 7);

        // 1. Pause genesis[0]: VP=1 (maxSlot full), VA=6
        _pauseVal(genesis[0]);
        assertEq(abv2.getStateCount(State.ValPaused), 1);
        assertEq(abv2.getStateCount(State.ValActive), 6);

        // 2. Exit genesis[0] from paused: VP=0, VE=1, VA=6
        _exitVal(genesis[0]);
        assertEq(abv2.getStateCount(State.ValPaused), 0);
        assertEq(abv2.getStateCount(State.ValExiting), 1);

        // 3. Pause genesis[1]: VP=0 < maxSlot(1), VA=6 > minActive(5) → succeeds (freed pause slot)
        _pauseVal(genesis[1]);
        assertEq(abv2.getStateCount(State.ValPaused), 1);
        assertEq(abv2.getStateCount(State.ValActive), 5);

        // 4. Exit genesis[1] from paused: VE=1 >= maxSlot(1) → SlotsFull
        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _exitVal(genesis[1]);
    }

    /* ========== offboard ========== */

    function test_offboard_success() public {
        _setupWithOneIdle(); // genesis[3] = ValInactive

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.StateChanged(genesis[3].nodeId, State.ValInactive, State.Registered);

        _offboardVal(genesis[3]);
        _assertNodeState(genesis[3].nodeId, State.Registered);

        // Should be back to Registered state
        _assertRegistered(genesis[3].nodeId, true);
    }

    function test_offboard_revert_OnlyNodeId() public {
        _setupWithOneIdle();

        vm.expectRevert(IAddressBookV2.OnlyNodeId.selector);
        vm.prank(makeAddr("nonNodeId"));
        abv2.offboard(genesis[3].nodeId);
    }

    function test_offboard_revert_InvalidState() public {
        _setupGenesisCommittee();
        // genesis[0] is ValActive, not ValInactive
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _offboardVal(genesis[0]);
    }

    function test_offboard_stateCountConsistency() public {
        _setupWithOneIdle(); // genesis[0-2] = ValActive, genesis[3] = ValInactive

        uint256 valInactiveBefore = abv2.getStateCount(State.ValInactive);
        uint256 registeredBefore = abv2.getStateCount(State.Registered);
        uint256 allNodesBefore = abv2.getAllNodesLength();
        _offboardVal(genesis[3]); // ValInactive → Registered

        assertEq(abv2.getStateCount(State.ValInactive), valInactiveBefore - 1, "ValInactive count should decrease");
        assertEq(abv2.getStateCount(State.Registered), registeredBefore + 1, "Registered count should increase");
        assertEq(abv2.getAllNodesLength(), allNodesBefore - 1, "allNodes should shrink");
    }

    /* ========== Timeout boundary: exact and one-second-before ========== */

    function test_resume_revert_atExactTimeout() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]);

        uint256 timeout = abv2.getNodeInfo(genesis[0].nodeId).timeoutAt;
        vm.warp(timeout);

        vm.expectRevert(IAddressBookV2.TimeoutExpired.selector);
        _resumeVal(genesis[0]);
    }

    function test_exit_fromValPaused_revert_atExactTimeout() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]);

        uint256 timeout = abv2.getNodeInfo(genesis[0].nodeId).timeoutAt;
        vm.warp(timeout);

        vm.expectRevert(IAddressBookV2.TimeoutExpired.selector);
        _exitVal(genesis[0]);
    }

    function test_resume_success_withZeroTimeout() public {
        _setupGenesisCommittee();

        // System pauses with timeout = 0 (unusual but valid per trust-the-consensus)
        _doSingleTransition(genesis[0].nodeId, State.ValPaused, 0);

        // timeoutAt == 0 → no timeout check → resume succeeds
        _resumeVal(genesis[0]);
        _assertNodeState(genesis[0].nodeId, State.ValActive);
    }

    /* ========== Exit from ValPaused: no minActive check needed ========== */

    function test_exit_fromValPaused_noMinActiveCheck() public {
        _setupGenesisCommittee(); // N=4
        NodeBundle memory n5 = _createNode(5);
        _readyCand(n5);
        _doSingleTransition(n5.nodeId, State.ValActive, 0); // 5 VA, SF=5, maxSlot(5)=1

        _exitVal(genesis[0]); // VA=4, VE=1 (uses the 1 slot)
        assertEq(abv2.getStateCount(State.ValActive), 4);

        // Slot is full (VE+VP=1 >= maxSlot(5)=1) → can't exit another from ValActive
        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _exitVal(genesis[1]);

        // Process exit to free the slot (SF=4)
        _doSingleTransition(genesis[0].nodeId, State.Registered, 0);

        _pauseVal(genesis[1]); // VA=3, VP=1 (slot reused, maxSlot(4)=1)
        _assertNodeState(genesis[1].nodeId, State.ValPaused);

        // From ValPaused, exit doesn't check minActive
        _exitVal(genesis[1]); // VP→VE
        _assertNodeState(genesis[1].nodeId, State.ValExiting);
    }

    function test_exit_valPaused_usesExitSlot_notPauseSlot() public {
        _setupGenesisCommittee(); // N=4, maxSlot(4)=1

        _pauseVal(genesis[0]); // VP=1
        assertEq(abv2.getStateCount(State.ValPaused), 1);

        _exitVal(genesis[0]); // VP→VE
        assertEq(abv2.getStateCount(State.ValPaused), 0);
        assertEq(abv2.getStateCount(State.ValExiting), 1);
    }

    /* ========== Full lifecycle: create → ... → delete ========== */

    function test_fullLifecycle_createToDeleteRoundTrip() public {
        _setupGenesisCommittee();

        NodeBundle memory n = _createNode(5);
        _assertNodeState(n.nodeId, State.Registered);

        _readyCand(n);
        _assertNodeState(n.nodeId, State.CandReady);

        _doSingleTransition(n.nodeId, State.ValActive, 0);
        _assertNodeState(n.nodeId, State.ValActive);

        _pauseVal(n);
        _assertNodeState(n.nodeId, State.ValPaused);

        _resumeVal(n);
        _assertNodeState(n.nodeId, State.ValActive);

        _exitVal(n);
        _assertNodeState(n.nodeId, State.ValExiting);

        _doSingleTransition(n.nodeId, State.Registered, 0);
        _assertNodeState(n.nodeId, State.Registered);
        _assertRegistered(n.nodeId, true);

        vm.prank(n.manager);
        abv2.deleteNode(n.nodeId);
        assertEq(uint256(abv2.getNodeState(n.nodeId)), uint256(State.Unknown));
    }

    /* ========== Offboard from invalid states ========== */

    function test_offboard_revert_fromRegistered() public {
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _offboardVal(genesis[0]);
    }

    function test_offboard_revert_fromCandReady() public {
        _readyCand(genesis[0]);
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _offboardVal(genesis[0]);
    }

    function test_offboard_revert_fromValReady() public {
        _setupWithOneIdle();
        _readyVal(genesis[3]); // ValInactive → ValReady
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _offboardVal(genesis[3]);
    }

    function test_offboard_afterUnready() public {
        _setupWithOneIdle();
        _readyVal(genesis[3]);
        _unreadyVal(genesis[3]);
        _offboardVal(genesis[3]);
        _assertNodeState(genesis[3].nodeId, State.Registered);
        _assertRegistered(genesis[3].nodeId, true);
    }

    /* ========== Timeout preservation through ValInactive ↔ ValReady ========== */

    function test_readyValidator_preservesIdleTimeout() public {
        _setupWithOneIdle(); // genesis[3] = ValInactive with idle timeout

        uint256 originalTimeout = abv2.getNodeInfo(genesis[3].nodeId).timeoutAt;
        assertTrue(originalTimeout > 0, "idle timeout should be set");

        // readyValidator: ValInactive → ValReady
        _readyVal(genesis[3]);
        _assertNodeState(genesis[3].nodeId, State.ValReady);

        // Timeout should be preserved (idle timeout continues ticking)
        uint256 afterReady = abv2.getNodeInfo(genesis[3].nodeId).timeoutAt;
        assertEq(afterReady, originalTimeout, "readyValidator should preserve idle timeout");
    }

    function test_unreadyValidator_preservesIdleTimeout() public {
        _setupWithOneIdle();
        uint256 originalTimeout = abv2.getNodeInfo(genesis[3].nodeId).timeoutAt;

        // readyValidator → unreadyValidator round-trip
        _readyVal(genesis[3]);
        _unreadyVal(genesis[3]);

        // Timeout should still be preserved
        uint256 afterUnready = abv2.getNodeInfo(genesis[3].nodeId).timeoutAt;
        assertEq(afterUnready, originalTimeout, "unreadyValidator should preserve idle timeout");
    }
}
