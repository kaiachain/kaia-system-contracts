// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ABv1ForkCommon} from "./ABv1ForkCommon.sol";
import {IMainnetMultiSig} from "./ABv1PdOffMultiSigForkBase.sol";
import {IMainnetV2AdminGetter} from "./ABv1V2SwapFork.s.sol";
import {IMainnetV3AdminGetter} from "./ABv1V3SwapFork.s.sol";
import {IV3PDV1} from "./ABv1V3PdOnSwapFork.s.sol";
import {StakingTrackerV3} from "../../src/StakingTrackerV3/StakingTrackerV3.sol";
import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {ABv2DataContract} from "../../src/AddressBookV2/ABv2DataContract.sol";
import {IABv2DataContract} from "../../src/AddressBookV2/interfaces/IABv2DataContract.sol";
import {CnStakingV4} from "../../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {CnStakingV4Factory} from "../../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";
import {IPublicDelegation} from "../../src/PublicDelegation/interfaces/IPublicDelegation.sol";
import {CnStakingDelegator} from "../../src/Delegator/CnStakingDelegator.sol";
import {PublicDelegationDelegator} from "../../src/Delegator/PublicDelegationDelegator.sol";
import {NodeInfo, BlsPublicKeyInfo, GovernanceInfo, State} from "../../src/types/Node.sol";

/* ========== MAINNET LIVE CONTRACT INTERFACES ========== */

/// @dev Mainnet Voting contract (contracts-klaytn-v1.10 Voting.sol)
interface IVotingLive {
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
}

/// @dev Mainnet StakingTrackerV2 (contracts-v2.0 StakingTrackerV2.sol)
interface ISTv2Live {
    function refreshStake(address staking) external;
    function getLastTrackerId() external view returns (uint256);
    function getLiveTrackerIds() external view returns (uint256[] memory);
    function getTrackerSummary(uint256 trackerId) external view returns (uint256, uint256, uint256, uint256, uint256);
    function getAllTrackedGCs(uint256 trackerId)
        external
        view
        returns (uint256[] memory, uint256[] memory, uint256[] memory);
    function gcIdToVoter(uint256 gcId) external view returns (address);
}

/// @dev Mainnet Registry (0x401)
interface IRegistryLive {
    function owner() external view returns (address);
    function register(string memory name, address addr, uint256 activation) external;
    function getActiveAddr(string memory name) external view returns (address);
}

/// @dev Live CnStakingV2/V3 read surface (pre-migration snapshot)
interface ICnStakingLive {
    function VERSION() external view returns (uint256);
    function gcId() external view returns (uint256);
    function voterAddress() external view returns (address);
    function stakingTracker() external view returns (address);
    function staking() external view returns (uint256);
    function unstaking() external view returns (uint256);
    function publicDelegation() external view returns (address);
}

/// @dev Legacy V2/V3 initial-lockup surface. Both multisigs expose the same functions and
///      `Functions.WithdrawLockupStaking` sits at the same enum index (ICnStakingV2.sol:116-128,
///      ICnStakingV3MultiSig.sol:46-59).
interface ILegacyLockupLive {
    function remainingLockupStaking() external view returns (uint256);
    function getLockupStakingInfo()
        external
        view
        returns (
            uint256[] memory unlockTime,
            uint256[] memory unlockAmount,
            uint256 initial,
            uint256 remaining,
            uint256 withdrawable
        );
    function submitWithdrawLockupStaking(address to, uint256 value) external;
}

/// @dev Mainnet SimpleBlsRegistry / KIP113 (UUPS, OwnableUpgradeable)
interface ISBRLive {
    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
    function getAllBlsInfo() external view returns (address[] memory, BlsPublicKeyInfo[] memory);
}

/// @dev Legacy per-GC Delegator (contracts-v1.0/contracts/Delegator.sol), deployed on
///      mainnet for delegation-funded PD-on GCs — addresses live in
///      contracts-v1.0/deployments/cypress/Delegator#*.json.
interface ILegacyDelegator {
    function PD() external view returns (address);
    function delegation() external view returns (uint256);
    function withdrawableReward() external view returns (uint256);
    function withdrawDelegation(address to, uint256 amount) external;
    function withdrawReward(address to, uint256 amount) external;
    function claimDelegation(uint256 id) external;
    function claimReward(uint256 id) external;
    function delegationWithdrawalIds() external view returns (uint256[] memory);
    function rewardWithdrawalIds() external view returns (uint256[] memory);
    function DELEGATOR_ROLE() external view returns (bytes32);
    function DELEGATEE_ROLE() external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
}

/// @dev Mainnet CLRegistry — maps CL (concentrated-liquidity DEX) pools to gcIds. STv3 reads
///      it to fold CL-pool WrappedKaia liquidity into a GC's voting power.
interface ICLRegistryLive {
    function getAllCLs()
        external
        view
        returns (address[] memory nodeIds, uint256[] memory gcIds, address[] memory pools);
}

interface IERC20Live {
    function balanceOf(address account) external view returns (uint256);
}

/// @title MainnetFullMigrationFork
/// @notice Mainnet-fork rehearsal of the COMPLETE v3.0 migration:
///         GC voting (StakingTracker switch), CnStaking V2/V3 -> V4 migration for every GC,
///         VMC sunset, and the ABv1 -> ABv2 hardfork.
///
/// Ordering constraints this sequence honors: both Registry entries and the vote's
/// execute land before the first V4 (once a V4 enters the legacy AddressBook, STv2-based
/// propose() reverts, so a deferred switch would deadlock governance), and execute
/// requires no Pending proposal (no live trackers).
///
/// Phases:
///   1.  Deploy STv3 (implementation + ERC1967 UUPS proxy, owner = Voting)
///   2.  Register STv3 in Registry as "StakingTracker"
///   3.  GC Voting: propose updateStakingTracker(STv3), vote Yes with every live voter,
///       queue, and EXECUTE -> Voting.stakingTracker == STv3. This begins the INTENDED
///       voting freeze: propose() now routes to STv3.createTracker, which needs ABv2 at
///       0x400, so no proposal can be created until the hardfork (verified in 3c).
///       (Proposing must precede the CnStaking migration — the proposal is tallied on STv2,
///       which can only read CnStakingV2/V3 contracts.)
///   4.  System contract deployment (except STv3): CnStakingV4 impl, PublicDelegation impl,
///       both UpgradeableBeacons (owner = Voting), CnStakingV4Factory, AddressBookV2 impl
///   5.  Register CnStakingFactory in Registry (must precede the first V4:
///       V4.redelegate and ABv2.createNode read it)
///   6.  CnStaking migration per the GC migration runbook,
///       following its D-7 / 7-day lockup / D-day timeline for each committee GC:
///         §1 PD-off (V2/V3, no PD)     — multisig approve -> withdraw -> owner delegates to V4
///         §2 PD-on (V3 + PD)           — PD redeem -> claim -> holder stakes into V4 PD
///         §3 Delegator (KF-funded)     — PD-on: detected via the legacy Delegator registry
///                                        (contracts-v1.0 deployments); funder principal exits
///                                        via withdrawDelegation/claimDelegation and re-enters
///                                        through a new PublicDelegationDelegator, delegatee
///                                        reward is claimed but not restaked. PD-off: detected
///                                        via shared-admin sibling pots, consolidated through
///                                        a new CnStakingDelegator. DELEGATOR_NODES adds
///                                        cases known only off-chain.
///       Initial lockup still held by a legacy contract (remainingLockupStaking, which
///       staking() excludes) is withdrawn on D-day through submitWithdrawLockupStaking —
///       executed in the confirming tx once unlockTime has passed — and restaked with the
///       GC's own pot, because STv3 and the post-fork client count V4 staking() only.
///       Every GC eligible today (balance-based, initial lockup included) must stay eligible
///       on STv3; the run fails otherwise.
///   7.  Sunset VMC: AddressBook admins and SimpleBlsRegistry ownership -> the Registry
///       owner (recipient stand-in; between migration completion and data-contract
///       finalization)
///   8.  Deploy ABv2DataContract (genesis built from post-migration live state — registered
///       last because NodeInfo[] is only final after the migration), register it in
///       Registry, etch ABv2 over 0x400 (hardfork stand-in), initialize, refresh voters
///       into STv3 — the hardfork ends the voting freeze
///   9.  End-to-end verification: full no-op proposal lifecycle on STv3 + ABv2 + V4
///
/// Node filtering: ABv1 holds 42 entries, but 9 are dummy nodes (multi-node GCs' inactive
/// siblings — absent from kaia_getCommittee, no KIP113 BLS key, reward shared with the real
/// node). They retire with ABv1 at the hardfork, so only the 33 committee members are
/// migrated and carried into ABv2 genesis.
///
/// Simulation-only stand-ins (each logged when applied):
///   - vm.prank for the secretary, GC voters, legacy CnStaking admins, VMC admins,
///     Registry owner, SBR owner
///   - vm.warp for the 7-day STAKE_LOCKUP between D-7 and D-day
///   - PD-on: the GC's V3 PD share is seeded by staking fresh KAIA right before redeeming
///     (the real GC-owned holder address is off-chain knowledge; same as ABv1V3PdOnSwapFork)
///   - vm.etch/vm.store for the ABv2 hardfork code swap at 0x400
///   - fabricated CnStakingOwners, managers, suspender/configurator/KEF/KIF/KPF in ABv2
///     genesis (real values come from the reviewed abv2-data.json)
///
/// Usage:
///   forge script script/rehearsal/MainnetFullMigrationFork.s.sol \
///     --fork-url https://public-en.node.kaia.io -vv
contract MainnetFullMigrationFork is ABv1ForkCommon {
    /* ========== MAINNET CONSTANTS ========== */
    // ADDRESS_BOOK, MIN_STAKE, and the `abv1` handle come from ABv1ForkCommon.

    address internal constant VOTING = 0xcA4Ef926634A530f12e55A0aEE87F195A7B22Aa3;
    address internal constant REGISTRY = 0x0000000000000000000000000000000000000401;
    uint256 internal constant EPOCH_BLOCK_INTERVAL = 86_400;
    uint8 internal constant VOTE_YES = 1; // IVoting.VoteChoice.Yes
    bytes32 internal constant ERC1967_IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    // IVoting.ProposalState
    uint8 internal constant STATE_PENDING = 0;
    uint8 internal constant STATE_ACTIVE = 1;
    uint8 internal constant STATE_PASSED = 4;
    uint8 internal constant STATE_QUEUED = 5;
    uint8 internal constant STATE_EXECUTED = 7;

    IVotingLive internal voting = IVotingLive(VOTING);
    IRegistryLive internal registry = IRegistryLive(REGISTRY);

    /* ========== SNAPSHOT & DEPLOYED STATE ========== */

    /// @dev CnStaking migration scenario per the GC migration runbook.
    enum Scenario {
        PdOff, // manual §1: V2/V3 without PublicDelegation — multisig unstake, owner delegates into V4
        PdOn, // manual §2: V3 with PublicDelegation — PD redeem/claim, holder stakes into V4 PD
        DelegatorPdOff, // manual §3, PD-off variant: funder delegates via CnStakingDelegator
        DelegatorPdOn // manual §3, PD-on variant: funder delegates via PublicDelegationDelegator
    }

    /// @dev Per-GC snapshot taken before any mutation. gcId/voter live only on the legacy
    ///      V2/V3 contracts (V4 has no identity fields), so they must be captured up front.
    struct GC {
        address nodeId;
        address oldStaking;
        address oldPd; // V3 PublicDelegationV1, zero when PD-off
        address reward; // deduped in phase 6; for PD-on scenarios replaced by the new V4 PD
        uint256 gcId;
        address voter;
        uint256 effectiveStake; // staking() - unstaking() at snapshot time
        uint256 balanceStake; // balance - unstaking() over own + sibling pots: what STv2 counts
        bool eligibleToday; // balanceStake >= MIN_STAKE at snapshot time
        Scenario scenario;
        // Sibling (dummy-node) CnStakings under the same gcId. For KF-delegation GCs
        // (via DELEGATOR_NODES) the pot is the foundation's delegated stake and consolidates
        // through the §3 delegator as the funder's portion; otherwise it is the GC's own
        // stake (legacy multi-contract) and consolidates directly into the GC's V4.
        address[] siblingStakings;
        uint256[] siblingIds; // withdrawal ids on the siblings (valid where siblingAmounts > 0)
        uint256[] siblingAmounts;
        // Filled during phase 6:
        address gcOwner; // CnStakingOwner per the manual (fabricated per node)
        address newStaking; // V4 proxy
        address newPd; // V4 PublicDelegationV2 (PD-on scenarios)
        address holder; // committee-node extraction recipient (gcOwner, or pdHolder for PD-on)
        address funder; // §3: DELEGATOR_ROLE holder (real funder for PD-on, fabricated for pot-based PD-off)
        address delegatee; // §3 PD-on: real DELEGATEE_ROLE holder from the legacy delegator
        address oldDelegator; // §3 PD-on: legacy Delegator (contracts-v1.0) holding the funder position
        address delegatorContract; // manual §3: the NEW delegator deployed in phase 6
        uint256 extractAmount; // KAIA leaving the committee node's legacy contract (GC's own pot)
        uint256 withdrawalId; // PD-off: CnStaking withdrawal id; PD-on: PD claim request id
        uint256 funderAmount; // §3 PD-on: funder principal leaving the legacy delegator
        uint256 funderClaimId;
        uint256 rewardAmount; // §3 PD-on: delegatee reward leaving the legacy delegator
        uint256 rewardClaimId;
        uint256 lockupAmount; // initial lockup withdrawn on D-day (own pot + sibling pots)
    }

    GC[] internal gcs;

    /// @dev manual §3 (Delegator) membership. PD-on KF delegation (legacy Delegator
    ///      contract on the PD) is auto-detected. PD-off KF delegation (via a separate
    ///      dummy CnStaking) is NOT reliably detectable on-chain, so the affected GCs are
    ///      supplied here via DELEGATOR_NODES (comma-separated committee nodeIds).
    address[] internal delegatorNodes;

    /// @dev All legacy Delegator deployments on mainnet, from
    ///      contracts-v1.0/deployments/cypress/Delegator#*.json (Bisonai, Bughole, Certik,
    ///      Cosmostation, Delight, GGL, LineXenesis, Sega, StableLab, Verichains, X2eAll,
    ///      Xangle). Matched to GCs via ILegacyDelegator.PD().
    address[12] internal LEGACY_DELEGATORS = [
        0x0668F1d6c30f42670Ca5fD9597C997212C451C13,
        0x205561128130AAAB490FeF874640b34508762A4d,
        0x2390A1c008F713dEA8dF743217C94655Ece5A735,
        0xE653299dd1a7475051369e3Bfc76B03FF4eF0F03,
        0x4d0bE874F971f2A7523B77640D99516946BbcB91,
        0x90B1Cb59C789B890a95De337921727F40Fe78E84,
        0x5098ceaaDD5C70A4227b3d6E1995944e927b6fE0,
        0x08332d123357BE68f59fb0fE55FabB5B8F6Bf253,
        0xEC99cd28C0F587A94C5EF3ea1232B78b8a1661fd,
        0x94C6b78d867c6dD58Fcee13B2Ec28904F86Bd9Ef,
        0x04ca5B0A633504a7822d79B1a363b40375d035c0,
        0x3c2f1397291CeFfB253972ad21E4a481cc9Bd1E3
    ];

    ISTv2Live internal stv2;
    ISBRLive internal sbr;
    address internal secretary;
    address internal registryOwner; // Registry owner; sunset recipient stand-in

    StakingTrackerV3 internal stv3;
    CnStakingV4Factory internal factory;
    AddressBookV2 internal abv2Impl;

    /* ========== ENTRY ========== */

    function run() external {
        _snapshot(); // 0

        _deploySTv3(); // 1
        _registerSTv3(); // 2
        uint256 proposalId = _proposeAndVote(); // 3
        _executeSTv3Switch(proposalId); // 3b - voting freeze begins (intended)
        _verifyGovernanceFrozen(); // 3c
        _deploySystemContracts(); // 4
        _registerFactory(); // 5
        _migrateCnStakings(); // 6
        _sunsetVMC(); // 7
        _deployABv2AndInitialize(); // 8 - hardfork ends the voting freeze
        _verifyEndToEnd(); // 9

        console.log("=== REHEARSAL SUCCESS ===");
    }

    /* ========== 0. SNAPSHOT ========== */

    function _snapshot() internal {
        stv2 = ISTv2Live(voting.stakingTracker());
        secretary = voting.secretary();
        registryOwner = registry.owner();
        sbr = ISBRLive(registry.getActiveAddr("KIP113"));

        (bool secretaryPropose,, bool secretaryExecute,) = voting.accessRule();
        require(secretaryPropose && secretaryExecute, "Rehearsal assumes secretary propose/execute access");

        _labelKnownAddresses();

        (address[] memory nodeIds, address[] memory stakings, address[] memory rewards,,) = abv1.getAllAddressInfo();

        // ABv1 contains dummy node entries (multi-node GCs' inactive siblings) that never
        // validate: they are absent from kaia_getCommittee, hold no KIP113 BLS key, and
        // share their reward address with the GC's real node. They retire with ABv1 at the
        // hardfork, so only committee members are migrated and carried into ABv2 genesis.
        address[] memory committee = abi.decode(
            vm.rpc("kaia_getCommittee", string.concat("[\"", _hexQuantity(block.number), "\"]")), (address[])
        );
        console.log("Committee size:", committee.length);

        delegatorNodes = vm.envOr("DELEGATOR_NODES", ",", new address[](0));

        // Pass 1: committee nodes become migration entries.
        for (uint256 i = 0; i < nodeIds.length; i++) {
            ICnStakingLive cn = ICnStakingLive(stakings[i]);
            require(cn.VERSION() >= 2, "Unexpected legacy CnStakingV1 on mainnet");
            if (!_contains(committee, committee.length, nodeIds[i])) continue;

            _flagPendingUnstaking(stakings[i], cn.gcId());

            GC memory gc;
            gc.nodeId = nodeIds[i];
            gc.oldStaking = stakings[i];
            gc.oldPd = _readPublicDelegation(stakings[i]);
            gc.reward = rewards[i]; // deduped in phase 6 before it is baked into V4/ABv1/ABv2
            gc.gcId = cn.gcId();
            gc.voter = cn.voterAddress();
            gc.effectiveStake = cn.staking() - cn.unstaking();
            gcs.push(gc);
        }

        // Pass 2: dummy nodes attach as sibling pots of their gcId's committee entry.
        for (uint256 i = 0; i < nodeIds.length; i++) {
            if (_contains(committee, committee.length, nodeIds[i])) continue;
            uint256 gcId = ICnStakingLive(stakings[i]).gcId();
            bool attached;
            for (uint256 j = 0; j < gcs.length; j++) {
                if (gcs[j].gcId == gcId) {
                    gcs[j].siblingStakings.push(stakings[i]);
                    attached = true;
                    break;
                }
            }
            if (attached) {
                _flagPendingUnstaking(stakings[i], gcId);
                console.log("  sibling pot attached to gcId", gcId, "from dummy node:", nodeIds[i]);
            } else {
                console.log("  skip (dummy node without committee sibling):", nodeIds[i]);
            }
        }

        // Pass 3: categorize per the GC migration runbook. KF delegation exists in two
        // distinct mechanisms, detected separately:
        //   PD-on : the GC's PD has a deployed legacy Delegator contract holding the
        //           foundation's position (Bisonai/X2eAll/... — reliable on-chain signal).
        //   PD-off: KF delegation via a separate (dummy-node) CnStaking pot. This is NOT
        //           reliably detectable on-chain, so the affected GCs must be supplied
        //           via DELEGATOR_NODES.
        // NOTE: a shared-admin heuristic was tried and removed — it flagged legacy
        //       multi-CnStaking GCs (e.g. SwapScanner/Metabora) that are the GC's OWN
        //       stake, and missed the real KF-delegation GCs. Multi-CnStaking GCs that are
        //       not delegators consolidate their sibling pots as the GC's own stake.
        uint256[4] memory scenarioCounts;
        for (uint256 j = 0; j < gcs.length; j++) {
            GC storage gc = gcs[j];

            // Eligibility as counted today: STv2 (StakingTrackerV2.sol:494) and the pre-fork
            // client (MultiCallContract._getCnStakingAmountsLegacy) use the contract balance
            // net of pending withdrawals, consolidated per GC — initial lockup included.
            // STv3 and the post-fork client use staking() - unstaking() of the V4 instead,
            // so lockup-funded GCs only stay eligible if the lockup is migrated too.
            gc.balanceStake = _balanceStake(gc.oldStaking);
            uint256 effective = gc.effectiveStake;
            for (uint256 k = 0; k < gc.siblingStakings.length; k++) {
                gc.balanceStake += _balanceStake(gc.siblingStakings[k]);
                ICnStakingLive sib = ICnStakingLive(gc.siblingStakings[k]);
                effective += sib.staking() - sib.unstaking();
            }
            gc.eligibleToday = gc.balanceStake >= MIN_STAKE;
            if (gc.eligibleToday && effective < MIN_STAKE) {
                console.log(
                    "  [note] eligible today only through initial lockup, gcId / lockup (KAIA):",
                    gc.gcId,
                    (gc.balanceStake - effective) / 1e18
                );
            }

            gc.oldDelegator = _findLegacyDelegator(gc.oldPd);
            bool isDelegator =
                gc.oldDelegator != address(0) || _contains(delegatorNodes, delegatorNodes.length, gc.nodeId);
            gc.scenario = gc.oldPd != address(0)
                ? (isDelegator ? Scenario.DelegatorPdOn : Scenario.PdOn)
                : (isDelegator ? Scenario.DelegatorPdOff : Scenario.PdOff);
            scenarioCounts[uint256(gc.scenario)]++;

            // Product GCs (e.g. NEOPIN) legitimately run multiple staking contracts under
            // one nodeId; this sim collapses siblings into one V4, which such GCs may not
            // want. Flag non-delegator multi-CnStaking GCs for manual review.
            if (gc.siblingStakings.length > 0 && !isDelegator) {
                console.log(
                    "  [review] multi-CnStaking non-delegator GC, siblings consolidated as own stake, gcId:", gc.gcId
                );
            }
        }
        console.log("Scenario counts - PdOff / PdOn / DelegatorPdOff / DelegatorPdOn:");
        console.log("  ", scenarioCounts[0], scenarioCounts[1]);
        console.log("  ", scenarioCounts[2], scenarioCounts[3]);
        console.log("Eligible today (balance-based, >= MIN_STAKE):", _eligibleTodayCount());

        console.log("=== Initial mainnet state ===");
        console.log("Voting:", VOTING);
        console.log("Current StakingTracker (STv2):", address(stv2));
        console.log("Secretary:", secretary);
        console.log("Registry owner (sunset recipient):", registryOwner);
        console.log("SBR (KIP113):", address(sbr));
        console.log("SBR owner:", sbr.owner());
        console.log("Last proposal id:", voting.lastProposalId());
        console.log("AB nodes:", nodeIds.length);
        console.log("Committee nodes to migrate:", gcs.length);
    }

    /// @dev Labels live mainnet addresses so traces read by name instead of raw hex.
    function _labelKnownAddresses() internal {
        vm.label(VOTING, "Voting");
        vm.label(ADDRESS_BOOK, "AddressBook(0x400)");
        vm.label(REGISTRY, "Registry(0x401)");
        vm.label(address(stv2), "StakingTrackerV2");
        vm.label(secretary, "VotingSecretary");
        vm.label(registryOwner, "RegistryOwner");
        vm.label(address(sbr), "SimpleBlsRegistry(KIP113)");
        vm.label(sbr.owner(), "VMC(SbrOwner)");

        (address[] memory admins,) = abv1.getState();
        for (uint256 i = 0; i < admins.length; i++) {
            vm.label(admins[i], string.concat("VMCAdmin", vm.toString(i)));
        }

        address clRegistry = registry.getActiveAddr("CLRegistry");
        if (clRegistry != address(0)) vm.label(clRegistry, "CLRegistry");
        address wKaia = registry.getActiveAddr("WrappedKaia");
        if (wKaia != address(0)) vm.label(wKaia, "WrappedKaia");
    }

    /* ========== 1. DEPLOY STV3 ========== */

    function _deploySTv3() internal {
        console.log("=== 1. Deploy STv3 (owner = Voting) ===");
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

    /* ========== 2. REGISTRY: StakingTracker -> STV3 ========== */

    function _registerSTv3() internal {
        console.log("=== 2. Register STv3 in Registry ===");
        _registryRegister("StakingTracker", address(stv3));
        require(registry.getActiveAddr("StakingTracker") == address(stv3), "Registry StakingTracker mismatch");
        console.log("Registry[StakingTracker] =", address(stv3));
    }

    function _registryRegister(string memory name, address addr) internal {
        address regOwner = registry.owner();
        console.log("Registry owner:", regOwner);
        vm.prank(regOwner); // sim stand-in for the Registry owner's live tx
        registry.register(name, addr, block.number + 1);
        vm.roll(block.number + 1);
    }

    /* ========== 3. GC VOTING (PROPOSE + VOTE + QUEUE) ========== */

    /// @dev Runs before the CnStaking migration on purpose: the proposal's tally tracker is
    ///      created on STv2 from the live V2/V3 contracts. Execution follows immediately
    ///      (phase 3b) and begins the intended voting freeze that lasts until the hardfork.
    function _proposeAndVote() internal returns (uint256 proposalId) {
        console.log("=== 3. GC Voting: propose updateStakingTracker(STv3) ===");
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
        console.log("STv2 tracker GCs / eligible / totalVotes:", numGCs, numEligible, totalVotes);
        console.log("Eligible today (balance-based snapshot, committee GCs):", _eligibleTodayCount());
        require(numEligible > 0, "No eligible GC to vote");

        _castAllVotesOnSTv2(proposalId, trackerId);

        (, uint256 voteEnd,,,,,,) = voting.getProposalSchedule(proposalId);
        vm.roll(voteEnd + 1);
        require(voting.state(proposalId) == STATE_PASSED, "Proposal not Passed");

        vm.prank(secretary);
        voting.queue(proposalId);
        require(voting.state(proposalId) == STATE_QUEUED, "Proposal not Queued");
        console.log("Proposal queued");
    }

    function _castAllVotesOnSTv2(uint256 proposalId, uint256 trackerId) internal {
        (uint256 voteStart,,,,,,,) = voting.getProposalSchedule(proposalId);
        vm.roll(voteStart);
        require(voting.state(proposalId) == STATE_ACTIVE, "Proposal not Active");

        (uint256[] memory gcIds,, uint256[] memory gcVotes) = stv2.getAllTrackedGCs(trackerId);
        uint256 cast;
        uint256 castVotes;
        for (uint256 i = 0; i < gcIds.length; i++) {
            if (gcVotes[i] == 0) continue;
            address voter = stv2.gcIdToVoter(gcIds[i]);
            if (voter == address(0)) continue;

            vm.prank(voter); // sim stand-in for each GC voter's live tx
            voting.castVote(proposalId, VOTE_YES);
            cast++;
            castVotes += gcVotes[i];
        }
        console.log("Voters cast / votes cast:", cast, castVotes);
        require(voting.checkQuorum(proposalId), "Quorum not reached");
    }

    /* ========== 4. SYSTEM CONTRACT DEPLOYMENT (EXCEPT STV3) ========== */

    function _deploySystemContracts() internal {
        console.log("=== 4. Deploy system contracts (V4 impl, PD impl, beacons, factory, ABv2 impl) ===");

        // Beacon owner must be the Voting contract: beacon upgrades affect every deployed
        // CnStaking/PD proxy at once (see DeployBeaconsAndFactory.s.sol).
        factory = _deployV4Infra(makeAddr("deployer"), VOTING);
        abv2Impl = new AddressBookV2(EPOCH_BLOCK_INTERVAL);

        address cnBeacon = factory.cnStakingBeacon();
        address pdBeacon = factory.pdBeacon();
        vm.label(UpgradeableBeacon(cnBeacon).implementation(), "CnStakingV4Impl");
        vm.label(UpgradeableBeacon(pdBeacon).implementation(), "PublicDelegationImpl");
        vm.label(cnBeacon, "CnStakingBeacon");
        vm.label(pdBeacon, "PDBeacon");
        vm.label(address(factory), "CnStakingV4Factory");
        vm.label(address(abv2Impl), "ABv2Impl");

        console.log("CnStakingV4 implementation:", UpgradeableBeacon(cnBeacon).implementation());
        console.log("PublicDelegation implementation:", UpgradeableBeacon(pdBeacon).implementation());
        console.log("CnStaking beacon:", cnBeacon);
        console.log("PD beacon:", pdBeacon);
        console.log("CnStakingV4Factory:", address(factory));
        console.log("AddressBookV2 implementation:", address(abv2Impl));

        require(UpgradeableBeacon(cnBeacon).owner() == VOTING, "cnBeacon owner != Voting");
        require(UpgradeableBeacon(pdBeacon).owner() == VOTING, "pdBeacon owner != Voting");
    }

    /* ========== 5. REGISTRY: CnStakingFactory ========== */

    function _registerFactory() internal {
        console.log("=== 5. Register CnStakingFactory in Registry ===");
        _registryRegister("CnStakingFactory", address(factory));
        require(registry.getActiveAddr("CnStakingFactory") == address(factory), "Registry CnStakingFactory mismatch");
        console.log("Registry[CnStakingFactory] =", address(factory));
    }

    /* ========== 6. CNSTAKING MIGRATION (per the GC migration runbook) ========== */

    /// @dev Follows the GC migration runbook timeline for every committee GC:
    ///        D-7 : [KF] deploy V4 (+PD), [GC] verify + setLegacyAbv1Info, [GC] submit
    ///              unstake (multisig approve / PD redeem), [KF] deploy delegator (§3)
    ///        7-day STAKE_LOCKUP wait (vm.warp)
    ///        D-day: [GC] withdraw/claim, [GC] fund V4 (delegate / PD stake / via delegator),
    ///              [KF] ABv1 swap, requalification checks
    ///
    ///      Sim stand-ins: fabricated CnStakingOwner/holder/funder EOAs, vm.warp for the
    ///      lockup, and — PD-on only — the GC's V3 PD share is seeded by staking fresh KAIA
    ///      just before redeeming it (the real GC-owned holder address is off-chain
    ///      knowledge; same approach as ABv1V3PdOnSwapFork).
    function _migrateCnStakings() internal {
        console.log("=== 6. CnStaking migration (V2/V3 -> V4, per GC migration runbook) ===");

        // Committee gcIds must be unique for gcId-keyed identification (below) to be
        // collision-free: the factory CREATE2 salt is (msg.sender, gcOwner), so two GCs
        // resolving to the same gcOwner would clash. Holds because each GC runs a single
        // committee node (extra nodes are sibling pots, handled separately). A loud failure
        // here beats a confusing CREATE2 revert mid-deploy if that ever stops being true.
        require(_uniqueGcIdCount() == gcs.length, "committee gcIds not unique");

        _dedupRewards();

        console.log("--- D-7: deploy V4, setLegacyAbv1Info, submit unstake ---");
        for (uint256 i = 0; i < gcs.length; i++) {
            _migrateD7(gcs[i].gcId);
        }

        // Manual step 5: 7-day STAKE_LOCKUP between withdrawal request and execution
        vm.warp(block.timestamp + 7 days + 1);
        console.log("--- 7-day lockup elapsed (vm.warp) ---");

        console.log("--- D-day: withdraw/claim, fund V4, ABv1 swap ---");
        for (uint256 i = 0; i < gcs.length; i++) {
            _migrateDday(gcs[i].gcId);
        }
        console.log("Migrated GCs:", gcs.length);
    }

    /// @dev Storage reference to the committee GC with the given gcId (unique, asserted in
    ///      _migrateCnStakings).
    function _gc(uint256 gcId) internal view returns (GC storage) {
        for (uint256 i = 0; i < gcs.length; i++) {
            if (gcs[i].gcId == gcId) return gcs[i];
        }
        revert("gcId not found");
    }

    /// @dev Rewards must be globally unique in ABv2 genesis (vs every nodeId and each other).
    ///      On current mainnet every duplicate is a dummy node sharing its GC's reward, and
    ///      dummies are already filtered out via kaia_getCommittee in _snapshot — so this pass
    ///      is a defensive check and should replace nothing. If it ever logs, a committee
    ///      member shares a reward and the genesis data needs resolving before freeze.
    function _dedupRewards() internal {
        address[] memory used = new address[](gcs.length * 2);
        uint256 usedCount;
        for (uint256 i = 0; i < gcs.length; i++) {
            used[usedCount++] = gcs[i].nodeId;
        }
        for (uint256 i = 0; i < gcs.length; i++) {
            // PD-on genesis rewards are the fresh V4 PD proxies (set in _migrateD7), so the
            // legacy reward is neither checked nor reserved — reserving it would trigger
            // false-positive replacements for PD-off GCs sharing that address.
            if (gcs[i].scenario == Scenario.PdOn || gcs[i].scenario == Scenario.DelegatorPdOn) continue;
            if (_contains(used, usedCount, gcs[i].reward)) {
                gcs[i].reward = makeAddr(string.concat("reward_dedup_gc", vm.toString(gcs[i].gcId)));
                console.log("  [sim] duplicate reward replaced for node:", gcs[i].nodeId);
            }
            used[usedCount++] = gcs[i].reward;
        }
    }

    /// @dev Manual steps 1-4 for one GC (D-7).
    function _migrateD7(uint256 gcId) internal {
        GC storage gc = _gc(gcId);

        // CnStakingOwner is keyed by gcId (unique per committee GC, asserted in
        // _migrateCnStakings), so the factory CREATE2 salt (msg.sender, gcOwner) is distinct
        // per GC.
        gc.gcOwner = makeAddr(string.concat("cnStakingOwner_gc", vm.toString(gcId)));

        bool pdOn = gc.scenario == Scenario.PdOn || gc.scenario == Scenario.DelegatorPdOn;

        // Step 1 [KF]: deploy V4 (+ PD) via the factory on the GC's behalf
        address kf = makeAddr("kfDeployer");
        if (pdOn) {
            uint256 lockup = factory.INITIAL_LOCKUP(); // read outside the prank
            IPublicDelegation.PDConstructorArgs memory pdArgs = IPublicDelegation.PDConstructorArgs({
                owner: gc.gcOwner,
                commissionTo: gc.gcOwner,
                commissionRate: 0,
                gcName: string.concat("gc-", vm.toString(gcId))
            });
            vm.deal(kf, lockup);
            vm.prank(kf);
            (address cnProxy, address pdProxy) = factory.deployCnStakingWithPD{value: lockup}(gc.gcOwner, pdArgs);
            gc.newStaking = cnProxy;
            gc.newPd = pdProxy;
            gc.reward = pdProxy; // manual §2 step 2: reward must be the new PD
        } else {
            vm.prank(kf);
            gc.newStaking = factory.deployCnStaking(gc.gcOwner);
        }

        // Step 2 [GC]: verify the deployment
        CnStakingV4 v4 = CnStakingV4(payable(gc.newStaking));
        require(v4.owner() == gc.gcOwner, "V4 owner mismatch");
        require(v4.VERSION() == 4, "V4 VERSION mismatch");
        require(factory.isDeployedCnStaking(gc.newStaking), "V4 not factory-deployed");
        if (pdOn) require(v4.publicDelegation() == gc.newPd, "V4 PD mismatch");

        // Step 3 [GC, CnStakingOwner]: legacy info for ABv1 registration (one-shot)
        _setLegacyInfo(gc.gcOwner, v4, gc.nodeId, gc.reward);

        // The GC's own pot always comes back to the GC: gcOwner directly (PD-off) or via
        // its PD holder account (PD-on). The delegated sibling pots go to the funder.
        gc.holder = pdOn ? makeAddr(string.concat("pdHolder_gc", vm.toString(gcId))) : gc.gcOwner;

        // Manual §3 step 4-5 [KF/GC]: delegator deploy (+ V4 ownership hand-over when PD-off).
        // For PD-on, funder/delegatee are the REAL role holders read from the legacy
        // Delegator; fabricated only when forced via DELEGATOR_NODES with no on-chain one.
        if (gc.scenario == Scenario.DelegatorPdOff) {
            gc.funder = makeAddr(string.concat("kfFunder_gc", vm.toString(gcId)));
            gc.delegatorContract = address(new CnStakingDelegator(gc.funder, gc.gcOwner, gc.newStaking));
            vm.prank(gc.gcOwner);
            v4.transferOwnership(gc.delegatorContract);
        } else if (gc.scenario == Scenario.DelegatorPdOn) {
            if (gc.oldDelegator != address(0)) {
                ILegacyDelegator old = ILegacyDelegator(gc.oldDelegator);
                gc.funder = old.getRoleMember(old.DELEGATOR_ROLE(), 0);
                gc.delegatee = old.getRoleMember(old.DELEGATEE_ROLE(), 0);
            } else {
                gc.funder = makeAddr(string.concat("kfFunder_gc", vm.toString(gcId)));
                gc.delegatee = gc.gcOwner;
            }
            gc.delegatorContract = address(new PublicDelegationDelegator(gc.funder, gc.delegatee, gc.newPd));
        }

        // §3 PD-on step 6 (submit side): split the funder principal and delegatee reward
        // out of the LEGACY delegator (manual: funder withdrawDelegation / GC withdrawReward)
        if (gc.oldDelegator != address(0)) {
            _submitLegacyDelegatorWithdrawals(gc);
        }

        // Step 4 [GC]: submit the unstake request for the GC's own pot
        if (gc.effectiveStake == 0) {
            console.log("  [note] zero effective stake on committee node of gcId:", gc.gcId);
        } else if (pdOn) {
            // GC's own PD position = effective stake minus what leaves via the legacy delegator
            uint256 delegatorPortion = gc.funderAmount + gc.rewardAmount;
            if (gc.effectiveStake > delegatorPortion) {
                _submitPdRedeem(gc, gc.effectiveStake - delegatorPortion);
            } else {
                // Fully delegation-funded GC: everything leaves via the legacy delegator.
                console.log("  [note] own PD position fully covered by the legacy delegator, gcId:", gc.gcId);
            }
        } else {
            (gc.extractAmount, gc.withdrawalId) = _submitMultisigWithdrawal(gc.oldStaking, gc.holder);
        }

        // Submit the sibling-pot withdrawals: to the funder for §3 GCs (manual step 6,
        // funder side), to the GC itself when the pots are its own (disjoint admin sets).
        bool viaDelegator = gc.delegatorContract != address(0);
        uint256 sibEffective;
        for (uint256 k = 0; k < gc.siblingStakings.length; k++) {
            address sib = gc.siblingStakings[k];
            require(_readPublicDelegation(sib) == address(0), "PD-on sibling pot not supported");
            (uint256 amount, uint256 wid) = _submitMultisigWithdrawal(sib, viaDelegator ? gc.funder : gc.holder);
            gc.siblingAmounts.push(amount);
            gc.siblingIds.push(wid);
            sibEffective += amount; // sibling pots are withdrawn in full, so amount == their effective stake
        }

        // Per-gcId D-7 summary: effective stake (own pot + sibling pots) vs what was
        // actually submitted for withdrawal (own extraction + legacy delegator principal
        // and reward + sibling pots).
        uint256 withdrawTotal = gc.extractAmount + gc.funderAmount + gc.rewardAmount + sibEffective;
        console.log(
            string.concat(
                "  gcId ",
                vm.toString(gc.gcId),
                " [",
                _scenarioName(gc.scenario),
                "] effective (KAIA): ",
                vm.toString((gc.effectiveStake + sibEffective) / 1e18),
                " | withdraw submitted (KAIA): ",
                vm.toString(withdrawTotal / 1e18)
            )
        );
    }

    /// @dev §3 PD-on step 6, submit side: the funder withdraws its principal
    ///      (withdrawDelegation) and the delegatee its accrued reward (withdrawReward)
    ///      from the LEGACY delegator, kicking off the 7-day lockup for both.
    function _submitLegacyDelegatorWithdrawals(GC storage gc) internal {
        ILegacyDelegator old = ILegacyDelegator(gc.oldDelegator);
        gc.funderAmount = old.delegation();

        if (gc.funderAmount > 0) {
            vm.prank(gc.funder);
            old.withdrawDelegation(gc.funder, gc.funderAmount);
            uint256[] memory ids = old.delegationWithdrawalIds();
            gc.funderClaimId = ids[ids.length - 1];
        }
        // Read AFTER withdrawDelegation: the principal redemption moves the share price by
        // a rounding hair, so a pre-read reward amount can exceed the post-read one.
        gc.rewardAmount = old.withdrawableReward();
        if (gc.rewardAmount > 0) {
            vm.prank(gc.delegatee);
            old.withdrawReward(gc.delegatee, gc.rewardAmount);
            uint256[] memory ids = old.rewardWithdrawalIds();
            gc.rewardClaimId = ids[ids.length - 1];
        }
    }

    /// @dev Manual §2 step 4: the GC's PD holder redeems its share worth `seedAmount`. The
    ///      share is seeded by staking that amount first ([sim] — the real holder address
    ///      is off-chain knowledge; same approach as ABv1V3PdOnSwapFork).
    function _submitPdRedeem(GC storage gc, uint256 seedAmount) internal {
        IV3PDV1 oldPd = IV3PDV1(gc.oldPd);

        vm.deal(gc.holder, seedAmount);
        vm.prank(gc.holder);
        oldPd.stake{value: seedAmount}();

        uint256 shares = oldPd.balanceOf(gc.holder);
        require(shares > 0, "PD seed minted zero shares");

        uint256 unstakingBefore = ICnStakingLive(gc.oldStaking).unstaking();
        vm.prank(gc.holder);
        oldPd.redeem(gc.holder, shares);
        gc.extractAmount = ICnStakingLive(gc.oldStaking).unstaking() - unstakingBefore;
        require(gc.extractAmount > 0, "PD redeem produced zero unstaking");

        uint256[] memory ids = oldPd.getUserRequestIds(gc.holder);
        gc.withdrawalId = ids[ids.length - 1];
    }

    /// @dev Manual §1 step 4: a legacy V2/V3 multisig approves a withdrawal of the full
    ///      effective stake to the given recipient. Returns (0, 0) when there is nothing
    ///      to withdraw.
    function _submitMultisigWithdrawal(address staking, address recipient)
        internal
        returns (uint256 amount, uint256 withdrawalId)
    {
        IMainnetMultiSig legacy = IMainnetMultiSig(staking);
        amount = legacy.staking() - legacy.unstaking();
        if (amount == 0) return (0, 0);

        (address[] memory admins, uint256 quorum) = _fetchOldAdmins(staking);
        withdrawalId = legacy.withdrawalRequestCount();
        uint256 multisigId = legacy.requestCount();

        vm.prank(admins[0]);
        legacy.submitApproveStakingWithdrawal(recipient, amount);

        bytes32 toArg = bytes32(uint256(uint160(recipient)));
        bytes32 valueArg = bytes32(amount);
        for (uint256 i = 1; i < quorum; ++i) {
            vm.prank(admins[i]);
            legacy.confirmRequest(multisigId, FN_APPROVE_STAKING_WITHDRAWAL, toArg, valueArg, 0);
        }
    }

    /// @dev Withdraws the withdrawable initial lockup of a legacy V2/V3 contract to
    ///      `recipient` through its admin multisig (submit + confirmations). Unlike the
    ///      approve/withdraw pair, the transfer happens in the confirming transaction with no
    ///      7-day wait, provided unlockTime has passed. Returns 0 when nothing is withdrawable;
    ///      lockup that is still time-locked cannot be migrated and is reported.
    function _withdrawLockup(address staking, address recipient) internal returns (uint256 amount) {
        ILegacyLockupLive legacy = ILegacyLockupLive(staking);
        (,,,, amount) = legacy.getLockupStakingInfo();
        if (amount == 0) {
            uint256 locked = legacy.remainingLockupStaking();
            if (locked > 0) {
                console.log("  [warn] initial lockup still time-locked, NOT migrated (KAIA):", locked / 1e18);
                console.log("         contract:", staking);
            }
            return 0;
        }

        (address[] memory admins, uint256 quorum) = _fetchOldAdmins(staking);
        uint256 multisigId = IMainnetMultiSig(staking).requestCount();
        uint256 balBefore = recipient.balance;

        vm.prank(admins[0]);
        legacy.submitWithdrawLockupStaking(recipient, amount);

        bytes32 toArg = bytes32(uint256(uint160(recipient)));
        bytes32 valueArg = bytes32(amount);
        for (uint256 i = 1; i < quorum; ++i) {
            vm.prank(admins[i]);
            IMainnetMultiSig(staking).confirmRequest(multisigId, FN_WITHDRAW_LOCKUP_STAKING, toArg, valueArg, 0);
        }
        require(recipient.balance - balBefore >= amount, "lockup withdrawal shortfall");
    }

    /// @dev What STv2 (StakingTrackerV2.sol:494) and the pre-fork client
    ///      (MultiCallContract._getCnStakingAmountsLegacy) count for a legacy contract: its
    ///      balance net of pending withdrawals — initial lockup included, unlike staking().
    function _balanceStake(address staking) internal view returns (uint256) {
        return staking.balance - ICnStakingLive(staking).unstaking();
    }

    function _eligibleTodayCount() internal view returns (uint256 count) {
        for (uint256 i = 0; i < gcs.length; i++) {
            if (gcs[i].eligibleToday) count++;
        }
    }

    /// @dev Manual steps 6-9 for one GC (D-day).
    function _migrateDday(uint256 gcId) internal {
        GC storage gc = _gc(gcId);
        bool pdOn = gc.scenario == Scenario.PdOn || gc.scenario == Scenario.DelegatorPdOn;

        if (gc.extractAmount > 0) {
            // Step 6 [GC]: execute the withdrawal of the GC's own pot
            uint256 balBefore = gc.holder.balance;
            if (pdOn) {
                vm.prank(gc.holder);
                IV3PDV1(gc.oldPd).claim(gc.withdrawalId);
            } else {
                (address[] memory admins,) = _fetchOldAdmins(gc.oldStaking);
                vm.prank(admins[0]);
                IMainnetMultiSig(gc.oldStaking).withdrawApprovedStaking(gc.withdrawalId);
            }
            uint256 received = gc.holder.balance - balBefore;
            require(received >= gc.extractAmount, "legacy withdrawal shortfall");

            // Step 7/8 [GC]: the GC's own pot goes back in directly — owner delegate
            // (PD-off; permissionless even under §3's delegator-owned V4) or PD stake (PD-on)
            if (pdOn) {
                vm.prank(gc.holder);
                IV3PDV1(gc.newPd).stake{value: received}();
            } else {
                vm.prank(gc.holder);
                CnStakingV4(payable(gc.newStaking)).delegate{value: received}();
            }
        }

        // Initial lockup on the GC's own legacy contract: staking() excludes it, so the
        // step-4 withdrawal above leaves it behind, while STv3 and the post-fork client count
        // V4 staking() only. Withdraw it (immediate once unlockTime has passed) and restake it
        // with the GC's own pot.
        uint256 ownLockup = _withdrawLockup(gc.oldStaking, gc.holder);
        if (ownLockup > 0) {
            if (pdOn) {
                vm.prank(gc.holder);
                IV3PDV1(gc.newPd).stake{value: ownLockup}();
            } else {
                vm.prank(gc.holder);
                CnStakingV4(payable(gc.newStaking)).delegate{value: ownLockup}();
            }
            gc.lockupAmount += ownLockup;
            console.log("  own initial lockup migrated (KAIA):", ownLockup / 1e18);
        }

        // §3 PD-on step 6/8 (claim side): funder claims its principal and re-delegates it
        // through the NEW PublicDelegationDelegator; the delegatee claims its reward, which
        // is income and is NOT restaked (manual step 8 restakes only the funder portion)
        if (gc.oldDelegator != address(0)) {
            if (gc.funderAmount > 0) {
                vm.prank(gc.funder);
                ILegacyDelegator(gc.oldDelegator).claimDelegation(gc.funderClaimId);
                vm.prank(gc.funder);
                PublicDelegationDelegator(gc.delegatorContract).delegate{value: gc.funderAmount}();
                console.log("  funder principal re-delegated via new delegator (KAIA):", gc.funderAmount / 1e18);
            }
            if (gc.rewardAmount > 0) {
                vm.prank(gc.delegatee);
                ILegacyDelegator(gc.oldDelegator).claimReward(gc.rewardClaimId);
                console.log("  delegatee reward claimed, not restaked (KAIA):", gc.rewardAmount / 1e18);
            }
        }

        // Withdraw each sibling pot, then re-stake the total: through the delegator (§3,
        // stays withdrawable by the funder) or as the GC's own stake (disjoint-admin pots)
        bool viaDelegator = gc.delegatorContract != address(0);
        uint256 sibTotal;
        for (uint256 k = 0; k < gc.siblingStakings.length; k++) {
            address sib = gc.siblingStakings[k];
            if (gc.siblingAmounts[k] > 0) {
                (address[] memory sibAdmins,) = _fetchOldAdmins(sib);
                vm.prank(sibAdmins[0]);
                IMainnetMultiSig(sib).withdrawApprovedStaking(gc.siblingIds[k]);
                sibTotal += gc.siblingAmounts[k];
            }
            // Sibling-pot initial lockup follows the pot's destination (D-7 sent the pot to
            // the funder for §3 GCs, to the GC itself otherwise).
            uint256 sibLockup = _withdrawLockup(sib, viaDelegator ? gc.funder : gc.holder);
            if (sibLockup > 0) {
                sibTotal += sibLockup;
                gc.lockupAmount += sibLockup;
                console.log("  sibling initial lockup migrated (KAIA):", sibLockup / 1e18);
            }
        }
        if (sibTotal > 0) {
            if (gc.scenario == Scenario.DelegatorPdOff) {
                vm.prank(gc.funder);
                CnStakingDelegator(gc.delegatorContract).delegate{value: sibTotal}();
                console.log("  funder pot consolidated via delegator (KAIA):", sibTotal / 1e18);
            } else if (gc.scenario == Scenario.DelegatorPdOn) {
                vm.prank(gc.funder);
                PublicDelegationDelegator(gc.delegatorContract).delegate{value: sibTotal}();
                console.log("  funder pot consolidated via delegator (KAIA):", sibTotal / 1e18);
            } else if (pdOn) {
                vm.prank(gc.holder);
                IV3PDV1(gc.newPd).stake{value: sibTotal}();
                console.log("  own sibling pot consolidated (KAIA):", sibTotal / 1e18);
            } else {
                vm.prank(gc.holder);
                CnStakingV4(payable(gc.newStaking)).delegate{value: sibTotal}();
                console.log("  own sibling pot consolidated (KAIA):", sibTotal / 1e18);
            }
        }

        // Step 8/9 [KF]: ABv1 swap under the same nodeId (AB admin multisig)
        _swapAbv1Node(gc.nodeId, gc.newStaking, gc.reward);

        // Step 9 [GC]: requalification checks
        uint256 v4Staking = CnStakingV4(payable(gc.newStaking)).staking();
        require(
            v4Staking >= gc.extractAmount + ownLockup + sibTotal + gc.funderAmount, "V4 staking below migrated amount"
        );
        if (gc.eligibleToday) {
            require(v4Staking >= MIN_STAKE, "GC eligible today falls below MIN_STAKE after migration");
        } else if (v4Staking < MIN_STAKE) {
            console.log("  [note] below MIN_STAKE post-migration (already below today), gcId:", gc.gcId);
        }
        console.log("  gcId", gc.gcId, string.concat("[", _scenarioName(gc.scenario), "] -> V4:"), gc.newStaking);
    }

    /// @dev Legacy admin lookup: V3 uses AccessControl (ADMIN_ROLE/getRoleMember), V2 the
    ///      getState() 9-tuple — same split as ABv1V3SwapFork/ABv1V2SwapFork._fetchAdmins.
    function _fetchOldAdmins(address staking) internal view returns (address[] memory admins, uint256 quorum) {
        (bool ok, bytes memory ret) = staking.staticcall(abi.encodeWithSignature("ADMIN_ROLE()"));
        if (ok && ret.length == 32) {
            IMainnetV3AdminGetter v3 = IMainnetV3AdminGetter(staking);
            quorum = v3.requirement();
            bytes32 adminRole = abi.decode(ret, (bytes32));
            admins = new address[](quorum);
            for (uint256 i = 0; i < quorum; ++i) {
                admins[i] = v3.getRoleMember(adminRole, i);
            }
        } else {
            (,,, address[] memory all, uint256 req,,,,) = IMainnetV2AdminGetter(staking).getState();
            quorum = req;
            admins = new address[](quorum);
            for (uint256 i = 0; i < quorum; ++i) {
                admins[i] = all[i];
            }
        }
    }

    /// @dev The migration withdraws `staking() - unstaking()`, so KAIA already inside a
    ///      pending withdrawal at fork time is NOT migrated — it stays claimable by its
    ///      original recipient on the old, soon-to-be-unregistered contract. Surface it
    ///      loudly so the real runbook can require pending requests to be settled or
    ///      cancelled before D-7.
    function _flagPendingUnstaking(address staking, uint256 gcId) internal view {
        uint256 pending = ICnStakingLive(staking).unstaking();
        if (pending > 0) {
            console.log("  [warn] pre-existing pending unstaking, NOT migrated (KAIA):", pending / 1e18);
            console.log("         gcId / contract:", gcId, staking);
        }
    }

    /// @dev Matches a GC's V3 PD against the legacy Delegator deployment registry.
    function _findLegacyDelegator(address oldPd) internal view returns (address) {
        if (oldPd == address(0)) return address(0);
        for (uint256 i = 0; i < LEGACY_DELEGATORS.length; i++) {
            if (ILegacyDelegator(LEGACY_DELEGATORS[i]).PD() == oldPd) return LEGACY_DELEGATORS[i];
        }
        return address(0);
    }

    function _readPublicDelegation(address staking) internal view returns (address) {
        (bool ok, bytes memory ret) = staking.staticcall(abi.encodeWithSignature("publicDelegation()"));
        if (!ok || ret.length != 32) return address(0);
        return abi.decode(ret, (address));
    }

    function _scenarioName(Scenario m) internal pure returns (string memory) {
        if (m == Scenario.PdOff) return "PD-off";
        if (m == Scenario.PdOn) return "PD-on";
        if (m == Scenario.DelegatorPdOff) return "Delegator/PD-off";
        return "Delegator/PD-on";
    }

    /* ========== 7. SUNSET VMC ========== */

    /// @dev Hands AddressBook admin rights and SimpleBlsRegistry ownership from the VMC to
    ///      a successor account (the Registry owner is used as the recipient stand-in here;
    ///      substitute the real target before the live run).
    function _sunsetVMC() internal {
        console.log("=== 7. Sunset VMC ===");

        // 7a. AddressBook admin: add the successor, then remove every VMC admin.
        // Guards: submitAddAdmin reverts via adminDoesNotExist if the successor is already
        // an admin, and the delete loop must never remove the successor itself.
        (address[] memory admins, uint256 quorum) = abv1.getState();
        require(quorum == 1, "Rehearsal only handles requirement=1 AB multisig");

        if (!_contains(admins, admins.length, registryOwner)) {
            vm.prank(admins[0]);
            abv1.submitAddAdmin(registryOwner);
        }
        for (uint256 i = 0; i < admins.length; i++) {
            if (admins[i] == registryOwner) continue;
            vm.prank(registryOwner);
            abv1.submitDeleteAdmin(admins[i]);
        }

        (address[] memory newAdmins, uint256 newQuorum) = abv1.getState();
        require(newAdmins.length == 1 && newAdmins[0] == registryOwner && newQuorum == 1, "AB admin sunset failed");
        console.log("AB admin:", newAdmins[0]);

        // 7b. SimpleBlsRegistry ownership
        address sbrOwner = sbr.owner();
        vm.prank(sbrOwner);
        sbr.transferOwnership(registryOwner);
        require(sbr.owner() == registryOwner, "SBR ownership sunset failed");
        console.log("SBR owner:", sbr.owner());
    }

    /* ========== 8. ABV2: DATA CONTRACT + REGISTRY + HARDFORK INIT ========== */

    /// @dev The hardfork that puts ABv2 at 0x400 is what ends the intended voting freeze:
    ///      from here on STv3.createTracker() can read getAllGovernanceInfo() and proposals
    ///      work again. On the real network this code swap happens via hardfork; here
    ///      vm.etch stands in for it.
    function _deployABv2AndInitialize() internal {
        console.log("=== 8. ABv2 data contract + hardfork stand-in at 0x400 ===");

        ABv2DataContract dataContract = new ABv2DataContract(address(abv2Impl), _buildInitData());
        vm.label(address(dataContract), "ABv2DataContract");
        _registryRegister("ABv2DataContract", address(dataContract));

        // Same pattern as test/stv3/Base.t.sol: the temp proxy initializes its own storage,
        // the etched copy at 0x400 starts with fresh (namespaced) storage and inits again.
        ERC1967Proxy tempProxy = new ERC1967Proxy(address(abv2Impl), abi.encodeCall(AddressBookV2.initialize, ()));
        vm.etch(ADDRESS_BOOK, address(tempProxy).code); // sim stand-in for the hardfork
        vm.store(ADDRESS_BOOK, ERC1967_IMPL_SLOT, bytes32(uint256(uint160(address(abv2Impl)))));
        AddressBookV2(ADDRESS_BOOK).initialize();

        GovernanceInfo[] memory infos = AddressBookV2(ADDRESS_BOOK).getAllGovernanceInfo();
        require(infos.length == gcs.length, "ABv2 governance info count mismatch");
        console.log("ABv2 initialized, nodes:", infos.length);

        // Populate STv3's voter mappings from ABv2 (public, anyone can call)
        uint256 votersRegistered;
        for (uint256 i = 0; i < gcs.length; i++) {
            stv3.refreshVoter(gcs[i].nodeId);
            if (gcs[i].voter != address(0)) votersRegistered++;
        }
        // Verify in a SECOND pass, after every refresh: refreshVoter is last-write-wins per
        // gcId, so a per-node check right after each call could pass even though a later
        // node sharing the gcId (with a different snapshot voter) overwrote the mapping.
        // A failure here means the genesis data has an ambiguous gcId -> voter assignment
        // that must be resolved in abv2-data.json before the real run.
        for (uint256 i = 0; i < gcs.length; i++) {
            require(stv3.gcIdToVoter(gcs[i].gcId) == gcs[i].voter, "STv3 voter mapping ambiguous or mismatched");
        }
        console.log("STv3 voters registered:", votersRegistered);
    }

    /// @dev Builds ABv2 genesis from the post-migration state: V4 staking contracts from
    ///      phase 6, gcId/voter from the pre-migration snapshot (V4 has no identity fields),
    ///      BLS keys from the live KIP113. Fields ABv1 has no notion of are fabricated for
    ///      the simulation; the real migration uses the reviewed abv2-data.json
    ///      (see DeployABv2DataContract.s.sol).
    function _buildInitData() internal returns (IABv2DataContract.InitData memory d) {
        (address[] memory blsNodes, BlsPublicKeyInfo[] memory blsKeys) = sbr.getAllBlsInfo();

        address[] memory nodeIds = new address[](gcs.length);
        NodeInfo[] memory infos = new NodeInfo[](gcs.length);

        for (uint256 i = 0; i < gcs.length; i++) {
            GC storage gc = gcs[i];
            nodeIds[i] = gc.nodeId;
            infos[i] = NodeInfo({
                manager: makeAddr(string.concat("manager_gc", vm.toString(gc.gcId))), // sim placeholder
                stakingContract: gc.newStaking,
                rewardAddress: gc.reward,
                voterAddress: gc.voter,
                timeoutAt: 0,
                gcId: gc.gcId,
                blsInfo: _findBlsInfo(blsNodes, blsKeys, gc.nodeId, i),
                name: string.concat("gc-", vm.toString(gc.gcId)),
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

    function _uniqueGcIdCount() internal view returns (uint256 count) {
        uint256[] memory seen = new uint256[](gcs.length);
        for (uint256 i = 0; i < gcs.length; i++) {
            bool dup;
            for (uint256 j = 0; j < count; j++) {
                if (seen[j] == gcs[i].gcId) {
                    dup = true;
                    break;
                }
            }
            if (!dup) seen[count++] = gcs[i].gcId;
        }
    }

    function _contains(address[] memory arr, uint256 len, address x) internal pure returns (bool) {
        for (uint256 i = 0; i < len; i++) {
            if (arr[i] == x) return true;
        }
        return false;
    }

    /* ========== 3B. EXECUTE THE SWITCH (VOTING FREEZE BEGINS) ========== */

    function _executeSTv3Switch(uint256 proposalId) internal {
        console.log("=== 3b. Execute the switch (voting freeze begins) ===");
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

    /// @dev The freeze is intended: from the switch execution until the ABv2 hardfork,
    ///      propose() routes to STv3.createTracker, which reads getAllGovernanceInfo()
    ///      from 0x400 — still ABv1 — and therefore reverts. Pinned in three steps so the
    ///      probe can't pass for an unrelated reason (wrong owner, timing-rule drift, ...):
    ///      routing, direct cause, then the user-visible effect.
    function _verifyGovernanceFrozen() internal {
        console.log("=== 3c. Voting freeze window (execution -> hardfork) ===");

        // (a) Routing: proposals now go to STv3 (established in 3b, restated here as the
        // premise of this check).
        require(voting.stakingTracker() == address(stv3), "Freeze probe premise broken: tracker != STv3");

        // (b) Direct cause: STv3.createTracker itself (called as its owner, so onlyOwner
        // cannot be the reason) fails because 0x400 has no getAllGovernanceInfo() yet.
        vm.prank(VOTING);
        try stv3.createTracker(block.number, block.number + 1) returns (uint256) {
            revert("STv3.createTracker unexpectedly succeeded before the hardfork");
        } catch {}

        // (c) User-visible effect: propose() reverts end-to-end.
        (uint256 minVotingDelay,, uint256 minVotingPeriod,) = voting.timingRule();
        address[] memory targets = new address[](1);
        targets[0] = VOTING;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateSecretary(address)", secretary);

        vm.prank(secretary);
        try voting.propose("freeze probe", targets, values, calldatas, minVotingDelay, minVotingPeriod) returns (
            uint256
        ) {
            revert("Voting is NOT frozen before the hardfork");
        } catch {
            console.log("propose() reverts as intended: governance frozen until the ABv2 hardfork");
        }
    }

    /// @dev CLDEX check: STv3 folds CL-pool WrappedKaia liquidity into a GC's voting-power
    ///      balance (on top of its CnStaking balance), read live from CLRegistry — no CLDEX
    ///      redeployment is needed for the migration, so this verifies the existing
    ///      CLRegistry keeps feeding STv3 after the switch. On mainnet the CL pools belong to
    ///      gcId 44 (BORA) and 61 (SCNR); their CL liquidity only affects votes when the GC
    ///      is eligible (CnStaking >= MIN_STAKE), which the sibling-pot consolidation ensures.
    function _verifyCLDEX(uint256 trackerId) internal {
        address clRegistry = registry.getActiveAddr("CLRegistry");
        if (clRegistry == address(0)) {
            console.log("  [note] CLDEX: no CLRegistry registered, skipping");
            return;
        }
        address wKaia = registry.getActiveAddr("WrappedKaia");
        (, uint256[] memory clGcIds, address[] memory pools) = ICLRegistryLive(clRegistry).getAllCLs();
        (uint256[] memory trackedGcIds,,) = stv3.getAllTrackedGCs(trackerId);
        console.log("  CLDEX: CL pools registered:", clGcIds.length);
        for (uint256 i = 0; i < clGcIds.length; i++) {
            uint256 gcId = clGcIds[i];
            if (!_uintIn(trackedGcIds, gcId)) {
                console.log("  [note] CLDEX pool gcId not a migrated/tracked GC, skipping gcId:", gcId);
                continue;
            }
            uint256 clBal = wKaia == address(0) ? 0 : IERC20Live(wKaia).balanceOf(pools[i]);
            (uint256 cnBal, uint256 gcBal) = stv3.getTrackedGCBalance(trackerId, gcId);
            require(gcBal >= cnBal + clBal, "CL liquidity not counted in STv3 tracker");
            console.log("  CLDEX gcId / CL liquidity counted (KAIA):", gcId, clBal / 1e18);
        }
    }

    function _uintIn(uint256[] memory arr, uint256 x) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == x) return true;
        }
        return false;
    }

    /* ========== 9. END-TO-END VERIFICATION (POST-HARDFORK GC VOTING) ========== */

    /// @dev The definitive post-hardfork check: with ABv2 etched over 0x400 (phase 8), run
    ///      a complete GC voting lifecycle on the migrated stack — propose (STv3
    ///      createTracker over ABv2 governance info + V4 contracts), Pending -> Active ->
    ///      vote with STv3-mapped voters -> Passed -> Queued -> Executed — asserting every
    ///      state transition of the Voting state machine along the way.
    function _verifyEndToEnd() internal {
        console.log("=== 9. Post-hardfork GC voting: full lifecycle on STv3 + ABv2 + V4 ===");
        (uint256 minVotingDelay,, uint256 minVotingPeriod,) = voting.timingRule();

        address[] memory targets = new address[](1);
        targets[0] = VOTING;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("updateSecretary(address)", secretary); // no-op action

        // Propose — the hardfork unfroze governance, so this must now succeed
        vm.prank(secretary);
        uint256 proposalId = voting.propose(
            "Rehearsal: verify post-migration proposal lifecycle",
            targets,
            values,
            calldatas,
            minVotingDelay,
            minVotingPeriod
        );
        require(voting.state(proposalId) == STATE_PENDING, "not Pending after propose");

        uint256 trackerId = stv3.getLastTrackerId();
        require(trackerId == 1, "STv3 tracker not created");
        (,, uint256 numGCs, uint256 totalVotes, uint256 numEligible) = stv3.getTrackerSummary(trackerId);
        console.log("STv3 tracker GCs / eligible / totalVotes:", numGCs, numEligible, totalVotes);
        // The tracker counts unique gcIds, not AB nodes — several GCs run multiple nodes.
        require(numGCs == _uniqueGcIdCount(), "STv3 tracker missing GCs");
        require(numEligible > 0, "No eligible GC in STv3 tracker");

        // The eligible set must not shrink: every GC eligible today (balance-based, initial
        // lockup included) must be eligible on STv3, which counts V4 staking() only.
        for (uint256 i = 0; i < gcs.length; i++) {
            if (!gcs[i].eligibleToday) continue;
            (uint256 cnBal,) = stv3.getTrackedGCBalance(trackerId, gcs[i].gcId);
            if (cnBal < MIN_STAKE) {
                console.log(
                    "  [fail] eligible today, ineligible on STv3 - gcId / V4 stake (KAIA):", gcs[i].gcId, cnBal / 1e18
                );
                revert("eligible GC set shrank after migration");
            }
        }
        console.log("Eligible today / eligible on STv3:", _eligibleTodayCount(), numEligible);
        require(numEligible >= _eligibleTodayCount(), "STv3 eligible count below today's");

        _verifyCLDEX(trackerId);

        // Pending -> Active
        (uint256 voteStart, uint256 voteEnd,,,,,,) = voting.getProposalSchedule(proposalId);
        vm.roll(voteStart);
        require(voting.state(proposalId) == STATE_ACTIVE, "not Active at voteStart");

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
        console.log("Voters cast:", cast);
        require(cast > 0, "No vote cast on STv3 proposal");
        require(voting.checkQuorum(proposalId), "Quorum not reached on STv3 proposal");

        // Active -> Passed -> Queued
        vm.roll(voteEnd + 1);
        require(voting.state(proposalId) == STATE_PASSED, "not Passed after voteEnd");
        vm.prank(secretary);
        voting.queue(proposalId);
        require(voting.state(proposalId) == STATE_QUEUED, "not Queued after queue");

        // Queued -> Executed
        (,,, uint256 eta,,,,) = voting.getProposalSchedule(proposalId);
        vm.roll(eta);
        vm.prank(secretary);
        voting.execute(proposalId);

        require(voting.state(proposalId) == STATE_EXECUTED, "STv3 proposal not Executed");
        require(voting.secretary() == secretary, "Secretary changed unexpectedly");
        console.log("Post-hardfork GC voting lifecycle complete, proposal id:", proposalId);
    }

    /// @dev JSON-RPC quantity encoding (0x-prefixed, no leading zeros) for block tags.
    function _hexQuantity(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0x0";
        bytes memory buf = new bytes(64);
        uint256 i = 64;
        while (v != 0) {
            uint256 nib = v & 0xf;
            buf[--i] = bytes1(uint8(nib < 10 ? 48 + nib : 87 + nib));
            v >>= 4;
        }
        bytes memory out = new bytes(64 - i);
        for (uint256 j = 0; j < out.length; j++) {
            out[j] = buf[i + j];
        }
        return string.concat("0x", string(out));
    }
}
