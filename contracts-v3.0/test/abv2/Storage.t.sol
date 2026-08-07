// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {State, NodeInfo, Profile, BlsPublicKeyInfo} from "../../src/types/Node.sol";

contract StorageTest is Base {
    /* ========== getNodeInfo ========== */

    function test_getNodeInfo_success() public view {
        NodeInfo memory info = abv2.getNodeInfo(genesis[0].nodeId);

        assertEq(info.stakingContract, address(genesis[0].staking));
        assertEq(info.rewardAddress, genesis[0].rewardAddr);
        assertEq(info.voterAddress, genesis[0].voterAddr);
        assertEq(uint256(info.state), uint256(State.Registered));
        assertEq(info.timeoutAt, 0);
        assertEq(info.gcId, 0);
    }

    function test_getNodeInfo_revert_NodeNotFound() public {
        address nonExistent = makeAddr("nonExistent");
        vm.expectRevert(IAddressBookV2.NodeNotFound.selector);
        abv2.getNodeInfo(nonExistent);
    }

    /* ========== getAllProfiles ========== */

    function test_getAllProfiles_initialState() public view {
        // 4 genesis nodes are Registered — excluded from getAllProfiles (allNodes only)
        Profile[] memory profiles = abv2.getAllProfiles();
        assertEq(profiles.length, 0);
    }

    function test_getAllProfiles_excludesRegistered() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Add a 5th node as Registered
        NodeBundle memory n5 = _createNode(5);

        Profile[] memory profiles = abv2.getAllProfiles();
        // Only allNodes nodes (Registered excluded)
        assertEq(profiles.length, 4);

        for (uint256 i = 0; i < profiles.length; i++) {
            assertEq(uint256(profiles[i].state), uint256(State.ValActive));
            assertTrue(profiles[i].nodeId != n5.nodeId, "Registered node should not be in profiles");
        }
    }

    function test_getAllProfiles_profileFields() public {
        _setupGenesisCommittee(); // 4 ValActive

        Profile[] memory profiles = abv2.getAllProfiles();
        assertTrue(profiles.length > 0);

        // Verify profile fields match node info
        Profile memory p = profiles[0];
        NodeInfo memory info = abv2.getNodeInfo(p.nodeId);

        assertEq(p.stakingContract, info.stakingContract);
        assertEq(p.rewardAddress, info.rewardAddress);
        assertEq(p.timeoutAt, info.timeoutAt);
        assertEq(uint256(p.state), uint256(info.state));
    }

    function test_getAllProfiles_includesSuspended() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Suspend one validator
        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        Profile[] memory profiles = abv2.getAllProfiles();
        // All 4 returned — suspended nodes are no longer filtered here
        assertEq(profiles.length, 4);

        // Suspended node IS present; caller must cross-reference getSuspendedValidators()
        bool found;
        for (uint256 i = 0; i < profiles.length; i++) {
            if (profiles[i].nodeId == genesis[0].nodeId) found = true;
        }
        assertTrue(found, "suspended node should be included in profiles");
    }

    function test_getAllProfiles_includesSuspended_multipleSuspended() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Suspend two validators
        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);
        vm.prank(owner);
        abv2.suspendValidator(genesis[1].nodeId);

        Profile[] memory profiles = abv2.getAllProfiles();
        assertEq(profiles.length, 4);

        address[] memory suspended = abv2.getSuspendedValidators();
        assertEq(suspended.length, 2);
    }

    function test_getAllProfiles_suspendedWithRegistered() public {
        _setupGenesisCommittee(); // 4 ValActive
        _createNode(5); // Registered (excluded from allNodes, so excluded from profiles)

        // Suspend one validator
        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        Profile[] memory profiles = abv2.getAllProfiles();
        // 4 active (suspended included), Registered still excluded (not in allNodes)
        assertEq(profiles.length, 4);
    }

    /* ========== getAllBlsInfo ========== */

    function test_getAllBlsInfo_initialState() public view {
        // 4 genesis nodes are Registered — excluded from getAllBlsInfo (allNodes only)
        (address[] memory nodeIds, BlsPublicKeyInfo[] memory pubkeys) = abv2.getAllBlsInfo();
        assertEq(nodeIds.length, 0);
        assertEq(pubkeys.length, 0);
    }

    function test_getAllBlsInfo_excludesRegistered() public {
        _setupGenesisCommittee(); // 4 ValActive

        // Add a 5th node as Registered
        NodeBundle memory n5 = _createNode(5);

        (address[] memory nodeIds, BlsPublicKeyInfo[] memory pubkeys) = abv2.getAllBlsInfo();
        // Only allNodes nodes (Registered excluded)
        assertEq(nodeIds.length, 4);
        assertEq(pubkeys.length, 4);

        for (uint256 i = 0; i < nodeIds.length; i++) {
            assertTrue(nodeIds[i] != n5.nodeId, "Registered node should not be in getAllBlsInfo");
        }
    }

    function test_getAllBlsInfo_matchesNodeInfo() public {
        _setupGenesisCommittee(); // 4 ValActive

        (address[] memory nodeIds, BlsPublicKeyInfo[] memory pubkeys) = abv2.getAllBlsInfo();
        assertTrue(nodeIds.length > 0);

        // Verify BLS data matches getNodeInfo
        NodeInfo memory info = abv2.getNodeInfo(nodeIds[0]);
        assertEq(keccak256(pubkeys[0].publicKey), keccak256(info.blsInfo.publicKey));
        assertEq(keccak256(pubkeys[0].pop), keccak256(info.blsInfo.pop));
    }

    function test_getAllBlsInfo_includesSuspended() public {
        _setupGenesisCommittee(); // 4 ValActive

        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        (address[] memory nodeIds, BlsPublicKeyInfo[] memory pubkeys) = abv2.getAllBlsInfo();
        // Suspended nodes are no longer filtered — all 4 returned
        assertEq(nodeIds.length, 4);
        assertEq(pubkeys.length, 4);

        bool found;
        for (uint256 i = 0; i < nodeIds.length; i++) {
            if (nodeIds[i] == genesis[0].nodeId) found = true;
        }
        assertTrue(found, "suspended node should be included in getAllBlsInfo");
    }

    function test_getAllBlsInfo_includesSuspended_multipleSuspended() public {
        _setupGenesisCommittee(); // 4 ValActive

        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);
        vm.prank(owner);
        abv2.suspendValidator(genesis[1].nodeId);

        (address[] memory nodeIds, BlsPublicKeyInfo[] memory pubkeys) = abv2.getAllBlsInfo();
        assertEq(nodeIds.length, 4);
        assertEq(pubkeys.length, 4);
    }

    /* ========== getNodeState ========== */

    function test_getNodeState_registered() public view {
        assertEq(uint256(abv2.getNodeState(genesis[0].nodeId)), uint256(State.Registered));
    }

    function test_getNodeState_valActive() public {
        _setupGenesisCommittee();
        assertEq(uint256(abv2.getNodeState(genesis[0].nodeId)), uint256(State.ValActive));
    }

    function test_getNodeState_unknown() public {
        address nonExistent = makeAddr("nonExistent");
        assertEq(uint256(abv2.getNodeState(nonExistent)), uint256(State.Unknown));
    }

    /* ========== isUsedAddress ========== */

    function test_isUsedAddress_nodeId() public view {
        assertTrue(abv2.isUsedAddress(genesis[0].nodeId));
    }

    function test_isUsedAddress_stakingContract() public view {
        assertTrue(abv2.isUsedAddress(address(genesis[0].staking)));
    }

    function test_isUsedAddress_rewardAddress() public view {
        assertTrue(abv2.isUsedAddress(genesis[0].rewardAddr));
    }

    function test_isUsedAddress_unknown() public {
        address unknown = makeAddr("unknownAddr");
        assertFalse(abv2.isUsedAddress(unknown));
    }

    /* ========== getSuspender / getConfigurator ========== */

    function test_getSuspender() public view {
        assertEq(abv2.getSuspender(), owner);
    }

    function test_getConfigurator() public view {
        assertEq(abv2.getConfigurator(), owner);
    }

    /* ========== getAllNodesLength ========== */

    function test_getAllNodesLength_initial() public view {
        // All 4 genesis nodes are Registered → not in allNodes
        assertEq(abv2.getAllNodesLength(), 0);
    }

    function test_getAllNodesLength_afterActivation() public {
        _readyCand(genesis[0]); // Registered → CandReady (moves to allNodes)
        assertEq(abv2.getAllNodesLength(), 1);
    }

    function test_getAllNodesLength_afterFullSetup() public {
        _setupGenesisCommittee(); // 4 ValActive
        assertEq(abv2.getAllNodesLength(), 4);
    }

    /* ========== getStateCount ========== */

    function test_getStateCount_initial() public view {
        assertEq(abv2.getStateCount(State.Registered), 4);
        assertEq(abv2.getStateCount(State.CandReady), 0);
        assertEq(abv2.getStateCount(State.ValActive), 0);
        assertEq(abv2.getStateCount(State.Unknown), 0);
    }

    function test_getStateCount_afterActivation() public {
        _readyCand(genesis[0]);
        assertEq(abv2.getStateCount(State.Registered), 3);
        assertEq(abv2.getStateCount(State.CandReady), 1);
    }

    function test_getStateCount_afterGenesisCommittee() public {
        _setupGenesisCommittee();
        assertEq(abv2.getStateCount(State.Registered), 0);
        assertEq(abv2.getStateCount(State.ValActive), 4);
    }

    function test_getStateCount_afterPause() public {
        _setupGenesisCommittee();
        _pauseVal(genesis[0]);
        assertEq(abv2.getStateCount(State.ValActive), 3);
        assertEq(abv2.getStateCount(State.ValPaused), 1);
    }

    function test_getStateCount_afterDelete() public {
        assertEq(abv2.getStateCount(State.Registered), 4);
        vm.prank(genesis[0].manager);
        abv2.deleteNode(genesis[0].nodeId);
        assertEq(abv2.getStateCount(State.Registered), 3);
    }

    /* ========== getSuspendedValidators ========== */

    function test_getSuspendedValidators_empty() public view {
        assertEq(abv2.getSuspendedValidators().length, 0);
    }

    function test_getSuspendedValidators_afterSuspend() public {
        _setupGenesisCommittee();

        vm.prank(owner);
        abv2.suspendValidator(genesis[0].nodeId);

        address[] memory suspended = abv2.getSuspendedValidators();
        assertEq(suspended.length, 1);
        assertEq(suspended[0], genesis[0].nodeId);
    }

    /* ========== constants ========== */

    function test_constants() public view {
        assertEq(abv2.CONTRACT_TYPE(), "AddressBook");
        assertEq(abv2.VERSION(), 2);
        assertEq(abv2.MIN_STAKE(), 5_000_000 ether);
    }

    /* ========== epochBlockInterval ========== */

    function test_epochBlockInterval() public view {
        assertEq(abv2.epochBlockInterval(), EPOCH_BLOCK_INTERVAL);
    }

    /* ========== currentEpoch ========== */

    function test_currentEpoch() public {
        assertEq(abv2.currentEpoch(), block.number / EPOCH_BLOCK_INTERVAL);
        _rollToNextEpoch();
        assertEq(abv2.currentEpoch(), 1);
    }

    /* ========== epochVACount ========== */

    function test_epochVACount_zeroBeforeGenesisCommittee() public view {
        assertEq(abv2.getEpochVACount(), 0);
    }

    /* ========== stateCount: all 9 states initially zero (except Registered) ========== */

    function test_stateCount_allStatesInitially() public view {
        assertEq(abv2.getStateCount(State.Unknown), 0);
        assertEq(abv2.getStateCount(State.CandReady), 0);
        assertEq(abv2.getStateCount(State.CandTesting), 0);
        assertEq(abv2.getStateCount(State.ValInactive), 0);
        assertEq(abv2.getStateCount(State.ValReady), 0);
        assertEq(abv2.getStateCount(State.ValActive), 0);
        assertEq(abv2.getStateCount(State.ValPaused), 0);
        assertEq(abv2.getStateCount(State.ValExiting), 0);
    }

    /* ========== getAllProfiles / getAllBlsInfo: after all deleted ========== */

    function test_getAllProfiles_afterAllDeleted() public {
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(genesis[i].manager);
            abv2.deleteNode(genesis[i].nodeId);
        }
        Profile[] memory profiles = abv2.getAllProfiles();
        assertEq(profiles.length, 0);
    }

    function test_getAllBlsInfo_afterAllDeleted() public {
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(genesis[i].manager);
            abv2.deleteNode(genesis[i].nodeId);
        }
        (address[] memory nodeIds, BlsPublicKeyInfo[] memory pubkeys) = abv2.getAllBlsInfo();
        assertEq(nodeIds.length, 0);
        assertEq(pubkeys.length, 0);
    }
}
