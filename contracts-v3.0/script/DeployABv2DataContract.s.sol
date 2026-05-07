// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ABv2DataContract} from "../src/AddressBookV2/ABv2DataContract.sol";
import {IABv2DataContract} from "../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {NodeInfo, BlsPublicKeyInfo, State} from "../src/types/Node.sol";

/// @title DeployABv2DataContract
/// @notice Deployment script for ABv2DataContract using JSON config.
/// @dev Usage:
///   # Dry-run (simulation):
///   DEPLOYER_PRIVATE_KEY=0x... forge script script/DeployABv2DataContract.s.sol -v
///
///   # Broadcast (live):
///   DEPLOYER_PRIVATE_KEY=0x... forge script script/DeployABv2DataContract.s.sol \
///     --rpc-url $RPC_URL --broadcast
///
///   Environment variables:
///     DEPLOYER_PRIVATE_KEY  - Private key of the deployer (required)
///     CONFIG_PATH           - Path to JSON config file (default: script/abv2-data.json)
///
///   JSON format: see script/abv2-sample-data.json for a complete example.
///   BLS keys must be hex-encoded: publicKey = 48 bytes (96 hex chars), pop = 96 bytes (192 hex chars).
contract DeployABv2DataContract is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        string memory configPath = vm.envOr("CONFIG_PATH", string("script/abv2-data.json"));

        console.log("Config file:", configPath);
        console.log("Deployer:", vm.addr(deployerKey));

        (address implAddress, IABv2DataContract.InitData memory initData) = parseConfig(configPath);

        vm.startBroadcast(deployerKey);
        ABv2DataContract dataContract = new ABv2DataContract(implAddress, initData);
        vm.stopBroadcast();

        console.log("ABv2DataContract deployed at:", address(dataContract));
    }

    function parseConfig(string memory path) public view returns (address, IABv2DataContract.InitData memory) {
        string memory json = vm.readFile(path);

        address implAddress = abi.decode(vm.parseJson(json, ".implementation"), (address));
        console.log("implementation:", implAddress);

        IABv2DataContract.InitData memory d;
        d.initialOwner = abi.decode(vm.parseJson(json, ".initialOwner"), (address));
        d.initialSuspender = abi.decode(vm.parseJson(json, ".initialSuspender"), (address));
        d.initialConfigurator = abi.decode(vm.parseJson(json, ".initialConfigurator"), (address));
        d.pfsThreshold = abi.decode(vm.parseJson(json, ".pfsThreshold"), (uint256));
        d.cfsThreshold = abi.decode(vm.parseJson(json, ".cfsThreshold"), (uint256));
        d.pauseTimeout = abi.decode(vm.parseJson(json, ".pauseTimeout"), (uint256));
        d.idleTimeout = abi.decode(vm.parseJson(json, ".idleTimeout"), (uint256));
        d.maxNodeCount = abi.decode(vm.parseJson(json, ".maxNodeCount"), (uint256));
        d.maxValActivePausedCount = abi.decode(vm.parseJson(json, ".maxValActivePausedCount"), (uint256));
        d.maxCandReadyCount = abi.decode(vm.parseJson(json, ".maxCandReadyCount"), (uint256));
        d.kefAddress = abi.decode(vm.parseJson(json, ".kefAddress"), (address));
        d.kifAddress = abi.decode(vm.parseJson(json, ".kifAddress"), (address));
        d.kpfAddress = abi.decode(vm.parseJson(json, ".kpfAddress"), (address));

        console.log("initialOwner:", d.initialOwner);
        console.log("initialSuspender:", d.initialSuspender);
        console.log("initialConfigurator:", d.initialConfigurator);
        console.log("pfsThreshold:", d.pfsThreshold);
        console.log("cfsThreshold:", d.cfsThreshold);
        console.log("pauseTimeout:", d.pauseTimeout);
        console.log("idleTimeout:", d.idleTimeout);
        console.log("maxNodeCount:", d.maxNodeCount);
        console.log("maxValActivePausedCount:", d.maxValActivePausedCount);
        console.log("maxCandReadyCount:", d.maxCandReadyCount);
        console.log("kefAddress:", d.kefAddress);
        console.log("kifAddress:", d.kifAddress);
        console.log("kpfAddress:", d.kpfAddress);

        uint256 numNodes = abi.decode(vm.parseJson(json, ".numNodes"), (uint256));
        console.log("numNodes:", numNodes);

        (d.nodeIds, d.infos) = _parseNodes(json, numNodes);

        return (implAddress, d);
    }

    function _parseNodes(
        string memory json,
        uint256 numNodes
    ) internal pure returns (address[] memory nodeIds, NodeInfo[] memory infos) {
        nodeIds = new address[](numNodes);
        infos = new NodeInfo[](numNodes);

        for (uint256 i; i < numNodes; i++) {
            string memory base = string.concat(".nodes[", vm.toString(i), "]");
            (nodeIds[i], infos[i]) = _parseOneNode(json, base);

            console.log("--- Node", i, "---");
            console.log("  nodeId:          ", nodeIds[i]);
            console.log("  manager:         ", infos[i].manager);
            console.log("  stakingContract: ", infos[i].stakingContract);
            console.log("  rewardAddress:   ", infos[i].rewardAddress);
            console.log("  voterAddress:    ", infos[i].voterAddress);
            console.log("  gcId:            ", infos[i].gcId);
            console.log("  name:            ", infos[i].name);
        }
    }

    function _parseOneNode(
        string memory json,
        string memory base
    ) internal pure returns (address nodeId, NodeInfo memory info) {
        nodeId = abi.decode(vm.parseJson(json, string.concat(base, ".nodeId")), (address));

        bytes memory blsPublicKey = abi.decode(vm.parseJson(json, string.concat(base, ".blsPublicKey")), (bytes));
        bytes memory blsPop = abi.decode(vm.parseJson(json, string.concat(base, ".blsPop")), (bytes));

        info = NodeInfo({
            manager: abi.decode(vm.parseJson(json, string.concat(base, ".manager")), (address)),
            stakingContract: abi.decode(vm.parseJson(json, string.concat(base, ".stakingContract")), (address)),
            rewardAddress: abi.decode(vm.parseJson(json, string.concat(base, ".rewardAddress")), (address)),
            voterAddress: abi.decode(vm.parseJson(json, string.concat(base, ".voterAddress")), (address)),
            timeoutAt: 0,
            gcId: abi.decode(vm.parseJson(json, string.concat(base, ".gcId")), (uint256)),
            blsInfo: BlsPublicKeyInfo({publicKey: blsPublicKey, pop: blsPop}),
            name: abi.decode(vm.parseJson(json, string.concat(base, ".name")), (string)),
            metadata: abi.decode(vm.parseJson(json, string.concat(base, ".metadata")), (string)),
            state: State.Unknown
        });
    }
}
