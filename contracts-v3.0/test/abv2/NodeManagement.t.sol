// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {AddressBookV2Harness} from "../base/AddressBookV2Harness.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IRegistry} from "../../src/system/IRegistry.sol";
import {NodeVerifier} from "../../src/libraries/NodeVerifier.sol";
import {State, BlsPublicKeyInfo, NodeInfo} from "../../src/types/Node.sol";
import {MockCnStaking} from "../../src/CnStaking/mocks/MockCnStaking.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract NodeManagementTest is Base {
    /* ========== createNode ========== */

    function test_createNode_success() public {
        // Use index 5 (genesis uses 1-4)
        NodeBundle memory n = _makeNodeBundle(5);

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.NodeCreated(n.nodeId);

        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "meta", _signNodeId(n));

        // Verify manager stored in NC
        assertEq(abv2.getNodeInfo(n.nodeId).manager, n.manager);

        // Verify nodeInfo
        NodeInfo memory info = abv2.getNodeInfo(n.nodeId);
        assertEq(info.stakingContract, address(n.staking));
        assertEq(info.rewardAddress, n.rewardAddr);
        assertEq(info.voterAddress, n.voterAddr);
        assertEq(uint256(info.state), uint256(State.Registered));
        assertEq(info.timeoutAt, 0);
        assertEq(info.gcId, 0);
        assertEq(keccak256(bytes(info.name)), keccak256(bytes("testnode")));
        assertEq(keccak256(bytes(info.metadata)), keccak256(bytes("meta")));

        // Verify node is in Registered state
        _assertRegistered(n.nodeId, true);
    }

    function test_createNode_revert_NodeAlreadyExists() public {
        // genesis[0] already exists
        NodeBundle memory g = genesis[0];

        vm.expectRevert(IAddressBookV2.NodeAlreadyExists.selector);
        vm.prank(g.manager);
        abv2.createNode(g.nodeId, address(g.staking), g.rewardAddr, g.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(g));
    }

    function test_createNode_revert_InvalidInput_zeroNodeId() public {
        NodeBundle memory n = _makeNodeBundle(5);

        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(address(0), address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_InvalidInput_zeroStaking() public {
        NodeBundle memory n = _makeNodeBundle(5);

        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(0), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_InvalidInput_zeroReward() public {
        NodeBundle memory n = _makeNodeBundle(5);

        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), address(0), n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_InvalidInput_duplicateAddresses() public {
        NodeBundle memory n = _makeNodeBundle(5);

        // nodeId == stakingContract
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, n.nodeId, n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));

        // nodeId == rewardAddress
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.nodeId, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));

        // stakingContract == rewardAddress
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, n.rewardAddr, n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_InvalidInput_blsPublicKeyWrongSize() public {
        NodeBundle memory n = _makeNodeBundle(5);
        BlsPublicKeyInfo memory badBls = BlsPublicKeyInfo({publicKey: new bytes(32), pop: new bytes(96)});
        badBls.pop[0] = 0x01;

        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, badBls, "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_InvalidInput_blsPopWrongSize() public {
        NodeBundle memory n = _makeNodeBundle(5);
        BlsPublicKeyInfo memory badBls = BlsPublicKeyInfo({publicKey: new bytes(48), pop: new bytes(48)});
        badBls.publicKey[0] = 0x01;

        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, badBls, "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_InvalidInput_blsPublicKeyZero() public {
        NodeBundle memory n = _makeNodeBundle(5);
        BlsPublicKeyInfo memory badBls = BlsPublicKeyInfo({publicKey: new bytes(48), pop: new bytes(96)});
        badBls.pop[0] = 0x01; // pop is valid, publicKey is all zeros

        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, badBls, "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_InvalidInput_blsPopZero() public {
        NodeBundle memory n = _makeNodeBundle(5);
        BlsPublicKeyInfo memory badBls = BlsPublicKeyInfo({publicKey: new bytes(48), pop: new bytes(96)});
        badBls.publicKey[0] = 0x01; // publicKey is valid, pop is all zeros

        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, badBls, "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_StakingDeployerMismatch() public {
        NodeBundle memory n = _makeNodeBundle(5);

        // Override deployer mock so getDeployer(n.staking) returns address(0),
        // which won't match n.manager → StakingDeployerMismatch
        _mockDeployer(address(n.staking), address(0));

        vm.expectRevert(NodeVerifier.StakingDeployerMismatch.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_AddressAlreadyRegistered_nodeId() public {
        (address dup, uint256 dupPk) = makeAddrAndKey("reward1"); // == genesis[0].rewardAddr, already used, not a node
        NodeBundle memory n = _makeNodeBundle(5);
        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        vm.prank(n.manager);
        abv2.createNode(dup, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeIdFor(dupPk, n.manager, dup, address(n.staking)));
    }

    function test_createNode_revert_AddressAlreadyRegistered_staking() public {
        NodeBundle memory g = genesis[0];
        NodeBundle memory n = _makeNodeBundle(5);
        _mockDeployer(address(g.staking), n.manager);
        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(g.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeIdFor(n.nodeIdPk, n.manager, n.nodeId, address(g.staking)));
    }

    function test_createNode_revert_AddressAlreadyRegistered_reward() public {
        NodeBundle memory g = genesis[0];
        NodeBundle memory n = _makeNodeBundle(5);

        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), g.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));
    }

    function test_createNode_revert_InvalidInput_emptyName() public {
        NodeBundle memory n = _makeNodeBundle(5);

        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "", "", _signNodeId(n));
    }

    /* ========== createNode: nodeId ownership proof ========== */

    /// @dev Positive control: the exact same setup that the wrong-* cases below reject succeeds
    ///      when a valid nodeId signature is presented.
    function test_createNode_nodeIdProof_validSig_succeeds() public {
        NodeBundle memory n = _makeNodeBundle(5);

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.NodeCreated(n.nodeId);

        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));

        assertEq(abv2.getNodeInfo(n.nodeId).manager, n.manager);
        assertEq(uint256(abv2.getNodeInfo(n.nodeId).state), uint256(State.Registered));
    }

    /// @dev A signature by anyone other than nodeId is rejected — a caller cannot register a
    ///      nodeId it does not control.
    function test_createNode_revert_NodeIdProofInvalid_wrongSigner() public {
        NodeBundle memory n = _makeNodeBundle(5);
        (, uint256 attackerPk) = makeAddrAndKey("attacker");
        bytes memory badSig = _signNodeIdFor(attackerPk, n.manager, n.nodeId, address(n.staking));

        vm.expectRevert(NodeVerifier.NodeIdProofInvalid.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", badSig);
    }

    /// @dev An empty / malformed signature is rejected.
    function test_createNode_revert_NodeIdProofInvalid_emptySig() public {
        NodeBundle memory n = _makeNodeBundle(5);

        vm.expectRevert(NodeVerifier.NodeIdProofInvalid.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", "");
    }

    /// @dev A valid nodeId signature is bound to one caller; a different caller cannot replay it
    ///      (front-running / squat defense). The alternate caller still passes the deployer check.
    function test_createNode_revert_NodeIdProofInvalid_wrongCaller() public {
        NodeBundle memory n = _makeNodeBundle(5);
        bytes memory sigForManager = _signNodeId(n); // authorizes n.manager as the registrant

        address frontrunner = makeAddr("frontrunner");
        _mockDeployer(address(n.staking), frontrunner);

        vm.expectRevert(NodeVerifier.NodeIdProofInvalid.selector);
        vm.prank(frontrunner);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", sigForManager);
    }

    /// @dev A signature bound to a different staking contract is rejected.
    function test_createNode_revert_NodeIdProofInvalid_wrongStaking() public {
        NodeBundle memory n = _makeNodeBundle(5);
        NodeBundle memory other = _makeNodeBundle(6);
        bytes memory sigForOtherStaking = _signNodeIdFor(n.nodeIdPk, n.manager, n.nodeId, address(other.staking));

        vm.expectRevert(NodeVerifier.NodeIdProofInvalid.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", sigForOtherStaking);
    }

    /* ========== deleteNode ========== */

    function test_deleteNode_success() public {
        NodeBundle memory g = genesis[0];

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.NodeDeleted(g.nodeId);

        vm.prank(g.manager);
        abv2.deleteNode(g.nodeId);

        vm.expectRevert(IAddressBookV2.NodeNotFound.selector);
        abv2.getNodeInfo(g.nodeId);

        // Should no longer be in Registered state (deleted)
        _assertRegistered(g.nodeId, false);
    }

    function test_deleteNode_revert_OnlyManager() public {
        NodeBundle memory g = genesis[0];
        address nonManager = makeAddr("nonManager");

        vm.expectRevert(IAddressBookV2.OnlyManager.selector);
        vm.prank(nonManager);
        abv2.deleteNode(g.nodeId);
    }

    function test_deleteNode_revert_notInRegisteredState() public {
        // Activate genesis[0] to CandReady
        _readyCand(genesis[0]);

        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        vm.prank(genesis[0].manager);
        abv2.deleteNode(genesis[0].nodeId);
    }

    function test_deleteNode_unregistersAddresses() public {
        NodeBundle memory g = genesis[0];
        address oldNodeId = g.nodeId;
        address oldStaking = address(g.staking);
        address oldReward = g.rewardAddr;

        // Delete the node
        vm.prank(g.manager);
        abv2.deleteNode(oldNodeId);

        // Now create a new node re-using the same addresses — should succeed
        NodeBundle memory n = _makeNodeBundle(5);
        _mockDeployer(oldStaking, n.manager);
        vm.prank(n.manager);
        abv2.createNode(oldNodeId, oldStaking, oldReward, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeIdFor(g.nodeIdPk, n.manager, oldNodeId, oldStaking));

        // Verify it was created
        _assertNodeState(oldNodeId, State.Registered);
        _assertRegistered(oldNodeId, true);
    }

    /* ========== Re-registration after delete ========== */

    function test_deleteNode_reregistration_sameAddresses() public {
        NodeBundle memory g = genesis[0];
        address nodeId = g.nodeId;
        address stakingAddr = address(g.staking);
        address rewardAddr = g.rewardAddr;

        vm.prank(g.manager);
        abv2.deleteNode(nodeId);

        assertFalse(abv2.isUsedAddress(nodeId));
        assertFalse(abv2.isUsedAddress(stakingAddr));
        assertFalse(abv2.isUsedAddress(rewardAddr));

        address newManager = makeAddr("newManager");
        _mockDeployer(stakingAddr, newManager);
        vm.prank(newManager);
        abv2.createNode(nodeId, stakingAddr, rewardAddr, g.voterAddr, _makeBlsInfo(), "testnode", "re-registered", _signNodeIdFor(g.nodeIdPk, newManager, nodeId, stakingAddr));

        _assertNodeState(nodeId, State.Registered);
        assertEq(abv2.getNodeInfo(nodeId).manager, newManager);
        assertTrue(abv2.isUsedAddress(nodeId));
    }

    /* ========== Staking edge cases ========== */

    function test_createNode_stakingUnderflow_reverts_onActivate() public {
        string memory idx = vm.toString(uint256(5));
        NodeBundle memory n;
        (n.nodeId, n.nodeIdPk) = makeAddrAndKey(string.concat("node", idx));
        n.manager = makeAddr(string.concat("manager", idx));
        n.staking = deployMockCnStaking(MIN_STAKE, MIN_STAKE + 1); // unstaking > staking
        n.rewardAddr = makeAddr(string.concat("reward", idx));
        n.voterAddr = makeAddr(string.concat("voter", idx));

        _mockDeployer(address(n.staking), n.manager);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));

        vm.expectRevert();
        _readyCand(n);
    }

    /* ========== voterAddress edge cases ========== */

    function test_createNode_zeroVoterAddress() public {
        NodeBundle memory n = _makeNodeBundle(5);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, address(0), _makeBlsInfo(), "testnode", "", _signNodeId(n));
        NodeInfo memory info = abv2.getNodeInfo(n.nodeId);
        assertEq(info.voterAddress, address(0));
    }

    function test_createNode_voterSameAsNodeId() public {
        NodeBundle memory n = _makeNodeBundle(5);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.nodeId, _makeBlsInfo(), "testnode", "", _signNodeId(n));
        NodeInfo memory info = abv2.getNodeInfo(n.nodeId);
        assertEq(info.voterAddress, n.nodeId);
    }

    /* ========== BLS key non-uniqueness (two nodes, same BLS) ========== */

    function test_createNode_duplicateBlsKeys_succeeds() public {
        BlsPublicKeyInfo memory sameBlsInfo = _makeBlsInfo();

        NodeBundle memory n5 = _makeNodeBundle(5);
        vm.prank(n5.manager);
        abv2.createNode(n5.nodeId, address(n5.staking), n5.rewardAddr, n5.voterAddr, sameBlsInfo, "testnode", "", _signNodeId(n5));

        NodeBundle memory n6 = _makeNodeBundle(6);
        vm.prank(n6.manager);
        abv2.createNode(n6.nodeId, address(n6.staking), n6.rewardAddr, n6.voterAddr, sameBlsInfo, "testnode", "", _signNodeId(n6));

        NodeInfo memory info5 = abv2.getNodeInfo(n5.nodeId);
        NodeInfo memory info6 = abv2.getNodeInfo(n6.nodeId);
        assertEq(keccak256(info5.blsInfo.publicKey), keccak256(info6.blsInfo.publicKey));
    }

    /* ========== metadata: empty and long ========== */

    function test_createNode_emptyMetadata() public {
        NodeBundle memory n = _makeNodeBundle(5);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeId(n));
        NodeInfo memory info = abv2.getNodeInfo(n.nodeId);
        assertEq(bytes(info.metadata).length, 0);
    }

    function test_createNode_longMetadata() public {
        NodeBundle memory n = _makeNodeBundle(5);
        string memory longMeta = "abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789";
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", longMeta, _signNodeId(n));
        NodeInfo memory info = abv2.getNodeInfo(n.nodeId);
        assertEq(keccak256(bytes(info.metadata)), keccak256(bytes(longMeta)));
    }

    /* ========== createNode: caller becomes manager ========== */

    function test_createNode_callerBecomesManager() public {
        address caller = makeAddr("caller");
        NodeBundle memory n = _makeNodeBundle(5);
        _mockDeployer(address(n.staking), caller);
        vm.prank(caller);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", "", _signNodeIdFor(n.nodeIdPk, caller, n.nodeId, address(n.staking)));
        assertEq(abv2.getNodeInfo(n.nodeId).manager, caller);
    }

    /* ========== deleteNode + recreate: stateCount consistency ========== */

    function test_deleteAndRecreate_stateCountConsistency() public {
        assertEq(abv2.getStateCount(State.Registered), 4);

        vm.prank(genesis[0].manager);
        abv2.deleteNode(genesis[0].nodeId);
        assertEq(abv2.getStateCount(State.Registered), 3);

        address newMgr = makeAddr("newMgr");
        _mockDeployer(address(genesis[0].staking), newMgr);
        vm.prank(newMgr);
        abv2.createNode(
            genesis[0].nodeId,
            address(genesis[0].staking),
            genesis[0].rewardAddr,
            genesis[0].voterAddr,
            _makeBlsInfo(),
            "testnode",
            "",
            _signNodeIdFor(genesis[0].nodeIdPk, newMgr, genesis[0].nodeId, address(genesis[0].staking))
        );
        assertEq(abv2.getStateCount(State.Registered), 4);
    }

    /* ========== deleteNode on unknown node: reverts OnlyManager ========== */

    function test_deleteNode_revert_unknownNode() public {
        address phantom = makeAddr("phantom");
        vm.expectRevert(IAddressBookV2.OnlyManager.selector);
        vm.prank(makeAddr("anyone"));
        abv2.deleteNode(phantom);
    }

    /* ========== readyCandidate: InsufficientNodeBalance ========== */

    function test_readyCandidate_revert_insufficientNodeBalance() public {
        NodeBundle memory n = _createNode(5);

        // nodeId has no balance → InsufficientNodeBalance
        vm.expectRevert(IAddressBookV2.InsufficientNodeBalance.selector);
        vm.prank(n.nodeId);
        abv2.readyCandidate(n.nodeId);
    }

    function test_readyCandidate_success_withMinBalance() public {
        NodeBundle memory n = _createNode(5);

        vm.deal(n.nodeId, 10 ether);
        vm.prank(n.nodeId);
        abv2.readyCandidate(n.nodeId);

        assertEq(uint256(abv2.getNodeState(n.nodeId)), uint256(State.CandReady));
    }

    /* ========== assignGcId ========== */

    function test_assignGcId_success() public {
        NodeBundle memory n = _createNode(5);
        assertEq(abv2.getNodeInfo(n.nodeId).gcId, 0);

        vm.prank(owner); // owner == configurator
        abv2.assignGcId(n.nodeId);

        assertEq(abv2.getNodeInfo(n.nodeId).gcId, 101);
    }

    function test_assignGcId_incrementsSequentially() public {
        NodeBundle memory n5 = _createNode(5);
        NodeBundle memory n6 = _createNode(6);

        vm.prank(owner);
        abv2.assignGcId(n5.nodeId);

        vm.prank(owner);
        abv2.assignGcId(n6.nodeId);

        assertEq(abv2.getNodeInfo(n5.nodeId).gcId, 101);
        assertEq(abv2.getNodeInfo(n6.nodeId).gcId, 102);
    }

    function test_assignGcId_revert_NodeNotFound() public {
        vm.expectRevert(IAddressBookV2.NodeNotFound.selector);
        vm.prank(owner);
        abv2.assignGcId(makeAddr("phantom"));
    }

    function test_assignGcId_revert_GcIdAlreadyAssigned() public {
        NodeBundle memory n = _createNode(5);

        vm.prank(owner);
        abv2.assignGcId(n.nodeId);

        vm.expectRevert(IAddressBookV2.GcIdAlreadyAssigned.selector);
        vm.prank(owner);
        abv2.assignGcId(n.nodeId);
    }

    function test_assignGcId_revert_OnlyConfigurator() public {
        NodeBundle memory n = _createNode(5);
        address nonConfigurator = makeAddr("nonConfigurator");

        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonConfigurator);
        abv2.assignGcId(n.nodeId);
    }

    /* ========== revokeGcId ========== */

    function test_revokeGcId_success() public {
        NodeBundle memory n = _createNode(5);

        vm.prank(owner);
        abv2.assignGcId(n.nodeId);
        assertEq(abv2.getNodeInfo(n.nodeId).gcId, 101);

        vm.prank(owner);
        abv2.revokeGcId(n.nodeId);
        assertEq(abv2.getNodeInfo(n.nodeId).gcId, 0);
    }

    function test_revokeGcId_revert_GcIdNotAssigned() public {
        NodeBundle memory n = _createNode(5);

        vm.expectRevert(IAddressBookV2.GcIdNotAssigned.selector);
        vm.prank(owner);
        abv2.revokeGcId(n.nodeId);
    }

    function test_revokeGcId_revert_GcIdNotAssigned_unknownNode() public {
        vm.expectRevert(IAddressBookV2.GcIdNotAssigned.selector);
        vm.prank(owner);
        abv2.revokeGcId(makeAddr("phantom"));
    }

    function test_revokeGcId_revert_OnlyConfigurator() public {
        NodeBundle memory n = _createNode(5);
        address nonConfigurator = makeAddr("nonConfigurator");

        vm.expectRevert(IAddressBookV2.OnlyConfigurator.selector);
        vm.prank(nonConfigurator);
        abv2.revokeGcId(n.nodeId);
    }

    function test_isUsedAddress_voterAddress_false() public view {
        assertFalse(abv2.isUsedAddress(genesis[0].voterAddr));
    }

    /* ========== updateManager ========== */

    function test_updateManager_success() public {
        NodeBundle memory g = genesis[0];
        address newManager = makeAddr("newManager");

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.ManagerUpdated(g.nodeId, g.manager, newManager);

        vm.prank(g.manager);
        abv2.updateManager(g.nodeId, newManager);

        assertEq(abv2.getNodeInfo(g.nodeId).manager, newManager);
    }

    function test_updateManager_toSameManager() public {
        address currentManager = genesis[0].manager;

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.ManagerUpdated(genesis[0].nodeId, currentManager, currentManager);

        vm.prank(currentManager);
        abv2.updateManager(genesis[0].nodeId, currentManager);

        assertEq(abv2.getNodeInfo(genesis[0].nodeId).manager, currentManager);
    }

    function test_updateManager_thenOldManagerCannotAct() public {
        address newManager = makeAddr("newManager2");

        vm.prank(genesis[0].manager);
        abv2.updateManager(genesis[0].nodeId, newManager);

        vm.expectRevert(IAddressBookV2.OnlyManager.selector);
        vm.prank(genesis[0].manager);
        abv2.updateMetadata(genesis[0].nodeId, "test");

        vm.prank(newManager);
        abv2.updateMetadata(genesis[0].nodeId, "test");
    }

    function test_updateManager_revert_OnlyManager() public {
        address nonManager = makeAddr("nonManager");

        vm.expectRevert(IAddressBookV2.OnlyManager.selector);
        vm.prank(nonManager);
        abv2.updateManager(genesis[0].nodeId, nonManager);
    }

    function test_updateManager_revert_InvalidInput_zeroAddress() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(genesis[0].manager);
        abv2.updateManager(genesis[0].nodeId, address(0));
    }

    /* ========== updateRewardAddress ========== */

    function test_updateRewardAddress_success() public {
        NodeBundle memory g = genesis[0];
        address newReward = makeAddr("newReward");

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.RewardAddressUpdated(g.nodeId, g.rewardAddr, newReward);

        vm.prank(g.manager);
        abv2.updateRewardAddress(g.nodeId, newReward);

        NodeInfo memory info = abv2.getNodeInfo(g.nodeId);
        assertEq(info.rewardAddress, newReward);

        // Old address unregistered, new address registered
        assertFalse(abv2.isUsedAddress(g.rewardAddr));
        assertTrue(abv2.isUsedAddress(newReward));
    }

    function test_updateRewardAddress_revert_OnlyManager() public {
        address nonManager = makeAddr("nonManager");
        vm.expectRevert(IAddressBookV2.OnlyManager.selector);
        vm.prank(nonManager);
        abv2.updateRewardAddress(genesis[0].nodeId, makeAddr("newReward"));
    }

    function test_updateRewardAddress_revert_InvalidInput_zeroAddress() public {
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(genesis[0].manager);
        abv2.updateRewardAddress(genesis[0].nodeId, address(0));
    }

    function test_updateRewardAddress_revert_PDEnabled() public {
        NodeBundle memory g = genesis[0];

        // Mock publicDelegation() to return non-zero (PD is on)
        vm.mockCall(
            address(g.staking),
            abi.encodeWithSignature("publicDelegation()"),
            abi.encode(makeAddr("pdContract"))
        );

        vm.expectRevert(IAddressBookV2.PDEnabled.selector);
        vm.prank(g.manager);
        abv2.updateRewardAddress(g.nodeId, makeAddr("newReward"));
    }

    function test_updateRewardAddress_revert_AddressAlreadyRegistered() public {
        // genesis[1].rewardAddr is already registered
        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        vm.prank(genesis[0].manager);
        abv2.updateRewardAddress(genesis[0].nodeId, genesis[1].rewardAddr);
    }

    function test_updateRewardAddress_revert_collisionWithNodeId() public {
        // genesis[1].nodeId is registered
        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        vm.prank(genesis[0].manager);
        abv2.updateRewardAddress(genesis[0].nodeId, genesis[1].nodeId);
    }

    function test_updateRewardAddress_revert_collisionWithStaking() public {
        // genesis[1].staking is registered
        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        vm.prank(genesis[0].manager);
        abv2.updateRewardAddress(genesis[0].nodeId, address(genesis[1].staking));
    }

    function test_updateRewardAddress_oldAddressReusable() public {
        NodeBundle memory g0 = genesis[0];
        address oldReward = g0.rewardAddr;

        // Update genesis[0] reward to something new
        vm.prank(g0.manager);
        abv2.updateRewardAddress(g0.nodeId, makeAddr("newReward"));

        // Now genesis[1] can use the old reward address
        vm.prank(genesis[1].manager);
        abv2.updateRewardAddress(genesis[1].nodeId, oldReward);

        assertEq(abv2.getNodeInfo(genesis[1].nodeId).rewardAddress, oldReward);
    }

    /* ========== updateVoterAddress ========== */

    function test_updateVoterAddress_success() public {
        NodeBundle memory g = genesis[0];
        address newVoter = makeAddr("newVoter");

        vm.expectEmit(true, true, true, true);
        emit IAddressBookV2.VoterAddressUpdated(g.nodeId, g.voterAddr, newVoter);

        vm.prank(g.manager);
        abv2.updateVoterAddress(g.nodeId, newVoter);

        NodeInfo memory info = abv2.getNodeInfo(g.nodeId);
        assertEq(info.voterAddress, newVoter);
    }

    function test_updateVoterAddress_toZero() public {
        vm.prank(genesis[0].manager);
        abv2.updateVoterAddress(genesis[0].nodeId, address(0));

        assertEq(abv2.getNodeInfo(genesis[0].nodeId).voterAddress, address(0));
    }

    function test_updateVoterAddress_revert_OnlyManager() public {
        address nonManager = makeAddr("nonManager");
        vm.expectRevert(IAddressBookV2.OnlyManager.selector);
        vm.prank(nonManager);
        abv2.updateVoterAddress(genesis[0].nodeId, makeAddr("newVoter"));
    }

    /* ========== updateMetadata ========== */

    function test_updateMetadata_success() public {
        NodeBundle memory g = genesis[0];
        string memory newMeta = '{"name":"myNode","url":"https://example.com"}';

        vm.expectEmit(true, false, false, true);
        emit IAddressBookV2.MetadataUpdated(g.nodeId, newMeta);

        vm.prank(g.manager);
        abv2.updateMetadata(g.nodeId, newMeta);

        NodeInfo memory info = abv2.getNodeInfo(g.nodeId);
        assertEq(keccak256(bytes(info.metadata)), keccak256(bytes(newMeta)));
    }

    function test_updateMetadata_toEmpty() public {
        // First set some metadata
        vm.prank(genesis[0].manager);
        abv2.updateMetadata(genesis[0].nodeId, "some metadata");

        // Then clear it
        vm.prank(genesis[0].manager);
        abv2.updateMetadata(genesis[0].nodeId, "");

        assertEq(bytes(abv2.getNodeInfo(genesis[0].nodeId).metadata).length, 0);
    }

    function test_updateMetadata_revert_OnlyManager() public {
        address nonManager = makeAddr("nonManager");
        vm.expectRevert(IAddressBookV2.OnlyManager.selector);
        vm.prank(nonManager);
        abv2.updateMetadata(genesis[0].nodeId, "meta");
    }

    function test_updateMetadata_revert_tooLong() public {
        // MAX_METADATA_LENGTH = 2048
        string memory longMeta = new string(2049);
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(genesis[0].manager);
        abv2.updateMetadata(genesis[0].nodeId, longMeta);
    }

    function test_updateMetadata_success_atMaxLength() public {
        // Exactly MAX_METADATA_LENGTH should succeed
        bytes memory raw = new bytes(2048);
        for (uint256 i; i < 2048; i++) raw[i] = 0x41; // 'A'
        string memory maxMeta = string(raw);

        vm.prank(genesis[0].manager);
        abv2.updateMetadata(genesis[0].nodeId, maxMeta);

        assertEq(bytes(abv2.getNodeInfo(genesis[0].nodeId).metadata).length, 2048);
    }

    function test_createNode_revert_metadataTooLong() public {
        NodeBundle memory n = _makeNodeBundle(10);
        string memory longMeta = new string(2049);
        vm.expectRevert(IAddressBookV2.InvalidInput.selector);
        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", longMeta, _signNodeId(n));
    }

    function test_createNode_success_atMaxMetadataLength() public {
        NodeBundle memory n = _makeNodeBundle(10);
        bytes memory raw = new bytes(2048);
        for (uint256 i; i < 2048; i++) raw[i] = 0x41;
        string memory maxMeta = string(raw);

        vm.prank(n.manager);
        abv2.createNode(n.nodeId, address(n.staking), n.rewardAddr, n.voterAddr, _makeBlsInfo(), "testnode", maxMeta, _signNodeId(n));

        assertEq(bytes(abv2.getNodeInfo(n.nodeId).metadata).length, 2048);
    }

    /* ========== getRegisteredNodes ========== */

    function test_getRegisteredNodes_afterCreateNode() public {
        // Genesis 4 nodes are in Registered state from setUp
        uint256 baseCount = abv2.getRegisteredNodes().length;

        // Create a new node → Registered state
        NodeBundle memory n = _createNode(5);

        assertEq(abv2.getRegisteredNodes().length, baseCount + 1);
    }

    function test_getRegisteredNodes_afterDeleteNode() public {
        uint256 baseCount = abv2.getRegisteredNodes().length;

        NodeBundle memory n = _createNode(5);
        assertEq(abv2.getRegisteredNodes().length, baseCount + 1);

        // Delete the node → removed from registeredNodes
        vm.prank(n.manager);
        abv2.deleteNode(n.nodeId);

        assertEq(abv2.getRegisteredNodes().length, baseCount);
    }

    function test_getRegisteredNodes_afterReadyCandidate() public {
        uint256 baseCount = abv2.getRegisteredNodes().length;

        NodeBundle memory n = _createNode(5);
        assertEq(abv2.getRegisteredNodes().length, baseCount + 1);

        // readyCandidate: Registered → CandReady → removed from registeredNodes
        vm.deal(n.nodeId, 10 ether);
        vm.prank(n.nodeId);
        abv2.readyCandidate(n.nodeId);

        assertEq(abv2.getRegisteredNodes().length, baseCount);
    }

    function test_getRegisteredNodes_afterOffboard() public {
        _setupGenesisCommittee();

        // Exit genesis[0]: ValActive → ValExiting
        vm.prank(genesis[0].nodeId);
        abv2.exit(genesis[0].nodeId);

        // System transition: ValExiting → ValInactive
        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = genesis[0].nodeId;
        states[0] = State.ValInactive;
        timeouts[0] = 0;

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeouts, 0);

        // Offboard: ValInactive → Registered → added to registeredNodes
        vm.prank(genesis[0].nodeId);
        abv2.offboard(genesis[0].nodeId);

        address[] memory registered = abv2.getRegisteredNodes();
        assertEq(registered.length, 1);
        assertEq(registered[0], genesis[0].nodeId);
    }

    /* ========== Defense-in-depth: _createNode NodeAlreadyExists ========== */

    function _deployHarness() internal returns (AddressBookV2Harness) {
        // Deploy data contract with empty validators for harness
        IABv2DataContract.InitData memory initData = IABv2DataContract.InitData({
            initialOwner: owner,
            initialSuspender: owner,
            initialConfigurator: owner,
            pfsThreshold: DEFAULT_PFS_THRESHOLD,
            cfsThreshold: 300,
            pauseTimeout: DEFAULT_PAUSE_TIMEOUT,
            idleTimeout: DEFAULT_IDLE_TIMEOUT,
            maxNodeCount: DEFAULT_MAX_NODE_COUNT,
            maxValActivePausedCount: DEFAULT_MAX_NODE_COUNT,
            maxCandReadyCount: DEFAULT_MAX_READY_CAND_COUNT,
            kefAddress: DEFAULT_KEF_ADDRESS,
            kifAddress: DEFAULT_KIF_ADDRESS,
            kpfAddress: DEFAULT_KPF_ADDRESS,
            nodeIds: new address[](0),
            infos: new NodeInfo[](0)
        });
        ABv2DataContract dataContract = new ABv2DataContract(address(0xBEEF), initData);
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("ABv2DataContract")),
            abi.encode(address(dataContract))
        );
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("CnStakingFactory")),
            abi.encode(MOCK_FACTORY)
        );
        vm.mockCall(MOCK_FACTORY, abi.encodeWithSignature("isDeployedCnStaking(address)"), abi.encode(true));

        AddressBookV2Harness impl = new AddressBookV2Harness(EPOCH_BLOCK_INTERVAL);
        bytes memory callData = abi.encodeCall(AddressBookV2.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), callData);
        return AddressBookV2Harness(address(proxy));
    }

    /* ========== Defense-in-depth: _deleteNode InvalidState ========== */

    function test_defenseInDepth_deleteNode_invalidState() public {
        AddressBookV2Harness harness = _deployHarness();

        address nodeId = makeAddr("harness_node2");
        NodeInfo memory info = NodeInfo({
            manager: makeAddr("h_manager2"),
            stakingContract: makeAddr("h_staking2"),
            rewardAddress: makeAddr("h_reward2"),
            voterAddress: makeAddr("h_voter2"),
            timeoutAt: 0,
            gcId: 0,
            blsInfo: _makeBlsInfo(),
            name: "",
            metadata: "",
            state: State.Registered
        });

        // Create a Registered node
        harness.exposed_createNode(nodeId, info);

        // Transition to CandReady (no longer Registered)
        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeouts = new uint256[](1);
        ids[0] = nodeId;
        states[0] = State.CandReady;
        harness.exposed_batchTransition(ids, states, timeouts);

        // _deleteNode guard: state != Registered → revert
        vm.expectRevert(IAddressBookV2.InvalidState.selector);
        harness.exposed_deleteNode(nodeId);
    }
}
