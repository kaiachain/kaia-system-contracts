// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

/// @title IStakingTracker
/// @notice Minimal interface for the StakingTracker contract.
/// @dev Used by AddressBookV2 (refreshVoter, revokeVoter) and CnStakingV4 (refreshStake).
interface IStakingTracker {
    function refreshVoter(address nodeId) external;
    function revokeVoter(uint256 gcId) external;
    function refreshStake(address staking) external;
}
