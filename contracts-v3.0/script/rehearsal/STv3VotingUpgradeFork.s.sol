// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakingTrackerV3} from "../../src/StakingTrackerV3/StakingTrackerV3.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {NodeInfo, BlsPublicKeyInfo, GovernanceInfo, State} from "../../src/types/Node.sol";

/* ========== KAIROS LIVE CONTRACT INTERFACES ========== */

/// @dev Kairos Voting contract (contracts-klaytn-v1.10 Voting.sol)
interface IVotingKairos {
    function propose(
        string memory description,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        uint256 votingDelay,
        uint256 votingPeriod
    ) external returns (uint256 proposalId);

    function castVote(uint256 proposalId, uint8 choice) external;
    function queue(uint256 proposalId) external;
    function execute(uint256 proposalId) external payable;

    function stakingTracker() external view returns (address);
    function secretary() external view returns (address);
    function execDelay() external view returns (uint256);
    function lastProposalId() external view returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function checkQuorum(uint256 proposalId) external view returns (bool);
    function getVotes(uint256 proposalId, address voter) external view returns (uint256 gcId, uint256 votes);
    function accessRule() external view returns (bool, bool, bool, bool);
    function timingRule() external view returns (uint256, uint256, uint256, uint256);
    function getProposalSchedule(uint256 proposalId)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, bool, bool, bool);
    function getProposalTally(uint256 proposalId)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256[] memory);
}

/// @dev Kairos StakingTrackerV2 (contracts-v2.0 StakingTrackerV2.sol)
interface ISTv2Kairos {
    function refreshStake(address staking) external;
    function getLastTrackerId() external view returns (uint256);
    function getLiveTrackerIds() external view returns (uint256[] memory);
    function getTrackerSummary(uint256 trackerId) external view returns (uint256, uint256, uint256, uint256, uint256);
    function getAllTrackedGCs(uint256 trackerId)
        external
        view
        returns (uint256[] memory, uint256[] memory, uint256[] memory);
    function gcIdToVoter(uint256 gcId) external view returns (address);
    function voterToGCId(address voter) external view returns (uint256);
    function refreshVoter(address staking) external;
}

/// @dev Kairos AddressBook v1 (0x400, pre-hardfork)
interface IABv1Kairos {
    function getAllAddressInfo()
        external
        view
        returns (address[] memory, address[] memory, address[] memory, address, address);
}

/// @dev Kairos Registry (0x401, contracts-klaytn-v1.12 Registry.sol)
interface IRegistryKairos {
    function owner() external view returns (address);
    function register(string memory name, address addr, uint256 activation) external;
    function getActiveAddr(string memory name) external view returns (address);
}

/// @dev Live CnStaking probing surface (V2/V3 getters + V3 AccessControl multisig)
interface ICnStakingKairos {
    function VERSION() external view returns (uint256);
    function gcId() external view returns (uint256);
    function voterAddress() external view returns (address);
    function stakingTracker() external view returns (address);
    function requirement() external view returns (uint256);
    function ADMIN_ROLE() external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function submitUpdateVoterAddress(address _addr) external;
    function staking() external view returns (uint256);
    function unstaking() external view returns (uint256);
    function publicDelegation() external view returns (address);
}

/// @dev Kairos PublicDelegation (PD-enabled CnStakingV3s)
interface IPublicDelegationKairos {
    function stake() external payable;
}

/// @dev Kairos KIP113 (BLS registry, resolved via Registry)
interface IKIP113Kairos {
    function getAllBlsInfo() external view returns (address[] memory, BlsPublicKeyInfo[] memory);
}

/// @title STv3VotingUpgradeFork
/// @notice Kairos-fork rehearsal for switching the Voting contract's StakingTracker
///         from the live StakingTrackerV2 to a freshly deployed StakingTrackerV3 (UUPS).
///
/// Sequence (mirrors DeploySTv3.s.sol deployment-order notes):
///   1. Ensure the target GC (TARGET_NODE_ID, gcId 11) has a voter account and >= MIN_STAKE
///      — one eligible GC satisfies quorum (quorumCount = (1+2)/3 = 1). Set via multisig
///      admin prank + PD stake top-up; sim-only prerequisites, on live Kairos the GC does this
///   2. Deploy STv3 implementation + ERC1967 proxy, initialized with owner = Voting
///   3. Register STv3 in Registry as "StakingTracker" (prank Registry owner)
///   4. Governance proposal on Voting: updateStakingTracker(STv3) — propose as secretary
///   5. Vote Yes with every eligible GC voter, pass, queue
///   6. During the exec delay, stand in for the ABv2 hardfork: build ABv2 genesis data
///      from live ABv1 + CnStaking + KIP113 state, register ABv2DataContract in Registry,
///      etch the ABv2 proxy over 0x400, initialize, and refresh voters into STv3
///   7. Execute the proposal → Voting.stakingTracker == STv3
///   8. End-to-end verification: run a second (no-op) proposal entirely on STv3
///
/// Simulation-only stand-ins (each logged when applied):
///   - vm.prank for the secretary, GC multisig admins, and Registry owner
///   - vm.etch/vm.store for the ABv2 hardfork code swap at 0x400
///   - fabricated manager/suspender/configurator/KEF/KIF/KPF addresses in ABv2 genesis
///   - vm.mockCall of publicDelegation() for legacy CnStakings that lack the getter
///
/// Usage:
///   forge script script/rehearsal/STv3VotingUpgradeFork.s.sol \
///     --fork-url https://public-en-kairos.node.kaia.io -vv
contract STv3VotingUpgradeFork is Script {
    /* ========== KAIROS CONSTANTS ========== */

    address internal constant VOTING = 0x2C41DdBF0239cEaa75325D66809d0199F368188b;
    address internal constant ADDRESS_BOOK = 0x0000000000000000000000000000000000000400;
    address internal constant REGISTRY = 0x0000000000000000000000000000000000000401;

    /// @dev The single GC activated for the vote (gcId 11). Both live Kairos GCs sit far
    ///      below MIN_STAKE, and one eligible GC is enough: quorumCount = (1+2)/3 = 1,
    ///      so only this node gets a voter account and a stake top-up.
    address internal constant TARGET_NODE_ID = 0xb278157b502e04e2060a5f2bEdC20929d3B6496d;
    uint256 internal constant EPOCH_BLOCK_INTERVAL = 86_400;
    uint8 internal constant VOTE_YES = 1; // IVoting.VoteChoice.Yes
    bytes32 internal constant ERC1967_IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    // IVoting.ProposalState
    uint8 internal constant STATE_PENDING = 0;
    uint8 internal constant STATE_ACTIVE = 1;
    uint8 internal constant STATE_PASSED = 4;
    uint8 internal constant STATE_QUEUED = 5;
    uint8 internal constant STATE_EXECUTED = 7;

    IVotingKairos internal voting = IVotingKairos(VOTING);
    IABv1Kairos internal abv1 = IABv1Kairos(ADDRESS_BOOK);
    IRegistryKairos internal registry = IRegistryKairos(REGISTRY);

    ISTv2Kairos internal stv2;
    address internal secretary;
    StakingTrackerV3 internal stv3;

    // Live ABv1 snapshot (taken once, before the 0x400 code swap)
    address[] internal nodeIds;
    address[] internal stakings;
    address[] internal rewards;

    /* ========== ENTRY ========== */

    function run() external {
        _logInitialState();

        _ensureVoters(); // 1
        _ensureMinStake(); // 1b
        _deploySTv3(); // 2
        _registerSTv3InRegistry(); // 3
        uint256 proposalId = _proposeSwitch(); // 4
        _voteAndQueue(proposalId); // 5
        _hardforkABv2AndRefreshVoters(); // 6
        _executeSwitch(proposalId); // 7
        _verifyEndToEnd(); // 8

        console.log("=== REHEARSAL SUCCESS ===");
    }

    /* ========== 0. SNAPSHOT ========== */

    function _logInitialState() internal {
        stv2 = ISTv2Kairos(voting.stakingTracker());
        secretary = voting.secretary();
        (nodeIds, stakings, rewards,,) = abv1.getAllAddressInfo();

        (bool secretaryPropose,, bool secretaryExecute,) = voting.accessRule();
        require(secretaryPropose && secretaryExecute, "Rehearsal assumes secretary propose/execute access");

        _labelKnownAddresses();

        console.log("=== Initial state ===");
        console.log("Voting:", VOTING);
        console.log("Current StakingTracker (STv2):", address(stv2));
        console.log("Secretary:", secretary);
        console.log("Last proposal id:", voting.lastProposalId());
        console.log("ABv1 node count:", nodeIds.length);
    }

    /// @dev Labels live Kairos addresses so traces read by name instead of raw hex.
    function _labelKnownAddresses() internal {
        vm.label(VOTING, "Voting");
        vm.label(ADDRESS_BOOK, "AddressBook(0x400)");
        vm.label(REGISTRY, "Registry(0x401)");
        vm.label(address(stv2), "StakingTrackerV2");
        vm.label(secretary, "VotingSecretary");
        vm.label(registry.owner(), "RegistryOwner");
        vm.label(TARGET_NODE_ID, "TargetNodeId(gcId11)");

        address targetStaking = _targetStaking();
        vm.label(targetStaking, "CnStakingV3(gcId11)");
        (bool ok, bytes memory ret) = targetStaking.staticcall(abi.encodeWithSignature("publicDelegation()"));
        if (ok && ret.length == 32 && abi.decode(ret, (address)) != address(0)) {
            vm.label(abi.decode(ret, (address)), "PublicDelegation(gcId11)");
        }

        address kip113 = registry.getActiveAddr("KIP113");
        if (kip113 != address(0)) vm.label(kip113, "KIP113");
        address clRegistry = registry.getActiveAddr("CLRegistry");
        if (clRegistry != address(0)) vm.label(clRegistry, "CLRegistry");
    }

    /* ========== 1. VOTER PREREQUISITE ========== */

    /// @dev The switch proposal is tallied on STv2, which only sees CnStakingV2+ contracts.
    ///      On current Kairos the target CnStakingV3 has no voterAddress, so no one could
    ///      cast a vote. Set one through the real multisig path (single-admin,
    ///      requirement=1 on Kairos today), which also syncs STv2's voter mapping via
    ///      the CnStaking -> stakingTracker.refreshVoter callback.
    function _ensureVoters() internal {
        console.log("=== 1. Ensure target GC voter account ===");
        ICnStakingKairos cn = ICnStakingKairos(_targetStaking());
        require(cn.VERSION() >= 2, "Target staking is not CnStakingV2+");
        require(cn.stakingTracker() == address(stv2), "Target staking tracker mismatch");

        uint256 gcId = cn.gcId();
        address voter = cn.voterAddress();
        if (voter != address(0)) {
            if (stv2.voterToGCId(voter) == 0) stv2.refreshVoter(address(cn));
        } else {
            require(cn.requirement() == 1, "Rehearsal only handles requirement=1 multisigs");
            address admin = cn.getRoleMember(cn.ADMIN_ROLE(), 0);
            voter = makeAddr(string.concat("voter_gc", vm.toString(gcId)));
            vm.prank(admin);
            cn.submitUpdateVoterAddress(voter);
        }

        require(stv2.voterToGCId(voter) == gcId, "STv2 voter mapping not set");
        console.log("  gcId", gcId, "voter:", voter);
    }

    function _targetStaking() internal view returns (address) {
        for (uint256 i = 0; i < nodeIds.length; i++) {
            if (nodeIds[i] == TARGET_NODE_ID) return stakings[i];
        }
        revert("Target node not found in AddressBook");
    }

    /* ========== 1b. STAKE PREREQUISITE ========== */

    /// @dev Voting eligibility requires >= 5M KAIA effective stake per GC, but current
    ///      Kairos GCs hold only double-digit KAIA — no GC could vote at all. Top the
    ///      target one up through its PublicDelegation with dealt funds (sim-only
    ///      prerequisite; the live GC must be staked above MIN_STAKE before the real vote).
    function _ensureMinStake() internal {
        console.log("=== 1b. Ensure target GC stake above MIN_STAKE ===");
        uint256 minStake = 5_000_000 ether; // MIN_STAKE, identical in STv2 and STv3
        ICnStakingKairos cn = ICnStakingKairos(_targetStaking());

        uint256 effective = cn.staking() - cn.unstaking();
        if (effective >= minStake) return;

        address pd = cn.publicDelegation();
        require(pd != address(0), "Rehearsal needs PD-enabled CnStaking to top up stake");

        uint256 topUp = minStake - effective + 1 ether;
        address whale = makeAddr(string.concat("whale_gc", vm.toString(cn.gcId())));
        vm.deal(whale, topUp); // sim stand-in for a real delegator's funds
        vm.prank(whale);
        IPublicDelegationKairos(pd).stake{value: topUp}();

        require(cn.staking() - cn.unstaking() >= minStake, "Top-up did not reach MIN_STAKE");
        console.log("  gcId", cn.gcId(), "topped up (KAIA):", topUp / 1e18);
        console.log("  new effective stake (KAIA):", (cn.staking() - cn.unstaking()) / 1e18);
    }

    /* ========== 2. DEPLOY STV3 ========== */

    function _deploySTv3() internal {
        console.log("=== 2. Deploy STv3 (owner = Voting) ===");
        StakingTrackerV3 impl = new StakingTrackerV3();
        bytes memory initCall = abi.encodeCall(StakingTrackerV3.initialize, (VOTING));
        stv3 = StakingTrackerV3(address(new ERC1967Proxy(address(impl), initCall)));
        vm.label(address(impl), "STv3Impl");
        vm.label(address(stv3), "STv3Proxy");

        require(stv3.owner() == VOTING, "STv3 owner mismatch");
        require(stv3.VERSION() == 3, "STv3 version mismatch");
        console.log("STv3 implementation:", address(impl));
        console.log("STv3 proxy:", address(stv3));
    }

    /* ========== 3. REGISTRY: StakingTracker -> STv3 ========== */

    function _registerSTv3InRegistry() internal {
        console.log("=== 3. Register STv3 in Registry ===");
        _registryRegister("StakingTracker", address(stv3));
        require(registry.getActiveAddr("StakingTracker") == address(stv3), "Registry StakingTracker mismatch");
        console.log("Registry[StakingTracker] =", address(stv3));
    }

    function _registryRegister(string memory name, address addr) internal {
        address registryOwner = registry.owner();
        console.log("Registry owner:", registryOwner);
        vm.prank(registryOwner); // sim stand-in for the Registry owner's live tx
        registry.register(name, addr, block.number + 1);
        vm.roll(block.number + 1);
    }

    /* ========== 4. PROPOSE ========== */

    function _proposeSwitch() internal returns (uint256 proposalId) {
        console.log("=== 4. Propose updateStakingTracker(STv3) ===");
        (uint256 minVotingDelay,, uint256 minVotingPeriod,) = voting.timingRule();

        address[] memory targets = new address[](1);
        targets[0] = VOTING;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateStakingTracker(address)", address(stv3));

        vm.prank(secretary);
        proposalId = voting.propose(
            "KGP: upgrade StakingTracker to StakingTrackerV3",
            targets,
            values,
            calldatas,
            minVotingDelay,
            minVotingPeriod
        );
        require(voting.state(proposalId) == STATE_PENDING, "Proposal not Pending");

        uint256 trackerId = stv2.getLastTrackerId();
        (,, uint256 numGCs, uint256 totalVotes, uint256 numEligible) = stv2.getTrackerSummary(trackerId);
        console.log("Proposal id:", proposalId);
        console.log("STv2 tracker id:", trackerId);
        console.log("Tracked GCs / eligible / totalVotes:", numGCs, numEligible, totalVotes);
        require(numEligible > 0, "No eligible GC to vote");
    }

    /* ========== 5. VOTE + QUEUE ========== */

    function _voteAndQueue(uint256 proposalId) internal {
        console.log("=== 5. Vote Yes and queue ===");
        (uint256 voteStart, uint256 voteEnd,,,,,,) = voting.getProposalSchedule(proposalId);

        vm.roll(voteStart);
        require(voting.state(proposalId) == STATE_ACTIVE, "Proposal not Active");

        (uint256[] memory gcIds,, uint256[] memory gcVotes) = stv2.getAllTrackedGCs(stv2.getLastTrackerId());
        uint256 cast;
        for (uint256 i = 0; i < gcIds.length; i++) {
            if (gcVotes[i] == 0) continue;
            address voter = stv2.gcIdToVoter(gcIds[i]);
            if (voter == address(0)) continue;

            vm.prank(voter);
            voting.castVote(proposalId, VOTE_YES);
            cast++;
            console.log("  gcId voted Yes:", gcIds[i], "votes:", gcVotes[i]);
        }
        require(cast > 0, "No vote cast");
        require(voting.checkQuorum(proposalId), "Quorum not reached");

        vm.roll(voteEnd + 1);
        require(voting.state(proposalId) == STATE_PASSED, "Proposal not Passed");

        vm.prank(secretary);
        voting.queue(proposalId);
        require(voting.state(proposalId) == STATE_QUEUED, "Proposal not Queued");
        console.log("Proposal queued");
    }

    /* ========== 6. ABv2 HARDFORK STAND-IN ========== */

    /// @dev STv3.createTracker() reads getAllGovernanceInfo() from 0x400, so ABv2 must be
    ///      live at 0x400 before the first STv3-backed proposal. On a real network this code
    ///      swap happens via hardfork; here vm.etch stands in for it. Runs during the exec
    ///      delay window, i.e. after the switch proposal is queued but before it executes.
    function _hardforkABv2AndRefreshVoters() internal {
        console.log("=== 6. ABv2 hardfork stand-in at 0x400 ===");

        AddressBookV2 impl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);
        ABv2DataContract dataContract = new ABv2DataContract(address(impl), _buildInitDataFromLiveState());
        vm.label(address(impl), "ABv2Impl");
        vm.label(address(dataContract), "ABv2DataContract");
        _registryRegister("ABv2DataContract", address(dataContract));

        // Same pattern as test/stv3/Base.t.sol: the temp proxy initializes its own storage,
        // the etched copy at 0x400 starts with fresh (namespaced) storage and inits again.
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(impl), abi.encodeCall(AddressBookV2.initialize, ()));
        vm.etch(ADDRESS_BOOK, address(tempProxy).code); // sim stand-in for the hardfork
        vm.store(ADDRESS_BOOK, ERC1967_IMPL_SLOT, bytes32(uint256(uint160(address(impl)))));
        AddressBookV2(ADDRESS_BOOK).initialize();

        GovernanceInfo[] memory infos = AddressBookV2(ADDRESS_BOOK).getAllGovernanceInfo();
        require(infos.length == nodeIds.length, "ABv2 governance info count mismatch");
        console.log("ABv2 initialized, nodes:", infos.length);

        // Populate STv3's voter mappings from ABv2 (public, anyone can call)
        for (uint256 i = 0; i < nodeIds.length; i++) {
            stv3.refreshVoter(nodeIds[i]);
        }
        for (uint256 i = 0; i < infos.length; i++) {
            if (infos[i].gcId == 0) continue;
            require(stv3.gcIdToVoter(infos[i].gcId) == infos[i].voterAddress, "STv3 voter mapping mismatch");
            console.log("  STv3 voter for gcId", infos[i].gcId, ":", infos[i].voterAddress);
        }
    }

    /// @dev Builds ABv2 genesis data from the live ABv1 + CnStaking + KIP113 state.
    ///      Fields ABv1 has no notion of (manager, suspender, KEF/KIF/KPF, ...) are
    ///      fabricated for the simulation; on the real migration these come from the
    ///      reviewed abv2-data.json (see DeployABv2DataContract.s.sol).
    function _buildInitDataFromLiveState() internal returns (IABv2DataContract.InitData memory d) {
        (address[] memory blsNodes, BlsPublicKeyInfo[] memory blsKeys) =
            IKIP113Kairos(registry.getActiveAddr("KIP113")).getAllBlsInfo();

        NodeInfo[] memory infos = new NodeInfo[](nodeIds.length);
        address[] memory used = new address[](nodeIds.length * 3);
        uint256 usedCount;

        for (uint256 i = 0; i < nodeIds.length; i++) {
            (uint256 gcId, address voter) = _readGovernanceFields(stakings[i]);

            // ABv2 genesis requires globally unique node/staking/reward addresses.
            address reward = rewards[i];
            if (_contains(used, usedCount, reward)) {
                reward = makeAddr(string.concat("reward_dedup", vm.toString(i)));
                console.log("  [sim] duplicate reward replaced for node:", nodeIds[i]);
            }
            used[usedCount++] = nodeIds[i];
            used[usedCount++] = stakings[i];
            used[usedCount++] = reward;

            _shimPublicDelegation(stakings[i], reward);

            infos[i] = NodeInfo({
                manager: makeAddr(string.concat("manager", vm.toString(i))), // sim placeholder
                stakingContract: stakings[i],
                rewardAddress: reward,
                voterAddress: voter,
                timeoutAt: 0,
                gcId: gcId,
                blsInfo: _findBlsInfo(blsNodes, blsKeys, nodeIds[i], i),
                name: string.concat("kairos-node-", vm.toString(i)),
                metadata: "",
                state: State.Unknown // overwritten to ValActive by ABv2.initialize
            });
        }

        d = IABv2DataContract.InitData({
            initialOwner: VOTING,
            initialSuspender: makeAddr("suspender"), // sim placeholder
            initialConfigurator: makeAddr("configurator"), // sim placeholder
            pfsThreshold: 2,
            cfsThreshold: 300,
            pauseTimeout: 8 hours,
            idleTimeout: 7 days,
            maxNodeCount: 100,
            maxValActivePausedCount: 50,
            maxCandReadyCount: 3,
            kefAddress: makeAddr("kef"), // sim placeholder
            kifAddress: makeAddr("kif"), // sim placeholder
            kpfAddress: makeAddr("kpf"), // sim placeholder
            nodeIds: nodeIds,
            infos: infos
        });
    }

    /// @dev gcId/voterAddress exist on CnStakingV2+; legacy V1 nodes stay gcId=0 and are
    ///      filtered out of governance by both ABv2.getAllGovernanceInfo and STv3.
    function _readGovernanceFields(address staking) internal view returns (uint256 gcId, address voter) {
        (bool ok, bytes memory ret) = staking.staticcall(abi.encodeCall(ICnStakingKairos.gcId, ()));
        if (!ok || ret.length == 0) return (0, address(0));
        gcId = abi.decode(ret, (uint256));
        voter = ICnStakingKairos(staking).voterAddress();
    }

    /// @dev ABv2 genesis validation calls publicDelegation() on every staking contract and
    ///      requires it to be zero or equal to the reward address. Legacy CnStakings don't
    ///      have the getter, and reward addresses deduped above would no longer match; mock
    ///      those to zero (simulation shim only).
    function _shimPublicDelegation(address staking, address reward) internal {
        (bool ok, bytes memory ret) = staking.staticcall(abi.encodeWithSignature("publicDelegation()"));
        bool needsShim = !ok || ret.length == 0 || _asAddress(ret) != address(0) && _asAddress(ret) != reward;
        if (needsShim) {
            vm.mockCall(staking, abi.encodeWithSignature("publicDelegation()"), abi.encode(address(0)));
            console.log("  [sim] publicDelegation() mocked to zero for:", staking);
        }
    }

    function _asAddress(bytes memory ret) internal pure returns (address) {
        return abi.decode(ret, (address));
    }

    function _findBlsInfo(address[] memory blsNodes, BlsPublicKeyInfo[] memory blsKeys, address nodeId, uint256 salt)
        internal
        pure
        returns (BlsPublicKeyInfo memory)
    {
        for (uint256 i = 0; i < blsNodes.length; i++) {
            if (blsNodes[i] == nodeId) return blsKeys[i];
        }
        // Placeholder for nodes missing from KIP113 (simulation shim only)
        console.log("  [sim] placeholder BLS key for node:", nodeId);
        bytes memory pk = new bytes(48);
        pk[0] = bytes1(uint8(salt + 1));
        bytes memory pop = new bytes(96);
        pop[0] = bytes1(uint8(salt + 1));
        return BlsPublicKeyInfo({publicKey: pk, pop: pop});
    }

    function _contains(address[] memory arr, uint256 len, address x) internal pure returns (bool) {
        for (uint256 i = 0; i < len; i++) {
            if (arr[i] == x) return true;
        }
        return false;
    }

    /* ========== 7. EXECUTE ========== */

    function _executeSwitch(uint256 proposalId) internal {
        console.log("=== 7. Execute the switch ===");
        (,,, uint256 eta,,,,) = voting.getProposalSchedule(proposalId);
        vm.roll(eta);

        // Retire expired trackers, mirroring what updateStakingTracker does internally,
        // so the remaining-live-tracker sanity check is meaningful.
        stv2.refreshStake(address(0));
        require(stv2.getLiveTrackerIds().length == 0, "STv2 still has live trackers");
        vm.prank(secretary);
        voting.execute(proposalId);

        require(voting.state(proposalId) == STATE_EXECUTED, "Proposal not Executed");
        require(voting.stakingTracker() == address(stv3), "Voting.stakingTracker != STv3");
        console.log("Voting.stakingTracker:", voting.stakingTracker());
    }

    /* ========== 8. END-TO-END VERIFICATION ON STV3 ========== */

    /// @dev Full proposal lifecycle on the new tracker: propose (STv3.createTracker via
    ///      ABv2 governance info), vote with STv3-mapped voters, queue, execute a no-op.
    function _verifyEndToEnd() internal {
        console.log("=== 8. Post-upgrade proposal lifecycle on STv3 ===");
        (uint256 minVotingDelay,, uint256 minVotingPeriod,) = voting.timingRule();

        address[] memory targets = new address[](1);
        targets[0] = VOTING;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateSecretary(address)", secretary); // no-op action

        vm.prank(secretary);
        uint256 proposalId = voting.propose(
            "Rehearsal: verify STv3 proposal lifecycle", targets, values, calldatas, minVotingDelay, minVotingPeriod
        );

        uint256 trackerId = stv3.getLastTrackerId();
        require(trackerId == 1, "STv3 tracker not created");
        (,, uint256 numGCs, uint256 totalVotes, uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        console.log("STv3 tracker GCs / eligible / totalVotes:", numGCs, numEligible, totalVotes);
        require(numEligible > 0, "No eligible GC in STv3 tracker");

        (uint256 voteStart, uint256 voteEnd,,,,,,) = voting.getProposalSchedule(proposalId);
        vm.roll(voteStart);

        (uint256[] memory gcIds,, uint256[] memory gcVotes) = stv3.getAllTrackedGCs(trackerId);
        uint256 cast;
        for (uint256 i = 0; i < gcIds.length; i++) {
            if (gcVotes[i] == 0) continue;
            address voter = stv3.gcIdToVoter(gcIds[i]);
            if (voter == address(0)) continue;

            (uint256 gcId, uint256 votes) = voting.getVotes(proposalId, voter);
            require(gcId == gcIds[i] && votes == gcVotes[i], "getVotes mismatch on STv3");

            vm.prank(voter);
            voting.castVote(proposalId, VOTE_YES);
            cast++;
        }
        require(cast > 0, "No vote cast on STv3 proposal");
        require(voting.checkQuorum(proposalId), "Quorum not reached on STv3 proposal");

        vm.roll(voteEnd + 1);
        vm.prank(secretary);
        voting.queue(proposalId);

        (,,, uint256 eta,,,,) = voting.getProposalSchedule(proposalId);
        vm.roll(eta);
        vm.prank(secretary);
        voting.execute(proposalId);

        require(voting.state(proposalId) == STATE_EXECUTED, "STv3 proposal not Executed");
        require(voting.secretary() == secretary, "Secretary changed unexpectedly");
        console.log("STv3-backed proposal executed, id:", proposalId);
    }
}
