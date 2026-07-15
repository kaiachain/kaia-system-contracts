// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DeployHelpers} from "./DeployHelpers.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {State, BlsPublicKeyInfo, NodeInfo} from "../../src/types/Node.sol";
import {MockCnStaking} from "../../src/CnStaking/mocks/MockCnStaking.sol";

/// @title Base
/// @notice Test base with deployment and helpers. setUp creates 4 Registered genesis nodes.
///         Tests compose the exact state they need via transition helpers.
contract Base is DeployHelpers {
    /* ========== TYPES ========== */

    struct NodeBundle {
        address nodeId;
        uint256 nodeIdPk;
        address manager;
        MockCnStaking staking;
        address rewardAddr;
        address voterAddr;
    }

    /* ========== STATE ========== */

    address internal owner;
    NodeBundle[4] internal genesis;

    /* ========== SETUP ========== */

    /// @dev Deploys all contracts and creates 4 genesis nodes as Registered.
    ///      Tests that need validators should call transition helpers explicitly.
    function setUp() public virtual {
        owner = makeAddr("owner");

        deployAll(
            owner,
            DEFAULT_PFS_THRESHOLD,
            DEFAULT_PAUSE_TIMEOUT,
            DEFAULT_IDLE_TIMEOUT,
            DEFAULT_MAX_NODE_COUNT,
            DEFAULT_MAX_READY_CAND_COUNT,
            DEFAULT_KEF_ADDRESS,
            DEFAULT_KIF_ADDRESS,
            DEFAULT_KPF_ADDRESS
        );

        // Create 4 genesis nodes as Registered (indices 1-4)
        for (uint256 i = 0; i < 4; i++) {
            genesis[i] = _createNode(i + 1);
        }
    }

    /* ========== NODE CREATION HELPERS ========== */

    /// @notice Creates a NodeBundle with deterministic addresses derived from index.
    ///         Also mocks getDeployer so the bundle's manager is recognized as the staking deployer.
    function _makeNodeBundle(uint256 index) internal returns (NodeBundle memory n) {
        string memory idx = vm.toString(index);
        (address nodeId, uint256 nodeIdPk) = makeAddrAndKey(string.concat("node", idx));
        n = NodeBundle({
            nodeId: nodeId,
            nodeIdPk: nodeIdPk,
            manager: makeAddr(string.concat("manager", idx)),
            staking: deployMockCnStaking(MIN_STAKE, 0),
            rewardAddr: makeAddr(string.concat("reward", idx)),
            voterAddr: makeAddr(string.concat("voter", idx))
        });
        _mockDeployer(address(n.staking), n.manager);
    }

    /// @notice Creates a node via AddressBookV2 with default MIN_STAKE
    function _createNode(uint256 index) internal returns (NodeBundle memory n) {
        n = _makeNodeBundle(index);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), string.concat("node-", vm.toString(index)), "", _signNodeId(n));
    }

    /// @notice Creates a node via AddressBookV2 with a custom stake amount
    function _createNodeCustomStake(uint256 index, uint256 stake) internal returns (NodeBundle memory n) {
        string memory idx = vm.toString(index);
        (address nodeId, uint256 nodeIdPk) = makeAddrAndKey(string.concat("node", idx));
        n = NodeBundle({
            nodeId: nodeId,
            nodeIdPk: nodeIdPk,
            manager: makeAddr(string.concat("manager", idx)),
            staking: deployMockCnStaking(stake, 0),
            rewardAddr: makeAddr(string.concat("reward", idx)),
            voterAddr: makeAddr(string.concat("voter", idx))
        });
        _mockDeployer(address(n.staking), n.manager);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), string.concat("node-", vm.toString(index)), "", _signNodeId(n));
    }

    /// @dev nodeId ownership signature for a NodeBundle.
    function _signNodeId(NodeBundle memory n) internal view returns (bytes memory) {
        return _signNodeIdFor(n.nodeIdPk, n.manager, n.nodeId, address(n.staking));
    }

    /* ========== STATE TRANSITION HELPERS ========== */

    /// @notice Registered -> CandReady (via readyCandidate)
    function _readyCand(NodeBundle memory n) internal {
        vm.deal(n.nodeId, 10 ether);
        vm.prank(n.nodeId);
        abv2.readyCandidate(n.nodeId);
    }

    /// @notice CandReady -> Registered (via unreadyCandidate)
    function _unreadyCand(NodeBundle memory n) internal {
        vm.prank(n.nodeId);
        abv2.unreadyCandidate(n.nodeId);
    }

    /// @notice ValInactive -> ValReady (via readyValidator)
    function _readyVal(NodeBundle memory n) internal {
        vm.prank(n.nodeId);
        abv2.readyValidator(n.nodeId);
    }

    /// @notice ValReady -> ValInactive (via unreadyValidator)
    function _unreadyVal(NodeBundle memory n) internal {
        vm.prank(n.nodeId);
        abv2.unreadyValidator(n.nodeId);
    }

    /// @notice ValActive -> ValPaused (via pause)
    function _pauseVal(NodeBundle memory n) internal {
        vm.prank(n.nodeId);
        abv2.pause(n.nodeId);
    }

    /// @notice ValPaused -> ValActive (via resume)
    function _resumeVal(NodeBundle memory n) internal {
        vm.prank(n.nodeId);
        abv2.resume(n.nodeId);
    }

    /// @notice ValActive/ValPaused -> ValExiting (via exit)
    function _exitVal(NodeBundle memory n) internal {
        vm.prank(n.nodeId);
        abv2.exit(n.nodeId);
    }

    /// @notice ValInactive -> Registered (via offboard)
    function _offboardVal(NodeBundle memory n) internal {
        vm.prank(n.nodeId);
        abv2.offboard(n.nodeId);
    }

    /* ========== COMPOSITE HELPERS ========== */

    /// @notice Promotes all 4 genesis nodes from Registered to ValActive via system transition.
    ///         After: epoch=1, block=86400, 4 ValActive validators.
    function _setupGenesisCommittee() internal {
        // Temporarily raise maxReady so we can activate all 4 at once (default is 2)
        vm.prank(owner);
        abv2.updateMaxCandReadyCount(4);

        // Ready all 4 candidates (Registered -> CandReady)
        for (uint256 i = 0; i < 4; i++) {
            _readyCand(genesis[i]);
        }

        // System transition at epoch: all 4 CandReady → ValActive
        address[] memory changedIds = new address[](4);
        State[] memory changedStates = new State[](4);
        uint256[] memory timeoutAts = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            changedIds[i] = genesis[i].nodeId;
            changedStates[i] = State.ValActive;
            // ValActive has no timeout
        }

        _doSystemTransition(changedIds, changedStates, timeoutAts);

        // Restore default maxReady
        vm.prank(owner);
        abv2.updateMaxCandReadyCount(DEFAULT_MAX_READY_CAND_COUNT);
    }

    /* ========== SYSTEM TRANSITION HELPERS ========== */

    /// @notice System transition with explicit timeoutAts.
    ///         epochVACount is auto-computed as VA count after the given transitions.
    function _doSystemTransition(
        address[] memory nodeIds,
        State[] memory newStates,
        uint256[] memory timeoutAts
    ) internal {
        _rollToNextEpoch();
        uint256 epochVACount = _computeEpochSF(nodeIds, newStates);
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(nodeIds, newStates, timeoutAts, epochVACount);
    }

    /// @notice Computes VA count after applying the given transitions (used as epochVACount).
    function _computeEpochSF(address[] memory nodeIds, State[] memory newStates) internal view returns (uint256) {
        uint256 va = abv2.getStateCount(State.ValActive);
        for (uint256 i = 0; i < nodeIds.length; i++) {
            State cur = abv2.getNodeState(nodeIds[i]);
            if (cur == State.ValActive && newStates[i] != State.ValActive) va--;
            else if (cur != State.ValActive && newStates[i] == State.ValActive) va++;
        }
        return va;
    }

    /// @notice System transition for a single node (convenience wrapper)
    function _doSingleTransition(address nodeId, State newState, uint256 timeoutAt) internal {
        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = nodeId;
        states[0] = newState;
        timeouts[0] = timeoutAt;
        _doSystemTransition(ids, states, timeouts);
    }

    /// @notice Compat wrapper: system transition with zero timeouts (for simple state changes)
    function _doEpochTransition(address[] memory changedValIds, State[] memory changedValStates) internal {
        uint256[] memory timeoutAts = new uint256[](changedValIds.length);
        _doSystemTransition(changedValIds, changedValStates, timeoutAts);
    }

    /* ========== SYSTEM TX HELPERS ========== */

    /// @notice Rolls block.number to the next epoch boundary
    function _rollToNextEpoch() internal {
        uint256 current = block.number;
        uint256 nextEpochBlock = ((current / EPOCH_BLOCK_INTERVAL) + 1) * EPOCH_BLOCK_INTERVAL;
        vm.roll(nextEpochBlock);
    }

    /// @notice Warps block.timestamp forward by the given seconds
    function _warpForward(uint256 seconds_) internal {
        vm.warp(block.timestamp + seconds_);
    }

    /* ========== ASSERTION HELPERS ========== */

    /// @notice Asserts that a node is in the expected state
    function _assertNodeState(address nodeId, State expectedState) internal view {
        NodeInfo memory info = abv2.getNodeInfo(nodeId);
        assertEq(uint256(info.state), uint256(expectedState), "unexpected node state");
    }

    /// @notice Asserts that a node is (or is not) in Registered state
    function _assertRegistered(address nodeId, bool expected) internal view {
        assertEq(abv2.getNodeState(nodeId) == State.Registered, expected, "unexpected Registered state");
    }

    /// @notice Asserts the all nodes length
    function _assertAllNodesLength(uint256 expectedCount) internal view {
        assertEq(abv2.getAllNodesLength(), expectedCount, "unexpected all nodes length");
    }
}
