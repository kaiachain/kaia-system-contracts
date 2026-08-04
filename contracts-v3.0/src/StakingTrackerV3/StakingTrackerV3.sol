// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {IStakingTrackerV3} from "./interfaces/IStakingTrackerV3.sol";
import {GovernanceInfo, NodeInfo} from "../types/Node.sol";
import {IRegistry} from "../system/IRegistry.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title StakingTrackerV3
/// @notice Tracks staking balances and computes voting power for GCs.
///         Reads governance data from AddressBookV2 and CL data from CLRegistry.
///         Fully backward-compatible with the Voting contract's StakingTracker interface.
contract StakingTrackerV3 is IStakingTrackerV3, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /* ========== CONSTANTS ========== */

    address private constant _ADDRESS_BOOK = 0x0000000000000000000000000000000000000400;
    address private constant _REGISTRY = 0x0000000000000000000000000000000000000401;
    uint256 private constant _MIN_STAKE = 5_000_000 ether;

    /* ========== STORAGE (ERC-7201) ========== */

    struct Tracker {
        uint256 trackStart;
        uint256 trackEnd;
        uint256[] gcIds;
        mapping(uint256 => bool) gcExists;
        mapping(address => uint256) stakingToGCId;
        mapping(address => uint256) stakingBalances;
        mapping(uint256 => uint256) cnStakingBalances;
        mapping(address => bool) isCLPool;
        mapping(uint256 => uint256) gcBalances;
        mapping(uint256 => uint256) gcVotes;
        uint256 totalVotes;
        uint256 numEligible;
    }

    /// @custom:storage-location erc7201:kaia.StakingTrackerV3
    struct STv3Storage {
        mapping(uint256 => Tracker) trackers;
        uint256[] allTrackerIds;
        uint256[] liveTrackerIds;
        mapping(uint256 => address) gcIdToVoter;
        mapping(address => uint256) voterToGCId;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("kaia.StakingTrackerV3")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_LOCATION = 0x926356c7610943575414e5f9d3a6bc474af929bce874d7f14aa7229ba5836c00;

    function _getStorage() private pure returns (STv3Storage storage $) {
        bytes32 loc = STORAGE_LOCATION;
        assembly {
            $.slot := loc
        }
    }

    /* ========== CONSTRUCTOR ========== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
    }

    /* ========== CONSTANTS (interface) ========== */

    /// @inheritdoc IStakingTrackerV3
    function CONTRACT_TYPE() external pure override returns (string memory) {
        return "StakingTracker";
    }

    /// @inheritdoc IStakingTrackerV3
    function VERSION() external pure override returns (uint256) {
        return 3;
    }

    /// @inheritdoc IStakingTrackerV3
    function ADDRESS_BOOK_ADDRESS() external pure override returns (address) {
        return _ADDRESS_BOOK;
    }

    /// @inheritdoc IStakingTrackerV3
    function REGISTRY_ADDRESS() external pure override returns (address) {
        return _REGISTRY;
    }

    /// @inheritdoc IStakingTrackerV3
    function MIN_STAKE() external pure override returns (uint256) {
        return _MIN_STAKE;
    }

    /* ========== MUTATORS ========== */

    /// @inheritdoc IStakingTrackerV3
    function createTracker(
        uint256 trackStart,
        uint256 trackEnd
    ) external override onlyOwner returns (uint256 trackerId) {
        STv3Storage storage $ = _getStorage();

        trackerId = $.allTrackerIds.length + 1;
        $.allTrackerIds.push(trackerId);
        $.liveTrackerIds.push(trackerId);

        Tracker storage tracker = $.trackers[trackerId];
        tracker.trackStart = trackStart;
        tracker.trackEnd = trackEnd;

        _populateTracker(trackerId);

        emit CreateTracker(trackerId, trackStart, trackEnd, tracker.gcIds);
    }

    /// @inheritdoc IStakingTrackerV3
    function refreshStake(address staking) external override {
        STv3Storage storage $ = _getStorage();
        uint256 i = 0;
        while (i < $.liveTrackerIds.length) {
            uint256 currId = $.liveTrackerIds[i];

            if (!_isTrackerLive(currId)) {
                uint256 lastId = $.liveTrackerIds[$.liveTrackerIds.length - 1];
                $.liveTrackerIds[i] = lastId;
                $.liveTrackerIds.pop();
                emit RetireTracker(currId);
                continue;
            }

            _updateTracker(currId, staking);
            i++;
        }
    }

    /// @inheritdoc IStakingTrackerV3
    function refreshVoter(address nodeId) external override {
        NodeInfo memory info = IAddressBookV2(_ADDRESS_BOOK).getNodeInfo(nodeId);
        if (info.gcId == 0) return;
        _updateVoter(info.gcId, info.voterAddress);
        emit RefreshVoter(info.gcId, info.voterAddress);
    }

    /// @inheritdoc IStakingTrackerV3
    function revokeVoter(uint256 gcId) external override {
        if (msg.sender != _ADDRESS_BOOK) revert NotAddressBook();
        _updateVoter(gcId, address(0));
        emit RefreshVoter(gcId, address(0));
    }

    /* ========== INTERNAL: POPULATE ========== */

    function _populateTracker(uint256 trackerId) private {
        _populateFromAddressBook(trackerId);
        _populateFromCLRegistry(trackerId);
        _calcAllVotes(trackerId);
    }

    /// @dev Reads governance info from ABv2 and populates CnStaking balances.
    ///      Filters out entries with gcId == 0 (non-governance nodes).
    function _populateFromAddressBook(uint256 trackerId) private {
        GovernanceInfo[] memory infos = IAddressBookV2(_ADDRESS_BOOK).getAllGovernanceInfo();
        Tracker storage tracker = _getStorage().trackers[trackerId];

        for (uint256 i; i < infos.length; i++) {
            uint256 gcId = infos[i].gcId;
            if (gcId == 0) continue;

            address staking = infos[i].stakingContract;
            uint256 balance = _readCnStakingBalance(staking);

            if (!tracker.gcExists[gcId]) {
                tracker.gcExists[gcId] = true;
                tracker.gcIds.push(gcId);
            }

            tracker.stakingToGCId[staking] = gcId;
            tracker.stakingBalances[staking] = balance;
            tracker.cnStakingBalances[gcId] += balance;
            tracker.gcBalances[gcId] += balance;
        }
    }

    /// @dev Reads CL pool data from CLRegistry and adds CLPool balances.
    ///      Only adds CLPool if its GC is already tracked from AddressBook population.
    function _populateFromCLRegistry(uint256 trackerId) private {
        (uint256[] memory gcIds, address[] memory pools) = _getCLRegistryLists();
        Tracker storage tracker = _getStorage().trackers[trackerId];

        for (uint256 i; i < gcIds.length; i++) {
            uint256 gcId = gcIds[i];
            address pool = pools[i];

            // Only add CLPool if its GC was already populated from AddressBook
            if (!tracker.gcExists[gcId]) continue;

            uint256 balance = _readCLPoolBalance(pool);
            tracker.isCLPool[pool] = true;
            tracker.stakingToGCId[pool] = gcId;
            tracker.stakingBalances[pool] = balance;
            tracker.gcBalances[gcId] += balance;
        }
    }

    /* ========== INTERNAL: VOTE CALCULATION ========== */

    /// @dev Counts eligible GCs and calculates initial votes for all GCs in a tracker.
    function _calcAllVotes(uint256 trackerId) private {
        Tracker storage tracker = _getStorage().trackers[trackerId];
        uint256 len = tracker.gcIds.length;

        // Count eligible GCs (cnStakingBalance >= MIN_STAKE)
        uint256 numEligible;
        for (uint256 i; i < len; i++) {
            if (tracker.cnStakingBalances[tracker.gcIds[i]] >= _MIN_STAKE) {
                numEligible++;
            }
        }
        tracker.numEligible = numEligible;

        // Calculate votes for each GC
        uint256 totalVotes;
        for (uint256 i; i < len; i++) {
            uint256 gcId = tracker.gcIds[i];
            uint256 votes = _calcVotes(numEligible, tracker.gcBalances[gcId], tracker.cnStakingBalances[gcId]);
            tracker.gcVotes[gcId] = votes;
            totalVotes += votes;
        }
        tracker.totalVotes = totalVotes;
    }

    /// @dev Calculates voting power for a single GC.
    ///      Eligibility requires cnStakingBalance >= MIN_STAKE.
    ///      Voting power = min(gcBalance / MIN_STAKE, voteCap).
    ///      voteCap = max(numEligible - 1, 1) to prevent single GC dominance.
    function _calcVotes(
        uint256 numEligible,
        uint256 gcBalance,
        uint256 cnStakingBalance
    ) private pure returns (uint256) {
        if (cnStakingBalance < _MIN_STAKE) return 0;

        uint256 voteCap = numEligible > 1 ? numEligible - 1 : 1;
        uint256 votes = gcBalance / _MIN_STAKE;
        if (votes > voteCap) votes = voteCap;
        return votes;
    }

    /* ========== INTERNAL: UPDATE ========== */

    /// @dev Updates balances and votes for a staking contract within a single tracker.
    function _updateTracker(uint256 trackerId, address staking) private {
        Tracker storage tracker = _getStorage().trackers[trackerId];

        uint256 gcId = tracker.stakingToGCId[staking];
        if (gcId == 0) return;

        (uint256 newBalance, bool recalcAll) = _updateBalances(trackerId, gcId, staking);

        if (recalcAll) {
            _updateAllVotes(trackerId, gcId);
        } else {
            _updateVotes(trackerId, gcId);
        }

        emit RefreshStake(
            trackerId,
            gcId,
            staking,
            newBalance,
            tracker.gcBalances[gcId],
            tracker.gcVotes[gcId],
            tracker.totalVotes
        );
    }

    /// @dev Updates staking and GC balances. Returns new balance and whether a full vote recalc is needed.
    function _updateBalances(
        uint256 trackerId,
        uint256 gcId,
        address staking
    ) private returns (uint256 newBalance, bool recalcAll) {
        Tracker storage tracker = _getStorage().trackers[trackerId];
        bool isCL = tracker.isCLPool[staking];

        newBalance = isCL ? _readCLPoolBalance(staking) : _readCnStakingBalance(staking);

        uint256 oldBalance = tracker.stakingBalances[staking];
        tracker.stakingBalances[staking] = newBalance;
        tracker.gcBalances[gcId] -= oldBalance;
        tracker.gcBalances[gcId] += newBalance;

        if (!isCL) {
            uint256 oldCnBalance = tracker.cnStakingBalances[gcId];
            tracker.cnStakingBalances[gcId] -= oldBalance;
            tracker.cnStakingBalances[gcId] += newBalance;
            recalcAll = _shouldRecalcAllVotes(oldCnBalance, tracker.cnStakingBalances[gcId]);
        }
    }

    /// @dev Returns true if a GC crossed the MIN_STAKE eligibility threshold.
    function _shouldRecalcAllVotes(uint256 oldBalance, uint256 newBalance) private pure returns (bool) {
        return (oldBalance >= _MIN_STAKE) != (newBalance >= _MIN_STAKE);
    }

    /// @dev Called when a GC crosses the eligibility threshold. Updates numEligible and recalculates all votes.
    function _updateAllVotes(uint256 trackerId, uint256 gcId) private {
        Tracker storage tracker = _getStorage().trackers[trackerId];

        if (tracker.cnStakingBalances[gcId] >= _MIN_STAKE) {
            tracker.numEligible++;
        } else {
            tracker.numEligible--;
        }

        _recalcAllVotes(trackerId);
    }

    /// @dev Called when a GC's balance changes but eligibility didn't change. Updates only that GC's votes.
    function _updateVotes(uint256 trackerId, uint256 gcId) private {
        Tracker storage tracker = _getStorage().trackers[trackerId];

        uint256 oldVotes = tracker.gcVotes[gcId];
        uint256 newVotes = _calcVotes(tracker.numEligible, tracker.gcBalances[gcId], tracker.cnStakingBalances[gcId]);
        tracker.gcVotes[gcId] = newVotes;
        tracker.totalVotes -= oldVotes;
        tracker.totalVotes += newVotes;
    }

    /// @dev Recalculates votes for all GCs in a tracker. Only writes to storage if votes changed.
    function _recalcAllVotes(uint256 trackerId) private {
        Tracker storage tracker = _getStorage().trackers[trackerId];
        uint256 len = tracker.gcIds.length;
        uint256 totalVotes;

        for (uint256 i; i < len; i++) {
            uint256 gcId = tracker.gcIds[i];
            uint256 newVotes = _calcVotes(
                tracker.numEligible,
                tracker.gcBalances[gcId],
                tracker.cnStakingBalances[gcId]
            );
            if (tracker.gcVotes[gcId] != newVotes) {
                tracker.gcVotes[gcId] = newVotes;
            }
            totalVotes += newVotes;
        }
        tracker.totalVotes = totalVotes;
    }

    /* ========== INTERNAL: VOTER ========== */

    /// @dev Updates bidirectional voter <-> GC ID mappings.
    function _updateVoter(uint256 gcId, address newVoter) private {
        STv3Storage storage $ = _getStorage();

        address oldVoter = $.gcIdToVoter[gcId];
        if (oldVoter != address(0)) {
            delete $.voterToGCId[oldVoter];
            delete $.gcIdToVoter[gcId];
        }
        if (newVoter != address(0)) {
            if ($.voterToGCId[newVoter] != 0) revert VoterAlreadyRegistered();
            $.voterToGCId[newVoter] = gcId;
            $.gcIdToVoter[gcId] = newVoter;
        }
    }

    /* ========== INTERNAL: READ EXTERNAL ========== */

    /// @dev Reads effective CnStaking balance: staking() - unstaking()
    function _readCnStakingBalance(address staking) private view returns (uint256 balance) {
        balance = ICnStaking(staking).staking() - ICnStaking(staking).unstaking();
    }

    /// @dev Reads CLPool balance via WrappedKaia ERC20 balanceOf
    function _readCLPoolBalance(address pool) private view returns (uint256 balance) {
        address wKaia = IRegistry(_REGISTRY).getActiveAddr("WrappedKaia");
        if (wKaia != address(0)) {
            balance = IERC20(wKaia).balanceOf(pool);
        }
    }

    /// @dev Reads CLRegistry data. Returns empty arrays if CLRegistry is not registered.
    function _getCLRegistryLists() private view returns (uint256[] memory gcIds, address[] memory pools) {
        address clRegistry = IRegistry(_REGISTRY).getActiveAddr("CLRegistry");
        if (clRegistry == address(0)) return (gcIds, pools);

        (, gcIds, pools) = ICLregistry(clRegistry).getAllCLs();
        /// @dev It never happens, but just in case.
        if (gcIds.length != pools.length) revert InvalidCLRegistry();
    }

    /// @dev Checks if a tracker is currently active (trackStart <= block.number < trackEnd)
    function _isTrackerLive(uint256 trackerId) private view returns (bool) {
        Tracker storage tracker = _getStorage().trackers[trackerId];
        return tracker.trackStart <= block.number && block.number < tracker.trackEnd;
    }

    /* ========== GETTERS ========== */

    /// @inheritdoc IStakingTrackerV3
    function getLastTrackerId() external view override returns (uint256) {
        return _getStorage().allTrackerIds.length;
    }

    /// @inheritdoc IStakingTrackerV3
    function getAllTrackerIds() external view override returns (uint256[] memory) {
        return _getStorage().allTrackerIds;
    }

    /// @inheritdoc IStakingTrackerV3
    function getLiveTrackerIds() external view override returns (uint256[] memory) {
        return _getStorage().liveTrackerIds;
    }

    /// @inheritdoc IStakingTrackerV3
    function getTrackerSummary(
        uint256 trackerId
    )
        external
        view
        override
        returns (uint256 trackStart, uint256 trackEnd, uint256 numGCs, uint256 totalVotes, uint256 numEligible)
    {
        Tracker storage tracker = _getStorage().trackers[trackerId];
        return (tracker.trackStart, tracker.trackEnd, tracker.gcIds.length, tracker.totalVotes, tracker.numEligible);
    }

    /// @inheritdoc IStakingTrackerV3
    function getTrackedGC(
        uint256 trackerId,
        uint256 gcId
    ) external view override returns (uint256 gcBalance, uint256 gcVotes) {
        Tracker storage tracker = _getStorage().trackers[trackerId];
        return (tracker.gcBalances[gcId], tracker.gcVotes[gcId]);
    }

    /// @inheritdoc IStakingTrackerV3
    function getTrackedGCBalance(
        uint256 trackerId,
        uint256 gcId
    ) external view override returns (uint256 cnStakingBalance, uint256 gcBalance) {
        Tracker storage tracker = _getStorage().trackers[trackerId];
        return (tracker.cnStakingBalances[gcId], tracker.gcBalances[gcId]);
    }

    /// @inheritdoc IStakingTrackerV3
    function getAllTrackedGCs(
        uint256 trackerId
    ) external view override returns (uint256[] memory gcIds, uint256[] memory gcBalances, uint256[] memory gcVotes) {
        Tracker storage tracker = _getStorage().trackers[trackerId];
        uint256 len = tracker.gcIds.length;
        gcIds = tracker.gcIds;
        gcBalances = new uint256[](len);
        gcVotes = new uint256[](len);
        for (uint256 i; i < len; i++) {
            uint256 gid = gcIds[i];
            gcBalances[i] = tracker.gcBalances[gid];
            gcVotes[i] = tracker.gcVotes[gid];
        }
    }

    /// @inheritdoc IStakingTrackerV3
    function stakingToGCId(uint256 trackerId, address staking) external view override returns (uint256) {
        return _getStorage().trackers[trackerId].stakingToGCId[staking];
    }

    /// @inheritdoc IStakingTrackerV3
    function isCLPool(uint256 trackerId, address staking) external view override returns (bool) {
        return _getStorage().trackers[trackerId].isCLPool[staking];
    }

    /// @inheritdoc IStakingTrackerV3
    function gcIdToVoter(uint256 gcId) external view override returns (address) {
        return _getStorage().gcIdToVoter[gcId];
    }

    /// @inheritdoc IStakingTrackerV3
    function voterToGCId(address voter) external view override returns (uint256) {
        return _getStorage().voterToGCId[voter];
    }

    /* ========== UPGRADE ========== */

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

/// @notice Minimal interface for reading data from AddressBookV2 (0x400)
interface IAddressBookV2 {
    function getAllGovernanceInfo() external view returns (GovernanceInfo[] memory);
    function getNodeInfo(address nodeId) external view returns (NodeInfo memory);
}

/// @notice Minimal interface for reading CnStaking balances
interface ICnStaking {
    function staking() external view returns (uint256);
    function unstaking() external view returns (uint256);
}

/// @notice Minimal interface for reading CLRegistry data
interface ICLregistry {
    function getAllCLs() external view returns (address[] memory, uint256[] memory, address[] memory);
}

/// @notice Minimal ERC20 interface for reading CLPool balances
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}
