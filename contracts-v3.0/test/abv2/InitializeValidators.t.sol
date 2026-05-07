// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DeployHelpers} from "../base/DeployHelpers.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IRegistry} from "../../src/system/IRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NodeVerifier} from "../../src/libraries/NodeVerifier.sol";
import {State, NodeInfo, BlsPublicKeyInfo} from "../../src/types/Node.sol";
import {MockCnStaking} from "../../src/CnStaking/mocks/MockCnStaking.sol";

/// @title InitializeValidatorsTest
/// @notice Tests for ABv2 initialization via ABv2DataContract — genesis validator setup.
///         Uses a clean deployment to simulate real genesis with data contract pattern.
contract InitializeValidatorsTest is DeployHelpers {
    address internal owner;

    function setUp() public {
        owner = makeAddr("owner");

        // Mock CnStakingFactory in registry (needed by NodeVerifier in ABv2DataContract constructor)
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("CnStakingFactory")),
            abi.encode(MOCK_FACTORY)
        );
        vm.mockCall(MOCK_FACTORY, abi.encodeWithSignature("isDeployedCnStaking(address)"), abi.encode(true));
    }

    /* ========== HELPERS ========== */

    /// @notice Builds InitData with N genesis validators
    function _buildInitData(uint256 count) internal returns (IABv2DataContract.InitData memory data) {
        address[] memory nodeIds = new address[](count);
        NodeInfo[] memory infos = new NodeInfo[](count);

        for (uint256 i; i < count; i++) {
            string memory idx = vm.toString(i + 1);
            nodeIds[i] = makeAddr(string.concat("gnode", idx));
            address manager = makeAddr(string.concat("gmanager", idx));

            MockCnStaking staking = deployMockCnStaking(MIN_STAKE, 0);
            address rewardAddr = makeAddr(string.concat("greward", idx));
            address voterAddr = makeAddr(string.concat("gvoter", idx));

            infos[i] = NodeInfo({
                manager: manager,
                stakingContract: address(staking),
                rewardAddress: rewardAddr,
                voterAddress: voterAddr,
                timeoutAt: 0,
                gcId: 0,
                blsInfo: _makeBlsInfo(),
                name: "",
                metadata: "",
                state: State.Unknown
            });
        }

        data = IABv2DataContract.InitData({
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
            kefAddress: makeAddr("kef"),
            kifAddress: makeAddr("kif"),
            kpfAddress: makeAddr("kpf"),
            nodeIds: nodeIds,
            infos: infos
        });
    }

    /* ========== HAPPY PATH: INITIALIZE VIA DATA CONTRACT ========== */

    function test_initialize_success_4validators() public {
        IABv2DataContract.InitData memory data = _buildInitData(4);
        deployAddressBookV2WithValidators(data);

        for (uint256 i; i < 4; i++) {
            assertEq(uint256(abv2.getNodeState(data.nodeIds[i])), uint256(State.ValActive));
            assertTrue(abv2.getNodeState(data.nodeIds[i]) != State.Registered);
        }

        assertEq(abv2.getStateCount(State.ValActive), 4);
        assertEq(abv2.getStateCount(State.Registered), 0);
        assertEq(abv2.getAllNodesLength(), 4);
        assertEq(abv2.getStateCount(State.Registered), 0);
    }

    function test_initialize_success_managersStored() public {
        IABv2DataContract.InitData memory data = _buildInitData(3);
        deployAddressBookV2WithValidators(data);

        for (uint256 i; i < 3; i++) {
            assertEq(abv2.getNodeInfo(data.nodeIds[i]).manager, data.infos[i].manager);
        }
    }

    function test_initialize_success_addressesRegistered() public {
        IABv2DataContract.InitData memory data = _buildInitData(2);
        deployAddressBookV2WithValidators(data);

        for (uint256 i; i < 2; i++) {
            assertTrue(abv2.isUsedAddress(data.nodeIds[i]));
            assertTrue(abv2.isUsedAddress(data.infos[i].stakingContract));
            assertTrue(abv2.isUsedAddress(data.infos[i].rewardAddress));
        }
    }

    function test_initialize_success_epochVACountSet() public {
        IABv2DataContract.InitData memory data = _buildInitData(4);
        deployAddressBookV2WithValidators(data);

        assertEq(abv2.getEpochVACount(), 4);
    }

    function test_initialize_success_emitsEvent() public {
        IABv2DataContract.InitData memory data = _buildInitData(2);

        // Deploy data contract and mock registry
        ABv2DataContract dataContract = new ABv2DataContract(address(0xBEEF), data);
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("ABv2DataContract")),
            abi.encode(address(dataContract))
        );

        // Deploy and initialize (the etch + initialize at 0x400)
        _deployProxyAndInitialize();
    }

    function test_initialize_success_nodeInfoStored() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        deployAddressBookV2WithValidators(data);

        NodeInfo memory stored = abv2.getNodeInfo(data.nodeIds[0]);
        assertEq(stored.stakingContract, data.infos[0].stakingContract);
        assertEq(stored.rewardAddress, data.infos[0].rewardAddress);
        assertEq(stored.voterAddress, data.infos[0].voterAddress);
        assertEq(uint256(stored.state), uint256(State.ValActive));
        assertEq(stored.timeoutAt, 0);
        assertEq(stored.gcId, 0); // gcId preserved from data contract (default 0)
    }

    function test_initialize_success_gcIdsFromDataContract() public {
        IABv2DataContract.InitData memory data = _buildInitData(3);
        // Set specific gcIds in data — should be preserved as-is
        data.infos[0].gcId = 10;
        data.infos[1].gcId = 20;
        data.infos[2].gcId = 30;
        deployAddressBookV2WithValidators(data);

        for (uint256 i; i < 3; i++) {
            NodeInfo memory stored = abv2.getNodeInfo(data.nodeIds[i]);
            assertEq(stored.gcId, data.infos[i].gcId);
        }
    }

    function test_initialize_success_singleValidator() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        deployAddressBookV2WithValidators(data);

        assertEq(uint256(abv2.getNodeState(data.nodeIds[0])), uint256(State.ValActive));
        assertEq(abv2.getStateCount(State.ValActive), 1);
        assertEq(abv2.getAllNodesLength(), 1);
    }

    function test_initialize_success_emptyValidators() public {
        IABv2DataContract.InitData memory data = _buildInitData(0);
        deployAddressBookV2WithValidators(data);

        assertEq(abv2.getAllNodesLength(), 0);
    }

    function test_initialize_success_configsSet() public {
        IABv2DataContract.InitData memory data = _buildInitData(0);
        deployAddressBookV2WithValidators(data);

        (uint256 pauseTimeout, uint256 idleTimeout) = abv2.getTimeouts();
        assertEq(pauseTimeout, DEFAULT_PAUSE_TIMEOUT);
        assertEq(idleTimeout, DEFAULT_IDLE_TIMEOUT);

        (uint256 maxValCount, uint256 maxReadyCandCount) = abv2.getMaxCounts();
        assertEq(maxValCount, DEFAULT_MAX_NODE_COUNT);
        assertEq(maxReadyCandCount, DEFAULT_MAX_READY_CAND_COUNT);
        assertEq(abv2.getMaxValActivePausedCount(), DEFAULT_MAX_NODE_COUNT);

        assertEq(abv2.getPfsThreshold(), DEFAULT_PFS_THRESHOLD);

        (address kef, address kif, address kpf) = abv2.getFundAddresses();
        assertEq(kef, makeAddr("kef"));
        assertEq(kif, makeAddr("kif"));
        assertEq(kpf, makeAddr("kpf"));
    }

    function test_initialize_success_ownerSet() public {
        IABv2DataContract.InitData memory data = _buildInitData(0);
        deployAddressBookV2WithValidators(data);

        assertEq(abv2.owner(), owner);
    }

    /* ========== POST-INIT: CREATE NODE STILL WORKS ========== */

    function test_initialize_doesNotBlockCreateNode() public {
        IABv2DataContract.InitData memory data = _buildInitData(2);
        deployAddressBookV2WithValidators(data);

        address newNode = makeAddr("newnode");
        address newManager = makeAddr("newmanager");
        MockCnStaking newStaking = deployMockCnStaking(MIN_STAKE, 0);
        address newReward = makeAddr("newreward");
        address newVoter = makeAddr("newvoter");

        _mockDeployer(address(newStaking), newManager);
        vm.prank(newManager);
        abv2.createNode(newNode, address(newStaking), newReward, newVoter, _makeBlsInfo(), "newnode", "");

        assertEq(uint256(abv2.getNodeState(newNode)), uint256(State.Registered));
        assertEq(abv2.getNodeInfo(newNode).manager, newManager);
    }

    function test_initialize_postInitNodeGetsNoGcId() public {
        IABv2DataContract.InitData memory data = _buildInitData(3);
        deployAddressBookV2WithValidators(data);

        // Genesis validators keep gcIds from data contract (0 by default)
        for (uint256 i; i < 3; i++) {
            NodeInfo memory stored = abv2.getNodeInfo(data.nodeIds[i]);
            assertEq(stored.gcId, 0);
        }

        // Create a new node — gcId is NOT auto-assigned at creation (must call assignGcId)
        address newNode = makeAddr("newnode");
        address newManager = makeAddr("newmanager");
        MockCnStaking newStaking = deployMockCnStaking(MIN_STAKE, 0);
        address newReward = makeAddr("newreward");
        address newVoter = makeAddr("newvoter");

        _mockDeployer(address(newStaking), newManager);
        vm.prank(newManager);
        abv2.createNode(newNode, address(newStaking), newReward, newVoter, _makeBlsInfo(), "newnode", "");

        NodeInfo memory newInfo = abv2.getNodeInfo(newNode);
        assertEq(newInfo.gcId, 0, "post-init node should have gcId=0 until assignGcId is called");
    }

    /* ========== ABV2 DATA CONTRACT: CONSTRUCTOR VALIDATION ========== */

    function test_dataContract_revert_zeroOwner() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.initialOwner = address(0);

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroSuspender() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.initialSuspender = address(0);

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroConfigurator() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.initialConfigurator = address(0);

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroPfsThreshold() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.pfsThreshold = 0;

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroPauseTimeout() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.pauseTimeout = 0;

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroIdleTimeout() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.idleTimeout = 0;

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroMaxNodeCount() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.maxNodeCount = 0;

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroMaxValActivePausedCount() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.maxValActivePausedCount = 0;

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroMaxCandReadyCount() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.maxCandReadyCount = 0;

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroKefAddress() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.kefAddress = address(0);

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroKifAddress() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.kifAddress = address(0);

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroKpfAddress() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.kpfAddress = address(0);

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_mismatchedArrays() public {
        IABv2DataContract.InitData memory data = _buildInitData(2);
        // Shorten infos array
        NodeInfo[] memory shortInfos = new NodeInfo[](1);
        shortInfos[0] = data.infos[0];
        data.infos = shortInfos;

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroManager() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].manager = address(0);

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroNodeId() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.nodeIds[0] = address(0);

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroStakingContract() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].stakingContract = address(0);

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_zeroRewardAddress() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].rewardAddress = address(0);

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_blsPublicKeyWrongSize() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].blsInfo.publicKey = new bytes(32);

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_blsPublicKeyZero() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].blsInfo.publicKey = new bytes(48); // all zeros

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_blsPopWrongSize() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].blsInfo.pop = new bytes(48);

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_blsPopZero() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].blsInfo.pop = new bytes(96); // all zeros

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_duplicateAddressesCrossNode() public {
        IABv2DataContract.InitData memory data = _buildInitData(2);
        address dupAddr = data.infos[0].rewardAddress;
        data.infos[1].stakingContract = dupAddr;
        // Mock nodeId() and publicDelegation() on the replacement staking address
        vm.mockCall(dupAddr, abi.encodeWithSignature("nodeId()"), abi.encode(data.nodeIds[1]));
        vm.mockCall(dupAddr, abi.encodeWithSignature("publicDelegation()"), abi.encode(address(0)));

        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_duplicateNodeId() public {
        IABv2DataContract.InitData memory data = _buildInitData(2);
        data.nodeIds[1] = data.nodeIds[0];

        vm.expectRevert(NodeVerifier.AddressAlreadyRegistered.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_nodeIdEqualsStaking() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].stakingContract = data.nodeIds[0];

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_nodeIdEqualsReward() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].rewardAddress = data.nodeIds[0];

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    function test_dataContract_revert_stakingEqualsReward() public {
        IABv2DataContract.InitData memory data = _buildInitData(1);
        data.infos[0].rewardAddress = data.infos[0].stakingContract;

        vm.expectRevert(NodeVerifier.InvalidInput.selector);
        new ABv2DataContract(address(0xBEEF), data);
    }

    /* ========== ABV2 DATA CONTRACT: getInitData() / implementation() ========== */

    function test_dataContract_implementation_returnsCorrectAddress() public {
        IABv2DataContract.InitData memory data = _buildInitData(0);
        address implAddr = makeAddr("implAddr");
        ABv2DataContract dc = new ABv2DataContract(implAddr, data);

        assertEq(dc.implementation(), implAddr);
    }

    function test_dataContract_revert_zeroImplementation() public {
        IABv2DataContract.InitData memory data = _buildInitData(0);

        vm.expectRevert(ABv2DataContract.InvalidInput.selector);
        new ABv2DataContract(address(0), data);
    }

    function test_dataContract_getInitData_returnsCorrectData() public {
        IABv2DataContract.InitData memory data = _buildInitData(2);
        ABv2DataContract dc = new ABv2DataContract(address(0xBEEF), data);

        IABv2DataContract.InitData memory result = dc.getInitData();

        assertEq(result.initialOwner, data.initialOwner);
        assertEq(result.pfsThreshold, data.pfsThreshold);
        assertEq(result.pauseTimeout, data.pauseTimeout);
        assertEq(result.idleTimeout, data.idleTimeout);
        assertEq(result.maxNodeCount, data.maxNodeCount);
        assertEq(result.maxCandReadyCount, data.maxCandReadyCount);
        assertEq(result.kefAddress, data.kefAddress);
        assertEq(result.kifAddress, data.kifAddress);
        assertEq(result.kpfAddress, data.kpfAddress);
        assertEq(result.nodeIds.length, 2);
        assertEq(result.infos.length, 2);

        for (uint256 i; i < 2; i++) {
            assertEq(result.nodeIds[i], data.nodeIds[i]);
            assertEq(result.infos[i].manager, data.infos[i].manager);
            assertEq(result.infos[i].stakingContract, data.infos[i].stakingContract);
            assertEq(result.infos[i].rewardAddress, data.infos[i].rewardAddress);
        }
    }

    /* ========== INITIALIZE REVERT: NotInitializable ========== */

    function test_initialize_revert_notInitializable() public {
        // First deploy with a valid data contract so the temp proxy can initialize
        IABv2DataContract.InitData memory data = _buildInitData(0);
        ABv2DataContract dataContract = new ABv2DataContract(address(0xBEEF), data);
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("ABv2DataContract")),
            abi.encode(address(dataContract))
        );

        AddressBookV2 impl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);
        bytes memory initCall = abi.encodeCall(AddressBookV2.initialize, ());
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(impl), initCall);

        vm.etch(ABV2_ADDRESS, address(tempProxy).code);
        vm.store(ABV2_ADDRESS, ERC1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));
        abv2 = AddressBookV2(ABV2_ADDRESS);

        // Now mock Registry to return address(0) so initialize() reverts
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("ABv2DataContract")),
            abi.encode(address(0))
        );

        vm.expectRevert(IAddressBookV2.NotInitializable.selector);
        abv2.initialize();
    }

    /* ========== INTERNAL HELPERS ========== */

    /// @dev Deploys proxy at 0x400 and calls initialize — for use when data contract
    ///      and registry mock are already set up externally.
    function _deployProxyAndInitialize() private {
        AddressBookV2 impl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);
        bytes memory initCall = abi.encodeCall(AddressBookV2.initialize, ());
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(impl), initCall);

        vm.etch(ABV2_ADDRESS, address(tempProxy).code);
        vm.store(ABV2_ADDRESS, ERC1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));

        abv2 = AddressBookV2(ABV2_ADDRESS);
        abv2.initialize();
    }
}
