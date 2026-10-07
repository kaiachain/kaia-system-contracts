// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployABv2DataContract} from "../DeployABv2DataContract.s.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {StakingTrackerV3} from "../../src/StakingTrackerV3/StakingTrackerV3.sol";
import {NodeInfo, GovernanceInfo, BlsPublicKeyInfo, State} from "../../src/types/Node.sol";

interface IRegistryKairos {
    function register(string memory name, address addr, uint256 activation) external;
    function getActiveAddr(string memory name) external view returns (address);
    function owner() external view returns (address);
}

interface IABv1Kairos {
    function getAllAddressInfo()
        external
        view
        returns (address[] memory, address[] memory, address[] memory, address, address);
    function spareContractAddress() external view returns (address);
}

interface IKip113 {
    function getAllBlsInfo() external view returns (address[] memory, BlsPublicKeyInfo[] memory);
}

interface IVotingKairos {
    function propose(
        string memory description,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        uint256 votingDelay,
        uint256 votingPeriod
    ) external returns (uint256 proposalId);
    function secretary() external view returns (address);
    function stakingTracker() external view returns (address);
    function timingRule() external view returns (uint256, uint256, uint256, uint256);
    function state(uint256 proposalId) external view returns (uint8);
}

/// @title KairosK03Fork
/// @notice Kairos fork rehearsal for K-03: deploy ABv2DataContract from the JSON config,
///         register it in Registry (0x401), install ABv2 at 0x400 the way the client does
///         at HF-1 (proxy code + implementation slot, then initialize()), and run the
///         post-hardfork STv3 path through Voting.propose.
/// @dev Usage (read-only; nothing is broadcast):
///   set RPC https://public-en-kairos.node.kaia.io
///   set BN (math "floor((cast block-number -r $RPC) / 128) * 128")
///   forge script script/rehearsal/KairosK03Fork.s.sol --fork-url $RPC --fork-block-number $BN -vv
///   Env: CONFIG_PATH (required; path to the abv2-data JSON for this fork)
///        DEPLOY_IMPL=true  deploy a fresh AddressBookV2 implementation in the fork as the real
///                          deployer (current nonce) before the data contract, so the data
///                          contract lands at nonce+1. Rehearses the redeploy path before the
///                          implementation exists on-chain; the JSON `implementation` is overridden.
///        EPOCH_BLOCK_INTERVAL (default 86400) constructor argument for that implementation.
contract KairosK03Fork is Script {
    address constant REGISTRY = 0x0000000000000000000000000000000000000401;
    address constant ADDRESS_BOOK = 0x0000000000000000000000000000000000000400;
    address constant VOTING = 0x2C41DdBF0239cEaa75325D66809d0199F368188b;
    address constant STV3 = 0xeB8aBBC673f4322226Db4B8718535a6831fa1F66;
    address constant KIP113 = 0x4BEed0651C46aE5a7CB3b7737345d2ee733789e6;
    address constant DEPLOYER = 0x04992a2B7E7CE809d409adE32185D49A96AAa32d;
    // bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 constant ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    uint256 constant MIN_STAKE = 5_000_000 ether;

    address impl;
    uint256 epochBlockInterval;
    IABv2DataContract.InitData d;
    ABv2DataContract data;
    bytes registerCalldata;

    function run() external {
        string memory configPath = vm.envString("CONFIG_PATH");
        epochBlockInterval = vm.envOr("EPOCH_BLOCK_INTERVAL", uint256(86_400));
        console.log("fork block:", block.number);
        console.log("config:", configPath);
        (address impl_, IABv2DataContract.InitData memory d_) = new DeployABv2DataContract().parseConfig(configPath);
        impl = impl_;
        _storeInitData(d_);

        if (vm.envOr("DEPLOY_IMPL", false)) _deployImpl();
        _preconditions();
        _deploy();
        _register();
        _install();
        _stv3();

        console.log("=== 5. summary ===");
        console.log("ABv2DataContract predicted (see deployer nonce above):", address(data));
        console.log("register calldata (activation placeholder = fork block + 1):");
        console.logBytes(registerCalldata);
        console.log("K-03 fork rehearsal PASSED");
    }

    function _storeInitData(IABv2DataContract.InitData memory m) internal {
        d.initialOwner = m.initialOwner;
        d.initialSuspender = m.initialSuspender;
        d.initialConfigurator = m.initialConfigurator;
        d.pfsThreshold = m.pfsThreshold;
        d.cfsThreshold = m.cfsThreshold;
        d.pauseTimeout = m.pauseTimeout;
        d.idleTimeout = m.idleTimeout;
        d.maxNodeCount = m.maxNodeCount;
        d.maxValActivePausedCount = m.maxValActivePausedCount;
        d.maxCandReadyCount = m.maxCandReadyCount;
        d.kefAddress = m.kefAddress;
        d.kifAddress = m.kifAddress;
        d.kpfAddress = m.kpfAddress;
        for (uint256 i; i < m.nodeIds.length; ++i) {
            d.nodeIds.push(m.nodeIds[i]);
            d.infos.push(m.infos[i]);
        }
    }

    function _preconditions() internal view {
        console.log("=== 0. preconditions ===");
        uint256 n = d.nodeIds.length;
        require(IRegistryKairos(REGISTRY).getActiveAddr("ABv2DataContract") == address(0), "already registered");
        require(impl.code.length > 0, "impl has no code");
        require(IRegistryKairos(REGISTRY).getActiveAddr("StakingTracker") == STV3, "Registry StakingTracker != STv3");
        require(IRegistryKairos(REGISTRY).getActiveAddr("CnStakingFactory") != address(0), "CnStakingFactory missing");
        require(IVotingKairos(VOTING).stakingTracker() == STV3, "Voting.stakingTracker != STv3");
        require(StakingTrackerV3(STV3).getLiveTrackerIds().length == 0, "live tracker exists");

        (
            address[] memory abNodes,
            address[] memory abStaking,
            address[] memory abReward,
            address abKif,
            address abKef
        ) = IABv1Kairos(ADDRESS_BOOK).getAllAddressInfo();
        for (uint256 i; i < n; ++i) {
            bool found;
            for (uint256 j; j < abNodes.length; ++j) {
                if (abNodes[j] == d.nodeIds[i]) {
                    require(abStaking[j] == d.infos[i].stakingContract, "AB v1 staking mismatch");
                    require(abReward[j] == d.infos[i].rewardAddress, "AB v1 reward mismatch");
                    found = true;
                }
            }
            require(found, "node not in AB v1");
        }
        require(abKef == d.kefAddress, "kef != AB v1 kir");
        require(abKif == d.kifAddress, "kif != AB v1 poc");
        require(IABv1Kairos(ADDRESS_BOOK).spareContractAddress() == d.kpfAddress, "kpf != AB v1 spare");

        (address[] memory blsNodes, BlsPublicKeyInfo[] memory blsInfos) = IKip113(KIP113).getAllBlsInfo();
        for (uint256 i; i < n; ++i) {
            bool found;
            for (uint256 j; j < blsNodes.length; ++j) {
                if (blsNodes[j] == d.nodeIds[i]) {
                    require(
                        keccak256(blsInfos[j].publicKey) == keccak256(d.infos[i].blsInfo.publicKey), "BLS pk mismatch"
                    );
                    require(keccak256(blsInfos[j].pop) == keccak256(d.infos[i].blsInfo.pop), "BLS pop mismatch");
                    found = true;
                }
            }
            require(found, "node not in KIP113");
        }
        console.log("preconditions OK, nodes:", n);
    }

    function _deployImpl() internal {
        console.log("=== 1a. deploy AddressBookV2 implementation as the real deployer ===");
        uint256 epoch = epochBlockInterval;
        uint64 nonce = vm.getNonce(DEPLOYER);
        address predicted = vm.computeCreateAddress(DEPLOYER, nonce);
        require(predicted.code.length == 0, "predicted impl address already has code");
        vm.startPrank(DEPLOYER, DEPLOYER);
        uint256 g0 = gasleft();
        AddressBookV2 newImpl = new AddressBookV2(epoch);
        uint256 gasUsed = g0 - gasleft();
        vm.stopPrank();
        require(address(newImpl) == predicted, "impl CREATE address mismatch");
        require(address(newImpl).code.length <= 24_576, "impl exceeds EIP-170");
        console.log("deployer nonce (impl):", nonce);
        console.log("new impl:", address(newImpl));
        console.log(
            "impl runtime bytes / EIP-170 headroom:",
            address(newImpl).code.length,
            24_576 - address(newImpl).code.length
        );
        console.log("impl constructor gas (execution only, excl. intrinsic):", gasUsed);
        console.log("JSON implementation (overridden):", impl);
        impl = address(newImpl);
    }

    function _deploy() internal {
        console.log("=== 1. deploy ABv2DataContract as the real deployer ===");
        uint64 nonce = vm.getNonce(DEPLOYER);
        address predicted = vm.computeCreateAddress(DEPLOYER, nonce);
        IABv2DataContract.InitData memory m = d;
        vm.startPrank(DEPLOYER, DEPLOYER);
        uint256 g0 = gasleft();
        data = new ABv2DataContract(impl, m);
        uint256 gasUsed = g0 - gasleft();
        vm.stopPrank();
        require(address(data) == predicted, "CREATE address mismatch");
        require(data.implementation() == impl, "implementation mismatch");
        IABv2DataContract.InitData memory stored = data.getInitData();
        require(stored.nodeIds.length == d.nodeIds.length, "stored node count");
        for (uint256 i; i < stored.nodeIds.length; ++i) {
            require(stored.nodeIds[i] == d.nodeIds[i], "stored nodeId");
            require(stored.infos[i].gcId == d.infos[i].gcId, "stored gcId");
            require(stored.infos[i].manager == d.infos[i].manager, "stored manager");
        }
        bytes memory initcode = abi.encodePacked(type(ABv2DataContract).creationCode, abi.encode(impl, m));
        uint256 zeros;
        for (uint256 i; i < initcode.length; ++i) {
            if (initcode[i] == 0) ++zeros;
        }
        console.log("initcode bytes / zero bytes:", initcode.length, zeros);
        console.log("INITCODE_HEX_BEGIN");
        console.logBytes(initcode);
        console.log("INITCODE_HEX_END");
        console.log("deployer nonce:", nonce);
        console.log("ABv2DataContract:", address(data));
        console.log("constructor gas (execution only, excl. intrinsic):", gasUsed);
    }

    function _register() internal {
        console.log("=== 2. Registry register by the Registry owner ===");
        address regOwner = IRegistryKairos(REGISTRY).owner();
        uint256 activation = block.number + 1;
        registerCalldata =
            abi.encodeWithSignature("register(string,address,uint256)", "ABv2DataContract", address(data), activation);
        vm.prank(regOwner);
        (bool ok,) = REGISTRY.call(registerCalldata);
        require(ok, "register failed");
        vm.roll(activation);
        require(IRegistryKairos(REGISTRY).getActiveAddr("ABv2DataContract") == address(data), "not active");
        console.log("Registry owner:", regOwner);
        console.log("active after roll to", block.number);
    }

    function _install() internal {
        console.log("=== 3. install ABv2 at 0x400 (client InstallAddressBookV2 stand-in) ===");
        // The exact runtime code the client writes at 0x400 (kaia blockchain/system/constant.go
        // ERC1967ProxyV5Code), exported from contracts/bindings to script/rehearsal/erc1967_proxy_v5_runtime.hex.
        bytes memory clientProxyCode = vm.parseBytes(vm.readFile("script/rehearsal/erc1967_proxy_v5_runtime.hex"));
        // Cross-check against this repo's OZ ERC1967Proxy runtime (same code, metadata aside).
        ERC1967Proxy temp = new ERC1967Proxy(impl, abi.encodeCall(AddressBookV2.initialize, ()));
        console.log("client proxy runtime bytes:", clientProxyCode.length);
        console.log("repo OZ proxy runtime bytes:", address(temp).code.length);
        console.log(
            "client proxy == repo OZ proxy (byte-exact):", keccak256(clientProxyCode) == keccak256(address(temp).code)
        );
        vm.etch(ADDRESS_BOOK, clientProxyCode);
        vm.store(ADDRESS_BOOK, ERC1967_IMPL_SLOT, bytes32(uint256(uint160(impl))));
        AddressBookV2 ab = AddressBookV2(ADDRESS_BOOK);
        ab.initialize();
        _checkConfig(ab);
        _checkNodes(ab);
        console.log("ABv2 initialized: owner/suspender/configurator/funds/nodes OK");
    }

    function _checkConfig(AddressBookV2 ab) internal view {
        require(ab.owner() == d.initialOwner, "owner");
        require(ab.getSuspender() == d.initialSuspender, "suspender");
        require(ab.getConfigurator() == d.initialConfigurator, "configurator");
        (address kef, address kif, address kpf) = ab.getFundAddresses();
        require(kef == d.kefAddress && kif == d.kifAddress && kpf == d.kpfAddress, "fund addresses");
        require(ab.epochBlockInterval() == epochBlockInterval, "epochBlockInterval");
        require(ab.getPfsThreshold() == d.pfsThreshold && ab.getCfsThreshold() == d.cfsThreshold, "thresholds");
        uint256 n = d.nodeIds.length;
        require(ab.getStateCount(State.ValActive) == n, "ValActive count");
        require(ab.getEpochVACount() == n, "epochVACount");
        (address[] memory lNodes, address[] memory lStaking,, address lKif, address lKef) = ab.getAllAddressInfo();
        require(lNodes.length == n && lStaking.length == n && lKif == kif && lKef == kef, "legacy view");
    }

    function _checkNodes(AddressBookV2 ab) internal view {
        uint256 n = d.nodeIds.length;
        GovernanceInfo[] memory gov = ab.getAllGovernanceInfo();
        require(gov.length == n, "gov count");
        for (uint256 i; i < n; ++i) {
            require(gov[i].nodeId == d.nodeIds[i], "gov nodeId");
            require(gov[i].stakingContract == d.infos[i].stakingContract, "gov staking");
            require(gov[i].gcId == i + 1, "gov gcId != i+1");
            require(gov[i].voterAddress == address(0), "gov voter != 0");
            NodeInfo memory ni = ab.getNodeInfo(d.nodeIds[i]);
            require(ni.state == State.ValActive, "state");
            require(ni.manager == d.infos[i].manager, "manager");
            require(ni.rewardAddress == d.infos[i].rewardAddress, "reward");
            console.log("  gcId", gov[i].gcId, gov[i].nodeId, d.infos[i].name);
        }
        (address[] memory blsNodes, BlsPublicKeyInfo[] memory bls) = ab.getAllBlsInfo();
        require(blsNodes.length == n, "bls count");
        for (uint256 i; i < n; ++i) {
            require(blsNodes[i] == d.nodeIds[i], "bls nodeId");
            require(keccak256(bls[i].publicKey) == keccak256(d.infos[i].blsInfo.publicKey), "bls pk");
        }
    }

    function _stv3() internal {
        console.log("=== 4. STv3: refreshVoter + Voting.propose -> createTracker ===");
        StakingTrackerV3 stv3 = StakingTrackerV3(STV3);
        for (uint256 i; i < d.nodeIds.length; ++i) {
            stv3.refreshVoter(d.nodeIds[i]);
            require(stv3.gcIdToVoter(i + 1) == address(0), "voter should stay 0");
        }
        uint256 proposalId = _propose();
        console.log("proposal id:", proposalId);
        console.log("proposal state:", IVotingKairos(VOTING).state(proposalId));
        _checkTracker(stv3);
    }

    function _propose() internal returns (uint256 proposalId) {
        IVotingKairos voting = IVotingKairos(VOTING);
        address secretary = voting.secretary();
        (uint256 minDelay,, uint256 minPeriod,) = voting.timingRule();
        address[] memory targets = new address[](1);
        targets[0] = VOTING;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateSecretary(address)", secretary);
        vm.prank(secretary);
        proposalId =
            voting.propose("K-03 rehearsal: STv3 tracker over ABv2", targets, values, calldatas, minDelay, minPeriod);
    }

    function _checkTracker(StakingTrackerV3 stv3) internal view {
        uint256 n = d.nodeIds.length;
        uint256 trackerId = stv3.getLastTrackerId();
        require(trackerId == 1, "tracker id");
        (,, uint256 numGCs, uint256 totalVotes, uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        require(numGCs == n, "tracker GC count");
        require(numEligible == n, "tracker eligible count");
        (uint256[] memory gcIds, uint256[] memory gcBalances, uint256[] memory gcVotes) =
            stv3.getAllTrackedGCs(trackerId);
        for (uint256 i; i < gcIds.length; ++i) {
            require(gcBalances[i] >= MIN_STAKE, "GC below min stake");
            console.log("  tracked gcId / balance(KAIA) / votes:", gcIds[i], gcBalances[i] / 1 ether, gcVotes[i]);
        }
        console.log("tracker GCs / eligible / totalVotes:", numGCs, numEligible, totalVotes);
    }
}
