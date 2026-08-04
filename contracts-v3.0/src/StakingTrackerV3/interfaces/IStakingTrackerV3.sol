// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

/// @title IStakingTrackerV3
/// @notice Full interface for StakingTrackerV3
interface IStakingTrackerV3 {
    // ========== EVENTS ==========

    event CreateTracker(uint256 indexed trackerId, uint256 trackStart, uint256 trackEnd, uint256[] gcIds);
    event RetireTracker(uint256 indexed trackerId);
    event RefreshStake(
        uint256 indexed trackerId,
        uint256 indexed gcId,
        address staking,
        uint256 stakingBalance,
        uint256 gcBalance,
        uint256 gcVote,
        uint256 totalVotes
    );
    event RefreshVoter(uint256 indexed gcId, address voter);

    // ========== ERRORS ==========

    error VoterAlreadyRegistered();

    error InvalidCLRegistry();

    error NotAddressBook();

    // ========== CONSTANTS ==========

    /// @notice Returns contract type identifier ("StakingTracker")
    function CONTRACT_TYPE() external pure returns (string memory);

    /// @notice Returns contract version
    function VERSION() external pure returns (uint256);

    /// @notice Returns AddressBook address (0x400)
    function ADDRESS_BOOK_ADDRESS() external pure returns (address);

    /// @notice Returns Registry address (0x401)
    function REGISTRY_ADDRESS() external pure returns (address);

    /// @notice Returns minimum stake for voting eligibility (5M KAIA)
    function MIN_STAKE() external pure returns (uint256);

    // ========== MUTATORS ==========

    /// @notice Creates a new tracker for a block range, only callable by owner, which is Voting contract
    /// @param trackStart Block number when tracker becomes active
    /// @param trackEnd Block number when tracker expires
    /// @return trackerId The new tracker ID (1-indexed, sequential)
    function createTracker(uint256 trackStart, uint256 trackEnd) external returns (uint256 trackerId);

    /// @notice Updates balances and voting power for a staking contract across all live trackers
    /// @dev Also retires expired trackers. Passing address(0) only cleans up expired trackers.
    /// @param staking The staking contract or CL pool address
    function refreshStake(address staking) external;

    /// @notice Updates voter mapping for a node by reading its info from ABv2.
    /// @dev Silently ignores gcId == 0 (node not yet in governance). Anyone can call.
    /// @param nodeId The node address to refresh voter for
    function refreshVoter(address nodeId) external;

    /// @notice Deletes the voter mapping for `gcId` (`gcIdToVoter[gcId]` and its `voterToGCId`).
    /// @dev Only the AddressBook (0x400) may call. `refreshVoter` re-derives state from ABv2 so
    ///      anyone may call it; this clears the given `gcId` unconditionally, so restricting the
    ///      caller keeps it from wiping a live GC's voter.
    /// @param gcId The GC ID whose voter mapping to clear
    function revokeVoter(uint256 gcId) external;

    // ========== GETTERS ==========

    /// @notice Returns the total number of trackers created
    function getLastTrackerId() external view returns (uint256);

    /// @notice Returns all tracker IDs ever created
    function getAllTrackerIds() external view returns (uint256[] memory);

    /// @notice Returns IDs of currently active trackers
    function getLiveTrackerIds() external view returns (uint256[] memory);

    /// @notice Returns summary data for a tracker
    function getTrackerSummary(
        uint256 trackerId
    )
        external
        view
        returns (uint256 trackStart, uint256 trackEnd, uint256 numGCs, uint256 totalVotes, uint256 numEligible);

    /// @notice Returns balance and votes for a GC within a tracker
    function getTrackedGC(uint256 trackerId, uint256 gcId) external view returns (uint256 gcBalance, uint256 gcVotes);

    /// @notice Returns separate CnStaking and total balance for a GC
    function getTrackedGCBalance(
        uint256 trackerId,
        uint256 gcId
    ) external view returns (uint256 cnStakingBalance, uint256 gcBalance);

    /// @notice Returns all GCs in a tracker with their balances and votes
    function getAllTrackedGCs(
        uint256 trackerId
    ) external view returns (uint256[] memory gcIds, uint256[] memory gcBalances, uint256[] memory gcVotes);

    /// @notice Maps a staking contract to its GC ID within a tracker
    function stakingToGCId(uint256 trackerId, address staking) external view returns (uint256 gcId);

    /// @notice Checks if a staking address is a CL pool within a tracker
    function isCLPool(uint256 trackerId, address staking) external view returns (bool);

    /// @notice Maps a GC ID to its voter address
    function gcIdToVoter(uint256 gcId) external view returns (address voter);

    /// @notice Maps a voter address to its GC ID
    function voterToGCId(address voter) external view returns (uint256 gcId);
}
