// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {DeployHelpers} from "../base/DeployHelpers.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IAddressBookV2} from "../../src/AddressBookV2/interfaces/IAddressBookV2.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {IRegistry} from "../../src/system/IRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {State, NodeInfo, BlsPublicKeyInfo} from "../../src/types/Node.sol";
import {MockCnStaking} from "../../src/CnStaking/mocks/MockCnStaking.sol";
import {NodeIdSigUtil} from "../base/NodeIdSigUtil.sol";

/// @title GasBenchmark
/// @notice Gas benchmarks for epoch transitions and getters at scale (50, 100, 150 nodes).
///         Results written to snapshots/GasBenchmark.json via vm.snapshotGasLastCall.
///         Run with: forge test --match-contract GasBenchmark -vv
contract GasBenchmark is DeployHelpers {
    uint256 internal constant BENCHMARK_MAX_NODE_COUNT = 500;
    uint256 internal constant BENCHMARK_MAX_READY_CAND_COUNT = 200;

    address internal owner;

    /// @dev Produces the nodeId ownership signature that createNode requires: an ECDSA
    ///      signature by nodeId over (caller, nodeId, stakingContract, chainId, addressBook).
    function _signNodeIdFor(uint256 nodeIdPk, address caller, address nodeId, address staking)
        internal
        view
        returns (bytes memory)
    {
        return NodeIdSigUtil.sign(nodeIdPk, caller, nodeId, staking, address(abv2));
    }

    function setUp() public {
        owner = makeAddr("owner");

        // Mock CnStakingFactory in registry (needed by NodeVerifier in ABv2DataContract constructor)
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("CnStakingFactory")),
            abi.encode(address(0x501))
        );
        vm.mockCall(address(0x501), abi.encodeWithSignature("isDeployedCnStaking(address)"), abi.encode(true));
    }

    /* ========== HELPERS ========== */

    /// @notice Deploy ABv2 with N genesis validators via ABv2DataContract
    function _bootstrapValidators(uint256 count, uint256 startIdx) internal returns (address[] memory nodeIds) {
        nodeIds = new address[](count);
        NodeInfo[] memory infos = new NodeInfo[](count);

        for (uint256 i; i < count; i++) {
            string memory idx = vm.toString(startIdx + i);
            nodeIds[i] = makeAddr(string.concat("val", idx));

            MockCnStaking staking = deployMockCnStaking(MIN_STAKE, 0);
            infos[i] = NodeInfo({
                manager: nodeIds[i], // manager = nodeId
                stakingContract: address(staking),
                rewardAddress: makeAddr(string.concat("rew", idx)),
                voterAddress: makeAddr(string.concat("vot", idx)),
                timeoutAt: 0,
                gcId: 0,
                blsInfo: _makeBlsInfo(),
                name: "",
                metadata: "",
                state: State.Unknown
            });
        }

        IABv2DataContract.InitData memory initData = IABv2DataContract.InitData({
            initialOwner: owner,
            initialSuspender: owner,
            initialConfigurator: owner,
            pfsThreshold: DEFAULT_PFS_THRESHOLD,
            cfsThreshold: 300,
            pauseTimeout: DEFAULT_PAUSE_TIMEOUT,
            idleTimeout: DEFAULT_IDLE_TIMEOUT,
            maxNodeCount: BENCHMARK_MAX_NODE_COUNT,
            maxValActivePausedCount: BENCHMARK_MAX_NODE_COUNT,
            maxCandReadyCount: BENCHMARK_MAX_READY_CAND_COUNT,
            kefAddress: makeAddr("kef"),
            kifAddress: makeAddr("kif"),
            kpfAddress: makeAddr("kpf"),
            nodeIds: nodeIds,
            infos: infos
        });

        deployAddressBookV2WithValidators(initData);
    }

    /// @notice Create N CandReady candidates (for CandTesting promotion in epoch)
    function _createCandReadyCandidates(uint256 count, uint256 startIdx) internal returns (address[] memory nodeIds) {
        nodeIds = new address[](count);

        for (uint256 i; i < count; i++) {
            string memory idx = vm.toString(startIdx + i);
            (address nodeId, uint256 nodeIdPk) = makeAddrAndKey(string.concat("cand", idx));
            address mgr = makeAddr(string.concat("cmgr", idx));
            MockCnStaking staking = deployMockCnStaking(MIN_STAKE, 0);
            address reward = makeAddr(string.concat("crew", idx));
            address voter = makeAddr(string.concat("cvot", idx));

            _mockDeployer(address(staking), mgr);
            bytes memory sig = _signNodeIdFor(nodeIdPk, mgr, nodeId, address(staking));
            vm.prank(mgr);
            abv2.createNode(nodeId, address(staking), reward, voter, _makeBlsInfo(), string.concat("cand", idx), "", sig);
            vm.deal(nodeId, 10 ether);
            vm.prank(nodeId);
            abv2.readyCandidate(nodeId);

            nodeIds[i] = nodeId;
        }
    }

    function _rollToNextEpoch() internal {
        uint256 current = block.number;
        uint256 nextEpochBlock = ((current / EPOCH_BLOCK_INTERVAL) + 1) * EPOCH_BLOCK_INTERVAL;
        vm.roll(nextEpochBlock);
    }

    /// @notice Prepare state for a full epoch swap, then execute processSystemTransition.
    ///         Only the final processSystemTransition call is snapshotted.
    function _setupAndRunFullEpoch(
        string memory snapshotName,
        uint256 totalValidators,
        uint256 swapCount,
        uint256 candTestingCount
    ) internal {
        // 1. Bootstrap all validators as ValActive via data contract
        address[] memory valIds = _bootstrapValidators(totalValidators, 0);

        // 2. Create CandReady candidates
        address[] memory candIds;
        if (candTestingCount > 0) {
            candIds = _createCandReadyCandidates(candTestingCount, 1000);
        } else {
            candIds = new address[](0);
        }

        // 3. First epoch: demote swapCount validators → ValInactive (so they can become ValReady)
        {
            address[] memory demoteIds = new address[](swapCount);
            State[] memory demoteStates = new State[](swapCount);
            uint256[] memory demoteTimeouts = new uint256[](swapCount);
            for (uint256 i; i < swapCount; i++) {
                demoteIds[i] = valIds[totalValidators - swapCount + i];
                demoteStates[i] = State.ValInactive;
                demoteTimeouts[i] = block.timestamp + DEFAULT_IDLE_TIMEOUT;
            }

            _rollToNextEpoch();
            vm.prank(SYSTEM_SENDER);
            abv2.processSystemTransition(demoteIds, demoteStates, demoteTimeouts, 0);
        }

        // 4. Those demoted validators call readyValidator → ValReady
        //    Manager is nodeId itself (set via ABv2DataContract)
        for (uint256 i; i < swapCount; i++) {
            address nodeId = valIds[totalValidators - swapCount + i];
            vm.prank(nodeId);
            abv2.readyValidator(nodeId);
        }

        // 5. Build single processSystemTransition call:
        //    - swapCount ValActive → ValInactive (demote from front)
        //    - swapCount ValReady → ValActive (promote from tail)
        //    - candTestingCount CandReady → CandTesting
        uint256 changedLen = 2 * swapCount + candTestingCount;
        address[] memory allIds = new address[](changedLen);
        State[] memory allStates = new State[](changedLen);
        uint256[] memory allTimeouts = new uint256[](changedLen);

        for (uint256 i; i < swapCount; i++) {
            allIds[i] = valIds[i];
            allStates[i] = State.ValInactive;
            allTimeouts[i] = block.timestamp + DEFAULT_IDLE_TIMEOUT;
        }
        for (uint256 i; i < swapCount; i++) {
            allIds[swapCount + i] = valIds[totalValidators - swapCount + i];
            allStates[swapCount + i] = State.ValActive;
            // ValActive: no timeout
        }
        for (uint256 i; i < candTestingCount; i++) {
            allIds[2 * swapCount + i] = candIds[i];
            allStates[2 * swapCount + i] = State.CandTesting;
            // CandTesting: no timeout
        }

        // 6. Run the real system transition and snapshot only this call
        _rollToNextEpoch();
        vm.prank(SYSTEM_SENDER);
        abv2.processSystemTransition(allIds, allStates, allTimeouts, 0);
        vm.snapshotGasLastCall(snapshotName);
    }

    /// @notice Deploys data contract + proxy at 0x400 WITHOUT calling initialize().
    ///         Returns the InitData so the caller can verify post-init state.
    function _prepareInitialize(uint256 count) internal returns (IABv2DataContract.InitData memory initData) {
        address[] memory nodeIds = new address[](count);
        NodeInfo[] memory infos = new NodeInfo[](count);

        for (uint256 i; i < count; i++) {
            string memory idx = vm.toString(i);
            nodeIds[i] = makeAddr(string.concat("val", idx));

            MockCnStaking staking = deployMockCnStaking(MIN_STAKE, 0);
            infos[i] = NodeInfo({
                manager: nodeIds[i],
                stakingContract: address(staking),
                rewardAddress: makeAddr(string.concat("rew", idx)),
                voterAddress: makeAddr(string.concat("vot", idx)),
                timeoutAt: 0,
                gcId: 0,
                blsInfo: _makeBlsInfo(),
                name: "",
                metadata: "",
                state: State.Unknown
            });
        }

        initData = IABv2DataContract.InitData({
            initialOwner: owner,
            initialSuspender: owner,
            initialConfigurator: owner,
            pfsThreshold: DEFAULT_PFS_THRESHOLD,
            cfsThreshold: 300,
            pauseTimeout: DEFAULT_PAUSE_TIMEOUT,
            idleTimeout: DEFAULT_IDLE_TIMEOUT,
            maxNodeCount: BENCHMARK_MAX_NODE_COUNT,
            maxValActivePausedCount: BENCHMARK_MAX_NODE_COUNT,
            maxCandReadyCount: BENCHMARK_MAX_READY_CAND_COUNT,
            kefAddress: makeAddr("kef"),
            kifAddress: makeAddr("kif"),
            kpfAddress: makeAddr("kpf"),
            nodeIds: nodeIds,
            infos: infos
        });

        // Deploy data contract and mock registry
        ABv2DataContract dataContract = new ABv2DataContract(address(0xBEEF), initData);
        vm.mockCall(
            REGISTRY_ADDRESS,
            abi.encodeCall(IRegistry.getActiveAddr, ("ABv2DataContract")),
            abi.encode(address(dataContract))
        );

        // Deploy proxy at 0x400 without calling initialize
        AddressBookV2 impl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);
        bytes memory initCall = abi.encodeCall(AddressBookV2.initialize, ());
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(impl), initCall);

        vm.etch(ABV2_ADDRESS, address(tempProxy).code);
        vm.store(ABV2_ADDRESS, ERC1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));
        abv2 = AddressBookV2(ABV2_ADDRESS);
    }

    /* ========== INITIALIZE WITH DATA CONTRACT ========== */

    function test_gas_initialize_50() public {
        _prepareInitialize(50);
        abv2.initialize();
        vm.snapshotGasLastCall("initialize_50");
        assertEq(abv2.getAllNodesLength(), 50);
    }

    function test_gas_initialize_100() public {
        _prepareInitialize(100);
        abv2.initialize();
        vm.snapshotGasLastCall("initialize_100");
        assertEq(abv2.getAllNodesLength(), 100);
    }

    /* ========== EPOCH TRANSITION: 50 validators ========== */

    function test_gas_epoch_50val_swap10_cand5() public {
        _setupAndRunFullEpoch("epoch_50val_swap10_cand5", 50, 10, 5);
    }

    function test_gas_epoch_50val_swap25_cand10() public {
        _setupAndRunFullEpoch("epoch_50val_swap25_cand10", 50, 25, 10);
    }

    /* ========== EPOCH TRANSITION: 100 validators ========== */

    function test_gas_epoch_100val_swap10_cand5() public {
        _setupAndRunFullEpoch("epoch_100val_swap10_cand5", 100, 10, 5);
    }

    function test_gas_epoch_100val_swap50_cand20() public {
        _setupAndRunFullEpoch("epoch_100val_swap50_cand20", 100, 50, 20);
    }

    /* ========== EPOCH TRANSITION: 150 validators ========== */

    function test_gas_epoch_150val_swap10_cand5() public {
        _setupAndRunFullEpoch("epoch_150val_swap10_cand5", 150, 10, 5);
    }

    function test_gas_epoch_150val_swap50_cand20() public {
        _setupAndRunFullEpoch("epoch_150val_swap50_cand20", 150, 50, 20);
    }

    function test_gas_epoch_150val_swap75_cand30() public {
        _setupAndRunFullEpoch("epoch_150val_swap75_cand30", 150, 75, 30);
    }

    /* ========== GETTERS: 50 nodes ========== */

    function test_gas_getAllProfiles_50() public {
        _bootstrapValidators(50, 0);
        abv2.getAllProfiles();
        vm.snapshotGasLastCall("getAllProfiles_50");
    }

    function test_gas_getAllBlsInfo_50() public {
        _bootstrapValidators(50, 0);
        abv2.getAllBlsInfo();
        vm.snapshotGasLastCall("getAllBlsInfo_50");
    }

    /* ========== GETTERS: 100 nodes ========== */

    function test_gas_getAllProfiles_100() public {
        _bootstrapValidators(100, 0);
        abv2.getAllProfiles();
        vm.snapshotGasLastCall("getAllProfiles_100");
    }

    function test_gas_getAllBlsInfo_100() public {
        _bootstrapValidators(100, 0);
        abv2.getAllBlsInfo();
        vm.snapshotGasLastCall("getAllBlsInfo_100");
    }

    /* ========== GETTERS: 150 nodes ========== */

    function test_gas_getAllProfiles_150() public {
        _bootstrapValidators(150, 0);
        abv2.getAllProfiles();
        vm.snapshotGasLastCall("getAllProfiles_150");
    }

    function test_gas_getAllBlsInfo_150() public {
        _bootstrapValidators(150, 0);
        abv2.getAllBlsInfo();
        vm.snapshotGasLastCall("getAllBlsInfo_150");
    }

}
