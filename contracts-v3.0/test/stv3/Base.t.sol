// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {StakingTrackerV3} from "../../src/StakingTrackerV3/StakingTrackerV3.sol";
import {IStakingTrackerV3} from "../../src/StakingTrackerV3/interfaces/IStakingTrackerV3.sol";
import {IRegistry} from "../../src/system/IRegistry.sol";
import {NodeInfo, BlsPublicKeyInfo, GovernanceInfo} from "../../src/types/Node.sol";
import {MockCnStaking} from "../../src/CnStaking/mocks/MockCnStaking.sol";

/// @title STv3 Base
/// @notice Test base for StakingTrackerV3 tests.
///         Deploys ABv2 with 4 genesis validators (ValActive, gcId 1-4),
///         deploys STv3 behind a UUPS proxy, and sets up Registry mocks.
contract STv3Base is Test {
    /* ========== SYSTEM CONSTANTS ========== */

    address internal constant ABV2_ADDRESS = address(0x400);
    address internal constant REGISTRY_ADDRESS = address(0x401);
    address internal constant MOCK_FACTORY = address(0x501);
    uint256 internal constant EPOCH_BLOCK_INTERVAL = 86_400;
    uint256 internal constant MIN_STAKE = 5_000_000 ether;

    bytes32 internal constant ERC1967_IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    /* ========== STATE ========== */

    address internal owner;
    AddressBookV2 internal abv2;
    StakingTrackerV3 internal stv3;

    // Mock contracts
    address internal mockWKaia;
    address internal mockCLRegistry;

    struct GCBundle {
        address nodeId;
        address manager;
        MockCnStaking staking;
        address rewardAddr;
        address voterAddr;
        uint256 gcId;
    }

    GCBundle[4] internal gc;

    /* ========== SETUP ========== */

    function setUp() public virtual {
        owner = makeAddr("owner");

        // Deploy ABv2 with 4 genesis validators
        _deployABv2WithGenesis();

        // Deploy STv3 behind a UUPS proxy
        _deploySTv3();

        // Setup Registry mocks for CLRegistry and WrappedKaia
        _setupRegistryMocks();
    }

    /* ========== DEPLOY: ABv2 ========== */

    function _deployABv2WithGenesis() internal {
        // Mock CnStakingFactory
        vm.mockCall(
            REGISTRY_ADDRESS, abi.encodeCall(IRegistry.getActiveAddr, ("CnStakingFactory")), abi.encode(MOCK_FACTORY)
        );
        vm.mockCall(MOCK_FACTORY, abi.encodeWithSignature("isDeployedCnStaking(address)"), abi.encode(true));
        vm.mockCall(MOCK_FACTORY, abi.encodeWithSignature("isDeployedPublicDelegation(address)"), abi.encode(false));
        vm.mockCall(MOCK_FACTORY, abi.encodeWithSignature("getDeployer(address)"), abi.encode(address(0)));

        // Mock StakingTracker → address(0) initially
        vm.mockCall(
            REGISTRY_ADDRESS, abi.encodeCall(IRegistry.getActiveAddr, ("StakingTracker")), abi.encode(address(0))
        );

        // Create 4 GC bundles with MockCnStaking
        address[] memory nodeIds = new address[](4);
        NodeInfo[] memory infos = new NodeInfo[](4);

        for (uint256 i; i < 4; i++) {
            GCBundle memory g = _makeGCBundle(i + 1);
            gc[i] = g;
            nodeIds[i] = g.nodeId;
            infos[i] = NodeInfo({
                manager: g.manager,
                stakingContract: address(g.staking),
                rewardAddress: g.rewardAddr,
                voterAddress: g.voterAddr,
                timeoutAt: 0,
                gcId: g.gcId,
                blsInfo: _makeBlsInfo(i),
                name: "test-node",
                metadata: "",
                state: State.Unknown // overwritten by _setInitialActiveValidators
            });
        }

        IABv2DataContract.InitData memory initData = IABv2DataContract.InitData({
            initialOwner: owner,
            initialSuspender: makeAddr("suspender"),
            initialConfigurator: makeAddr("configurator"),
            pfsThreshold: 2,
            cfsThreshold: 300,
            pauseTimeout: 8 hours,
            idleTimeout: 7 days,
            maxNodeCount: 100,
            maxValActivePausedCount: 50,
            maxCandReadyCount: 3,
            kefAddress: address(0xCE1),
            kifAddress: address(0xC12),
            kpfAddress: address(0xC13),
            nodeIds: nodeIds,
            infos: infos
        });

        // Deploy impl
        AddressBookV2 impl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);

        // Deploy data contract
        ABv2DataContract dataContract = new ABv2DataContract(address(impl), initData);

        // Mock registry to return data contract
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("ABv2DataContract")),
            abi.encode(address(dataContract))
        );

        // Deploy proxy at 0x400
        bytes memory initCall = abi.encodeCall(AddressBookV2.initialize, ());
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(impl), initCall);
        vm.etch(ABV2_ADDRESS, address(tempProxy).code);
        vm.store(ABV2_ADDRESS, ERC1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));

        abv2 = AddressBookV2(ABV2_ADDRESS);
        abv2.initialize();
    }

    /* ========== DEPLOY: STv3 ========== */

    function _deploySTv3() internal {
        StakingTrackerV3 impl = new StakingTrackerV3();
        bytes memory initCall = abi.encodeCall(StakingTrackerV3.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initCall);
        stv3 = StakingTrackerV3(address(proxy));

        // Update Registry mock to return STv3 address
        vm.mockCall(
            REGISTRY_ADDRESS, abi.encodeCall(IRegistry.getActiveAddr, ("StakingTracker")), abi.encode(address(stv3))
        );
    }

    /* ========== SETUP: REGISTRY MOCKS ========== */

    function _setupRegistryMocks() internal {
        // Mock WrappedKaia
        mockWKaia = makeAddr("wKaia");
        vm.mockCall(REGISTRY_ADDRESS, abi.encodeCall(IRegistry.getActiveAddr, ("WrappedKaia")), abi.encode(mockWKaia));

        // Mock CLRegistry → address(0) by default (no CL pools)
        vm.mockCall(
            REGISTRY_ADDRESS, abi.encodeCall(IRegistry.getActiveAddr, ("CLRegistry")), abi.encode(address(0))
        );
    }

    /* ========== HELPERS: GC BUNDLE ========== */

    function _makeGCBundle(uint256 index) internal returns (GCBundle memory g) {
        string memory idx = vm.toString(index);
        MockCnStaking staking = new MockCnStaking();
        staking.mockSetStaking(MIN_STAKE);
        staking.mockSetUnstaking(0);

        g = GCBundle({
            nodeId: makeAddr(string.concat("node", idx)),
            manager: makeAddr(string.concat("manager", idx)),
            staking: staking,
            rewardAddr: makeAddr(string.concat("reward", idx)),
            voterAddr: makeAddr(string.concat("voter", idx)),
            gcId: index
        });
    }

    /* ========== HELPERS: BLS ========== */

    function _makeBlsInfo(uint256 salt) internal pure returns (BlsPublicKeyInfo memory) {
        bytes memory pk = new bytes(48);
        pk[0] = bytes1(uint8(salt + 1));
        bytes memory pop = new bytes(96);
        pop[0] = bytes1(uint8(salt + 1));
        return BlsPublicKeyInfo({publicKey: pk, pop: pop});
    }

    /* ========== HELPERS: TRACKER ========== */

    /// @notice Creates a tracker spanning current block to current block + duration
    function _createTracker(uint256 duration) internal returns (uint256 trackerId) {
        vm.prank(owner);
        trackerId = stv3.createTracker(block.number, block.number + duration);
    }

    /* ========== HELPERS: CL REGISTRY MOCK ========== */

    /// @notice Sets up a mock CLRegistry with given GC IDs and pool addresses
    function _setupCLRegistry(uint256[] memory gcIds, address[] memory pools) internal {
        mockCLRegistry = makeAddr("clRegistry");
        vm.mockCall(
            REGISTRY_ADDRESS, abi.encodeCall(IRegistry.getActiveAddr, ("CLRegistry")), abi.encode(mockCLRegistry)
        );

        address[] memory nodeIds = new address[](gcIds.length);
        for (uint256 i; i < gcIds.length; i++) {
            nodeIds[i] = address(0); // not used by STv3
        }
        vm.mockCall(
            mockCLRegistry,
            abi.encodeWithSignature("getAllCLs()"),
            abi.encode(nodeIds, gcIds, pools)
        );
    }

    /// @notice Mocks wKaia.balanceOf for a CLPool
    function _mockCLPoolBalance(address pool, uint256 balance) internal {
        vm.mockCall(mockWKaia, abi.encodeWithSignature("balanceOf(address)", pool), abi.encode(balance));
    }

    /// @notice Creates a NodeInfo with a specific gcId and voterAddress (for mocking)
    function _makeNodeInfoWithGcId(uint256 gcId, address voterAddr) internal pure returns (NodeInfo memory) {
        return NodeInfo({
            manager: address(0),
            stakingContract: address(0),
            rewardAddress: address(0),
            voterAddress: voterAddr,
            timeoutAt: 0,
            gcId: gcId,
            blsInfo: BlsPublicKeyInfo({publicKey: new bytes(48), pop: new bytes(96)}),
            name: "",
            metadata: "",
            state: State.Unknown
        });
    }
}

// Need to import State for the NodeInfo construction
import {State} from "../../src/types/Node.sol";
