// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {State, NodeInfo} from "../../src/types/Node.sol";

contract CandidateLifecycleTest is Base {
    /* ========== readyCandidate ========== */

    function test_readyCandidate_success() public {
        _readyCand(genesis[0]);

        // No longer in Registered state
        _assertRegistered(genesis[0].nodeId, false);

        // State is CandReady
        _assertNodeState(genesis[0].nodeId, State.CandReady);
    }

    function test_readyCandidate_revert_InvalidState_notInactive() public {
        // Activate once -> CandReady
        _readyCand(genesis[0]);

        // Try again -- no longer Registered
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _readyCand(genesis[0]);
    }

    function test_readyCandidate_revert_SlotsFull_maxReady() public {
        // maxReady = 2, fill it up
        _readyCand(genesis[0]);
        _readyCand(genesis[1]);

        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _readyCand(genesis[2]);
    }

    function test_readyCandidate_revert_SlotsFull_maxNodeCount() public {
        // Lower maxNodeCount to 5, set up genesis (4 ValActive)
        vm.prank(owner);
        abv2.updateMaxNodeCount(5);
        _setupGenesisCommittee(); // 4 ValActive in allNodes

        // Create n5 + activate → CandReady (allNodes = 5 = maxNodeCount)
        NodeBundle memory n5 = _createNode(5);
        _readyCand(n5);

        // Create n6 — attempting to activate should fail (allNodes full)
        NodeBundle memory n6 = _createNode(6);

        vm.expectRevert(IAddressBookV2.SlotsFull.selector);
        _readyCand(n6);
    }

    function test_readyCandidate_revert_StakingTooLow() public {
        // Create node with stake below MIN_STAKE
        NodeBundle memory n5 = _createNodeCustomStake(5, MIN_STAKE - 1);

        vm.expectRevert(IAddressBookV2.StakingTooLow.selector);
        _readyCand(n5);
    }

    function test_readyCandidate_revert_stakingDroppedAfterCreate() public {
        NodeBundle memory n5 = _createNode(5); // Created with MIN_STAKE
        n5.staking.mockSetStaking(MIN_STAKE - 1); // Drop below threshold after creation

        vm.expectRevert(IAddressBookV2.StakingTooLow.selector);
        _readyCand(n5);
    }

    function test_readyCandidate_revert_OnlyNodeId() public {
        address nonNodeId = makeAddr("nonNodeId");

        vm.expectRevert(IAddressBookV2.OnlyNodeId.selector);
        vm.prank(nonNodeId);
        abv2.readyCandidate(genesis[0].nodeId);
    }

    function test_readyCandidate_exactMinStake() public {
        NodeBundle memory n = _createNodeCustomStake(5, MIN_STAKE);
        _readyCand(n);
        _assertNodeState(n.nodeId, State.CandReady);
    }

    /* ========== unreadyCandidate ========== */

    function test_unreadyCandidate_success() public {
        _readyCand(genesis[0]);

        _unreadyCand(genesis[0]);

        // Back to Registered state
        _assertRegistered(genesis[0].nodeId, true);

        // State is Registered
        _assertNodeState(genesis[0].nodeId, State.Registered);
    }

    function test_unreadyCandidate_revert_InvalidState_notReady() public {
        // genesis[0] is Registered, not CandReady
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _unreadyCand(genesis[0]);
    }

    function test_unreadyCandidate_revert_fromCandTesting() public {
        _readyCand(genesis[0]); // CandReady

        // System moves to CandTesting
        _doSingleTransition(genesis[0].nodeId, State.CandTesting, 0);

        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        _unreadyCand(genesis[0]);
    }

    function test_unreadyCandidate_revert_OnlyNodeId() public {
        _readyCand(genesis[0]);

        address nonNodeId = makeAddr("nonNodeId");
        vm.expectRevert(IAddressBookV2.OnlyNodeId.selector);
        vm.prank(nonNodeId);
        abv2.unreadyCandidate(genesis[0].nodeId);
    }
}
