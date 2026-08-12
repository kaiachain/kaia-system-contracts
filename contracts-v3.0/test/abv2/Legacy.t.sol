// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {AddressBookLegacy} from "../../src/AddressBookV2/AddressBookLegacy.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {IRegistry} from "../../src/system/IRegistry.sol";
import {MockAddressBookV1} from "../../src/AddressBookV2/mocks/MockAddressBookV1.sol";
import {MockCnStaking} from "../../src/CnStaking/mocks/MockCnStaking.sol";
import {State, BlsPublicKeyInfo, NodeInfo} from "../../src/types/Node.sol";
import {NodeIdSigUtil} from "../base/NodeIdSigUtil.sol";

/// @dev Interface for deprecated legacy functions removed from AddressBookLegacy.
///      Used only in tests to encode correct selectors for fallback revert verification.
interface ILegacyDeprecated {
    function constructContract(address[] calldata, uint256) external;
    function submitAddAdmin(address) external;
    function submitDeleteAdmin(address) external;
    function submitUpdateRequirement(uint256) external;
    function submitClearRequest() external;
    function submitActivateAddressBook() external;
    function submitUpdatePocContract(address, uint256) external;
    function submitUpdateKirContract(address, uint256) external;
    function submitUpdateSpareContract(address) external;
    function submitRegisterCnStakingContract(address, address, address) external;
    function submitUnregisterCnStakingContract(address) external;
    function revokeRequest(AddressBookLegacy.Functions, bytes32, bytes32, bytes32) external;
    function reviseRewardAddress(address) external;
    function addAdmin(address) external;
    function deleteAdmin(address) external;
    function updateRequirement(uint256) external;
    function clearRequest() external;
    function activateAddressBook() external;
    function updatePocContract(address, uint256) external;
    function updateKirContract(address, uint256) external;
    function updateSpareContract(address) external;
    function registerCnStakingContract(address, address, address) external;
    function unregisterCnStakingContract(address) external;
}

/// @title LegacyCompatibilityTest
/// @notice Tests backward compatibility with the original AddressBook (v1) at 0x400.
///         Uses MockAddressBookV1 to populate legacy storage before upgrading to ABv2,
///         then verifies all legacy getters return correct data.
contract LegacyCompatibilityTest is Test {
    /* ========== CONSTANTS ========== */

    address internal constant ABV2_ADDRESS = address(0x400);
    address internal constant REGISTRY_ADDRESS = address(0x401);
    bytes32 internal constant ERC1967_IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    uint256 internal constant MIN_STAKE = 5_000_000 ether;
    address internal constant SYSTEM_SENDER = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
    uint256 internal constant EPOCH_BLOCK_INTERVAL = 86_400;

    // Legacy data
    address internal constant LEGACY_POC = address(0xCAFE01);
    address internal constant LEGACY_KIR = address(0xCAFE02);
    address internal constant LEGACY_SPARE = address(0xCAFE03);
    address internal constant LEGACY_ADMIN1 = address(0xAD01);
    address internal constant LEGACY_ADMIN2 = address(0xAD02);
    address internal constant LEGACY_ADMIN3 = address(0xAD03);

    // Legacy CN data (will be overridden by ABv2 live data after upgrade)
    address internal constant LEGACY_CN_NODE1 = address(0xCE01);
    address internal constant LEGACY_CN_STAKING1 = address(0xCE11);
    address internal constant LEGACY_CN_REWARD1 = address(0xCE21);
    address internal constant LEGACY_CN_NODE2 = address(0xCE02);
    address internal constant LEGACY_CN_STAKING2 = address(0xCE12);
    address internal constant LEGACY_CN_REWARD2 = address(0xCE22);

    /* ========== STATE ========== */

    address internal owner;
    AddressBookV2 internal abv2;
    MockAddressBookV1 internal mockV1;

    /* ========== SETUP: Simulates the full upgrade path ========== */

    function setUp() public {
        owner = makeAddr("owner");

        // Step 1: Deploy MockAddressBookV1 and etch to 0x400 (simulating the original AB at genesis)
        MockAddressBookV1 mockImpl = new MockAddressBookV1();
        vm.etch(ABV2_ADDRESS, address(mockImpl).code);
        mockV1 = MockAddressBookV1(ABV2_ADDRESS);

        // Step 2: Populate legacy storage via mock setters
        address[] memory admins = new address[](3);
        admins[0] = LEGACY_ADMIN1;
        admins[1] = LEGACY_ADMIN2;
        admins[2] = LEGACY_ADMIN3;
        mockV1.mockSetAdmins(admins, 2); // 2-of-3 multisig
        mockV1.mockSetContracts(LEGACY_POC, LEGACY_KIR, LEGACY_SPARE);
        mockV1.mockRegisterCn(LEGACY_CN_NODE1, LEGACY_CN_STAKING1, LEGACY_CN_REWARD1);
        mockV1.mockRegisterCn(LEGACY_CN_NODE2, LEGACY_CN_STAKING2, LEGACY_CN_REWARD2);
        mockV1.mockActivate();

        // Add a mock pending request
        mockV1.mockAddRequest(
            MockAddressBookV1.Functions.AddAdmin,
            bytes32(uint256(uint160(makeAddr("newAdmin")))),
            bytes32(0),
            bytes32(0),
            LEGACY_ADMIN1
        );

        // Verify mock data is populated correctly before upgrade
        assertEq(mockV1.requirement(), 2, "pre-upgrade: requirement should be 2");
        assertTrue(mockV1.isActivated(), "pre-upgrade: should be activated");
        assertEq(mockV1.mockGetCnNodeIdList().length, 2, "pre-upgrade: should have 2 CNs");
        assertEq(mockV1.mockGetPendingRequestList().length, 1, "pre-upgrade: should have 1 pending request");

        // Step 3: Upgrade to ABv2 — deploy impl, overlay proxy bytecode, set storage
        _upgradeToABv2();
    }

    /* ========== UPGRADE HELPERS ========== */

    function _upgradeToABv2() internal {
        // Mock CnStakingFactory in registry (needed by NodeVerifier in ABv2DataContract constructor)
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("CnStakingFactory")),
            abi.encode(address(0x501))
        );
        vm.mockCall(address(0x501), abi.encodeWithSignature("isDeployedCnStaking(address)"), abi.encode(true));
        vm.mockCall(address(0x501), abi.encodeWithSignature("isDeployedPublicDelegation(address)"), abi.encode(false));
        // Default getDeployer mock — returns address(0).
        // Tests that call createNode must override this per staking contract.
        vm.mockCall(address(0x501), abi.encodeWithSignature("getDeployer(address)"), abi.encode(address(0)));

        // Deploy ABv2DataContract with genesis config (no initial validators)
        IABv2DataContract.InitData memory initData = IABv2DataContract.InitData({
            initialOwner: owner,
            initialSuspender: owner,
            initialConfigurator: owner,
            pfsThreshold: 2,
            cfsThreshold: 300,
            pauseTimeout: 8 hours,
            idleTimeout: 7 days,
            maxNodeCount: 100,
            maxValActivePausedCount: 100,
            maxCandReadyCount: 2,
            kefAddress: makeAddr("kef"),
            kifAddress: makeAddr("kif"),
            kpfAddress: makeAddr("kpf"),
            nodeIds: new address[](0),
            infos: new NodeInfo[](0)
        });
        ABv2DataContract dataContract = new ABv2DataContract(address(0xBEEF), initData);

        // Mock Registry at 0x401 to return our data contract
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("ABv2DataContract")),
            abi.encode(address(dataContract))
        );

        // Deploy ABv2 implementation
        AddressBookV2 impl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);

        // Deploy temp proxy to capture ERC1967Proxy runtime bytecode
        bytes memory dummyInit = abi.encodeCall(AddressBookV2.initialize, ());
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(impl), dummyInit);

        // Overlay proxy bytecode at 0x400 (preserves storage!)
        vm.etch(ABV2_ADDRESS, address(tempProxy).code);

        // Set ERC-1967 implementation slot
        vm.store(ABV2_ADDRESS, ERC1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));

        // Initialize the proxy
        abv2 = AddressBookV2(ABV2_ADDRESS);
        abv2.initialize();
    }

    /* ========== MOCK HELPERS ========== */

    function _mockDeployer(address stakingContract, address deployer) internal {
        vm.mockCall(
            address(0x501),
            abi.encodeWithSignature("getDeployer(address)", stakingContract),
            abi.encode(deployer)
        );
    }

    /* ========== NODE HELPERS ========== */

    function _makeBlsInfo() internal pure returns (BlsPublicKeyInfo memory) {
        bytes memory pk = new bytes(48);
        pk[0] = 0x01;
        bytes memory pop = new bytes(96);
        pop[0] = 0x01;
        return BlsPublicKeyInfo({publicKey: pk, pop: pop});
    }

    function _createNode(string memory name) internal returns (address nodeId, MockCnStaking staking, address reward) {
        uint256 nodeIdPk;
        (nodeId, nodeIdPk) = makeAddrAndKey(string.concat(name, "_node"));
        address manager = makeAddr(string.concat(name, "_manager"));
        staking = new MockCnStaking();
        staking.mockSetStaking(MIN_STAKE);
        reward = makeAddr(string.concat(name, "_reward"));

        _mockDeployer(address(staking), manager);
        bytes memory sig = _signNodeIdFor(nodeIdPk, manager, nodeId, address(staking));
        vm.prank(manager);
        abv2.createNode(
            nodeId,
            address(staking),
            reward,
            makeAddr(string.concat(name, "_voter")),
            _makeBlsInfo(),
            name,
            "",
            sig
        );
    }

    /// @dev Produces the nodeId ownership signature that createNode requires: an ECDSA
    ///      signature by nodeId over (caller, nodeId, stakingContract, chainId, addressBook).
    function _signNodeIdFor(uint256 nodeIdPk, address caller, address nodeId, address staking)
        internal
        view
        returns (bytes memory)
    {
        return NodeIdSigUtil.sign(nodeIdPk, caller, nodeId, staking, address(abv2));
    }

    function _rollToNextEpoch() internal {
        vm.roll(block.number - (block.number % EPOCH_BLOCK_INTERVAL) + EPOCH_BLOCK_INTERVAL);
    }

    function _createActiveNode(
        string memory name
    ) internal returns (address nodeId, MockCnStaking staking, address reward) {
        (nodeId, staking, reward) = _createNode(name);

        // Registered → CandReady
        vm.deal(nodeId, 10 ether);
        vm.prank(nodeId);
        abv2.readyCandidate(nodeId);

        // CandReady → ValActive (system transition at epoch)
        address[] memory ids = new address[](1);
        State[] memory states = new State[](1);
        uint256[] memory timeoutAts = new uint256[](1);
        ids[0] = nodeId;
        states[0] = State.ValActive;

        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(ids, states, timeoutAts, 0);
    }

    /* ========== TESTS: getState() ========== */

    function test_legacy_getState_returnsOwnerAnd1() public view {
        (address[] memory admins, uint256 req) = abv2.getState();
        assertEq(admins.length, 1, "should return single admin");
        assertEq(admins[0], owner, "admin should be owner");
        assertEq(req, 1, "requirement should be 1");
    }

    function test_legacy_getState_updatesWhenOwnerChanges() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        abv2.transferOwnership(newOwner);

        (address[] memory admins, uint256 req) = abv2.getState();
        assertEq(admins[0], newOwner, "admin should be new owner");
        assertEq(req, 1, "requirement should still be 1");
    }

    function test_legacy_getState_coexistsWithGetNodeState() public {
        // getState() = legacy → (address[], uint256)
        // getNodeState(address) = ABv2 → State
        (address[] memory admins, uint256 req) = abv2.getState();
        assertEq(admins.length, 1);
        assertEq(req, 1);
        // getNodeState(address) should return Unknown for any address (no nodes created yet)
        State state = abv2.getNodeState(makeAddr("random"));
        assertEq(uint256(state), uint256(State.Unknown));
    }

    /* ========== TESTS: requirement() ========== */

    function test_legacy_requirement_returns1_despiteFrozenValue() public view {
        // The old storage has requirement=2 (set via mockV1), but the override returns 1
        assertEq(abv2.requirement(), 1, "requirement should return 1 regardless of frozen storage");
    }

    /* ========== TESTS: Frozen public variable getters ========== */

    function test_legacy_pocContractAddress_readsFrozenStorage() public view {
        assertEq(abv2.pocContractAddress(), LEGACY_POC, "poc address should match frozen storage");
    }

    function test_legacy_kirContractAddress_readsFrozenStorage() public view {
        assertEq(abv2.kirContractAddress(), LEGACY_KIR, "kir address should match frozen storage");
    }

    function test_legacy_spareContractAddress_readsFrozenStorage() public view {
        assertEq(abv2.spareContractAddress(), LEGACY_SPARE, "spare address should match frozen storage");
    }

    function test_legacy_isActivated_readsFrozenStorage() public view {
        assertTrue(abv2.isActivated(), "isActivated should be true");
    }

    function test_legacy_isConstructed_readsFrozenStorage() public view {
        assertTrue(abv2.isConstructed(), "isConstructed should be true");
    }

    /* ========== TESTS: Constants ========== */

    function test_legacy_constants() public view {
        assertEq(abv2.VERSION(), 2);
        assertEq(keccak256(bytes(abv2.CONTRACT_TYPE())), keccak256(bytes("AddressBook")));
    }

    /* ========== TESTS: CN-related live data getters ========== */

    function test_legacy_getAllAddress_returnsLiveData_noNodes() public {
        // After upgrade, ABv2's ABv2Storage has no nodes (legacy CN data is frozen in old slots 9-11).
        // getAllAddress reads from ABv2 live storage, so it should return 0 CN entries + poc/kir.
        (uint8[] memory typeList, address[] memory addressList) = abv2.getAllAddress();

        // 0 nodes * 3 + 2 (poc + kir) = 2
        assertEq(typeList.length, 2, "should only have poc and kir");
        assertEq(typeList[0], 3, "poc type");
        assertEq(addressList[0], makeAddr("kif"), "poc returns live KIF address");
        assertEq(typeList[1], 4, "kir type");
        assertEq(addressList[1], makeAddr("kef"), "kir returns live KEF address");
    }

    function test_legacy_getAllAddress_returnsLiveData_withActiveNodes() public {
        // Only active-set nodes appear in getAllAddress (Registered excluded)
        (address nodeId1, MockCnStaking staking1, address reward1) = _createActiveNode("n1");
        (address nodeId2, , ) = _createActiveNode("n2");

        (uint8[] memory typeList, address[] memory addressList) = abv2.getAllAddress();

        // 2 active nodes * 3 + 2 = 8
        assertEq(typeList.length, 8, "should have 2*3+2 entries");

        // Find node1 in the results (order depends on set iteration)
        bool foundNode1 = false;
        bool foundNode2 = false;
        for (uint256 i = 0; i < typeList.length - 2; i += 3) {
            if (addressList[i] == nodeId1) {
                foundNode1 = true;
                assertEq(typeList[i], 0, "CN_NODE_ID_TYPE");
                assertEq(addressList[i + 1], address(staking1), "staking1");
                assertEq(typeList[i + 1], 1, "CN_STAKING_ADDRESS_TYPE");
                assertEq(addressList[i + 2], reward1, "reward1");
                assertEq(typeList[i + 2], 2, "CN_REWARD_ADDRESS_TYPE");
            }
            if (addressList[i] == nodeId2) {
                foundNode2 = true;
            }
        }
        assertTrue(foundNode1, "node1 should be in results");
        assertTrue(foundNode2, "node2 should be in results");

        // poc/kir at the end (live KIF/KEF from ABv2 storage)
        assertEq(addressList[6], makeAddr("kif"), "poc returns live KIF address");
        assertEq(addressList[7], makeAddr("kef"), "kir returns live KEF address");
    }

    function test_legacy_getAllAddress_excludesRegistered() public {
        // Registered nodes should NOT appear in getAllAddress
        _createNode("n1");
        _createNode("n2");

        (uint8[] memory typeList, address[] memory addressList) = abv2.getAllAddress();

        // 0 active nodes * 3 + 2 (poc + kir) = 2
        assertEq(typeList.length, 2, "Registered nodes should not appear");
        assertEq(addressList.length, 2);
        assertEq(typeList[0], 3, "poc type");
        assertEq(typeList[1], 4, "kir type");
    }

    function test_legacy_getAllAddress_returnsEmptyWhenNotActivated() public {
        // Set isActivated to false via vm.store (slot 12)
        vm.store(address(abv2), bytes32(uint256(12)), bytes32(0));
        assertFalse(abv2.isActivated());

        // Even though ABv2 has live nodes, the legacy isActivated guard returns empty
        _createNode("n1");

        (uint8[] memory typeList, address[] memory addressList) = abv2.getAllAddress();
        assertEq(typeList.length, 0, "should be empty when not activated");
        assertEq(addressList.length, 0, "should be empty when not activated");
    }

    function test_legacy_getAllAddressInfo_returnsLiveData() public {
        (address nodeId1, MockCnStaking staking1, address reward1) = _createActiveNode("n1");

        (
            address[] memory nodeIds,
            address[] memory stakingContracts,
            address[] memory rewardAddresses,
            address poc,
            address kir
        ) = abv2.getAllAddressInfo();

        assertEq(nodeIds.length, 1, "should have 1 active node");
        assertEq(nodeIds[0], nodeId1);
        assertEq(stakingContracts[0], address(staking1));
        assertEq(rewardAddresses[0], reward1);
        assertEq(poc, makeAddr("kif"), "poc returns live KIF address");
        assertEq(kir, makeAddr("kef"), "kir returns live KEF address");
    }

    function test_legacy_getAllAddressInfo_excludesRegistered() public {
        _createNode("n1");

        (address[] memory nodeIds, , , address poc, address kir) = abv2.getAllAddressInfo();

        assertEq(nodeIds.length, 0, "Registered nodes should not appear");
        assertEq(poc, makeAddr("kif"));
        assertEq(kir, makeAddr("kef"));
    }

    function test_legacy_getCnInfo_returnsLiveData() public {
        (address nodeId1, MockCnStaking staking1, address reward1) = _createNode("n1");

        (address nid, address staking, address reward) = abv2.getCnInfo(nodeId1);
        assertEq(nid, nodeId1);
        assertEq(staking, address(staking1));
        assertEq(reward, reward1);
    }

    function test_legacy_getCnInfo_revertsForUnknownNode() public {
        vm.expectRevert(AddressBookLegacy.CnNodeNotFound.selector);
        abv2.getCnInfo(makeAddr("unknownNode"));
    }

    function test_legacy_getAllAddress_onlyIncludesActiveSet() public {
        // Registered nodes don't appear
        _createNode("n1");
        (uint8[] memory typeList, ) = abv2.getAllAddress();
        assertEq(typeList.length, 2, "Registered should not appear, only poc+kir");

        // After activating to ValActive, node appears
        _createActiveNode("n2");
        (typeList, ) = abv2.getAllAddress();
        assertEq(typeList.length, 5, "1 active node * 3 + 2 = 5");
    }

    /* ========== TESTS: Deprecated mutators (hit fallback) ========== */

    function test_legacy_constructContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        address[] memory admins = new address[](1);
        admins[0] = makeAddr("admin");
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.constructContract(admins, 1);
    }

    function test_legacy_submitAddAdmin_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitAddAdmin(makeAddr("admin"));
    }

    function test_legacy_submitDeleteAdmin_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitDeleteAdmin(makeAddr("admin"));
    }

    function test_legacy_submitUpdateRequirement_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitUpdateRequirement(2);
    }

    function test_legacy_submitClearRequest_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitClearRequest();
    }

    function test_legacy_submitActivateAddressBook_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitActivateAddressBook();
    }

    function test_legacy_submitUpdatePocContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitUpdatePocContract(makeAddr("poc"), 1);
    }

    function test_legacy_submitUpdateKirContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitUpdateKirContract(makeAddr("kir"), 1);
    }

    function test_legacy_submitUpdateSpareContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitUpdateSpareContract(makeAddr("spare"));
    }

    function test_legacy_submitRegisterCnStakingContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitRegisterCnStakingContract(makeAddr("n"), makeAddr("s"), makeAddr("r"));
    }

    function test_legacy_submitUnregisterCnStakingContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.submitUnregisterCnStakingContract(makeAddr("n"));
    }

    function test_legacy_revokeRequest_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.revokeRequest(AddressBookLegacy.Functions.AddAdmin, bytes32(0), bytes32(0), bytes32(0));
    }

    function test_legacy_reviseRewardAddress_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.reviseRewardAddress(makeAddr("reward"));
    }

    function test_legacy_addAdmin_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.addAdmin(makeAddr("admin"));
    }

    function test_legacy_deleteAdmin_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.deleteAdmin(makeAddr("admin"));
    }

    function test_legacy_updateRequirement_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.updateRequirement(2);
    }

    function test_legacy_clearRequest_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.clearRequest();
    }

    function test_legacy_activateAddressBook_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.activateAddressBook();
    }

    function test_legacy_updatePocContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.updatePocContract(makeAddr("poc"), 1);
    }

    function test_legacy_updateKirContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.updateKirContract(makeAddr("kir"), 1);
    }

    function test_legacy_updateSpareContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.updateSpareContract(makeAddr("spare"));
    }

    function test_legacy_registerCnStakingContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.registerCnStakingContract(makeAddr("n"), makeAddr("s"), makeAddr("r"));
    }

    function test_legacy_unregisterCnStakingContract_reverts() public {
        ILegacyDeprecated legacy = ILegacyDeprecated(address(abv2));
        vm.expectRevert(AddressBookLegacy.LegacyFunctionDeprecated.selector);
        legacy.unregisterCnStakingContract(makeAddr("n"));
    }

    /* ========== TESTS: ABv2 functions still work alongside legacy ========== */

    function test_legacy_newABv2FunctionsStillWork() public {
        (address nodeId1, , ) = _createNode("n1");

        // New ABv2 getters should work alongside legacy getters
        State state = abv2.getNodeState(nodeId1);
        assertEq(uint256(state), uint256(State.Registered));

        NodeInfo memory info = abv2.getNodeInfo(nodeId1);
        assertEq(uint256(info.state), uint256(State.Registered));

        assertEq(abv2.getStateCount(State.Registered), 1);
        assertEq(abv2.getAllNodesLength(), 0);
    }
}
