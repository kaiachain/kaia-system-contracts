// Copyright 2026 The kaia Authors
// This file is part of the kaia library.
//
// The kaia library is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// The kaia library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with the kaia library. If not, see <http://www.gnu.org/licenses/>.

// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import "../../PublicDelegation/interfaces/IPublicDelegation.sol";
import {ICnStaking} from "../../CnStaking/CnStakingV4/interfaces/ICnStaking.sol";

/// @title IPublicDelegationDelegator
/// @notice Interface for PublicDelegationDelegator — separates delegator's delegation from
///         delegatee's reward, both flowing through a PublicDelegation (ERC4626 vault).
interface IPublicDelegationDelegator {
    /* ========== ERRORS ========== */

    error ZeroAddress();
    error ZeroValue();
    error SameAddress();
    error InsufficientDelegation();
    error InsufficientReward();
    error InvalidWithdrawalId();

    /* ========== EVENTS ========== */

    /// @notice Emitted when the delegator stakes KAIA into the PD vault.
    /// @param amount The amount of KAIA delegated.
    event Delegate(uint256 amount);

    /// @notice Emitted when a delegation withdrawal request is created.
    /// @param to The recipient address for the withdrawn KAIA.
    /// @param amount The amount of KAIA to withdraw.
    /// @param id The CN withdrawal request ID.
    event WithdrawDelegation(address indexed to, uint256 amount, uint256 id);

    /// @notice Emitted when a reward withdrawal request is created.
    /// @param to The recipient address for the withdrawn reward.
    /// @param amount The amount of KAIA reward to withdraw.
    /// @param id The CN withdrawal request ID.
    event WithdrawReward(address indexed to, uint256 amount, uint256 id);

    /// @notice Emitted when a delegation withdrawal is successfully claimed.
    /// @param id The CN withdrawal request ID.
    event ClaimDelegation(uint256 id);

    /// @notice Emitted when a delegation withdrawal is auto-canceled (2*STAKE_LOCKUP passed).
    /// @param id The CN withdrawal request ID.
    event ClaimDelegationFailed(uint256 id);

    /// @notice Emitted when a reward withdrawal is successfully claimed.
    /// @param id The CN withdrawal request ID.
    event ClaimReward(uint256 id);

    /// @notice Emitted when a reward withdrawal is auto-canceled (2*STAKE_LOCKUP passed).
    /// @param id The CN withdrawal request ID.
    event ClaimRewardFailed(uint256 id);

    /* ========== CONSTANT/IMMUTABLE GETTERS ========== */

    /// @notice Returns the DELEGATOR_ROLE identifier.
    function DELEGATOR_ROLE() external view returns (bytes32);

    /// @notice Returns the DELEGATEE_ROLE identifier.
    function DELEGATEE_ROLE() external view returns (bytes32);

    /// @notice Returns the PublicDelegation (ERC4626 vault) contract.
    function PD() external view returns (IPublicDelegation);

    /// @notice Returns the underlying CnStakingV4 contract.
    function CN() external view returns (ICnStaking);

    /* ========== ROLE MANAGEMENT FUNCTIONS ========== */

    /// @notice Transfers the DELEGATOR_ROLE to a new address. Caller loses the role.
    /// @param _newDelegator The address to receive DELEGATOR_ROLE.
    function transferDelegator(address _newDelegator) external;

    /// @notice Transfers the DELEGATEE_ROLE to a new address. Caller loses the role.
    /// @param _newDelegatee The address to receive DELEGATEE_ROLE.
    function transferDelegatee(address _newDelegatee) external;

    /* ========== DELEGATION FUNCTIONS ========== */

    /// @notice Delegates KAIA to the PD vault, increasing delegation. DELEGATOR_ROLE only.
    function delegate() external payable;

    /// @notice Creates a delegation withdrawal request via PD. DELEGATOR_ROLE only.
    /// @param _to The recipient address.
    /// @param _amount The amount of delegation to withdraw in KAIA.
    function withdrawDelegation(address _to, uint256 _amount) external;

    /// @notice Creates a reward withdrawal request via PD. DELEGATEE_ROLE only.
    /// @param _to The recipient address.
    /// @param _amount The amount of reward to withdraw in KAIA.
    function withdrawReward(address _to, uint256 _amount) external;

    /// @notice Claims a delegation withdrawal. Restores delegation if auto-canceled. DELEGATOR_ROLE only.
    /// @param _id The CN withdrawal request ID.
    function claimDelegation(uint256 _id) external;

    /// @notice Claims a reward withdrawal. DELEGATEE_ROLE only.
    /// @param _id The CN withdrawal request ID.
    function claimReward(uint256 _id) external;

    /* ========== PUBLIC GETTERS ========== */

    /// @notice Returns the delegator's tracked delegation in KAIA.
    function delegation() external view returns (uint256);

    /// @notice Returns the maximum reward withdrawable by the delegatee in KAIA.
    ///         Computed as PD.maxWithdraw(this) - delegation.
    function withdrawableReward() external view returns (uint256);

    /// @notice Returns the pending delegation withdrawal request IDs.
    function delegationWithdrawalIds() external view returns (uint256[] memory);

    /// @notice Returns the pending reward withdrawal request IDs.
    function rewardWithdrawalIds() external view returns (uint256[] memory);
}
