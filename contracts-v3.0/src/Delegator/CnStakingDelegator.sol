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

import {ICnStakingDelegator, ICnStaking} from "./interfaces/ICnStakingDelegator.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title CnStakingDelegator
/// @notice Delegator contract for CnStakingV4 without PublicDelegation.
///
/// Separates the delegator's delegation from the validator's own stake.
/// - DELEGATOR_ROLE: provides delegation, withdraws/claims delegation.
/// - DELEGATEE_ROLE: withdraws/claims validator's portion (CN.staking - CN.unstaking - delegation).
///
/// Rewards are NOT managed here — they go to a separate rewardAddress in ABv2.
/// Since CnStakingV4 without PD allows permissionless staking (anyone can call delegate()),
/// the validator stakes directly to CnStakingV4. This contract must be the owner of CnStakingV4
/// to call the unstaking functions (onlyUnstakingManager = owner when no PD).
contract CnStakingDelegator is ICnStakingDelegator, AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.UintSet;

    /* ========== CONSTANTS ========== */

    bytes32 public constant DELEGATOR_ROLE = keccak256("DELEGATOR_ROLE");
    bytes32 public constant DELEGATEE_ROLE = keccak256("DELEGATEE_ROLE");

    ICnStaking public immutable CN;

    /* ========== STATE VARIABLES ========== */

    /// @notice Total delegation from the delegator in KAIA.
    uint256 public delegation;

    /// @dev Delegation withdrawal request IDs.
    EnumerableSet.UintSet private _delegationWithdrawalIds;

    /// @dev Staking (validator) withdrawal request IDs.
    EnumerableSet.UintSet private _stakingWithdrawalIds;

    /* ========== MODIFIER ========== */

    modifier notNull(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    /// @param _delegator  The delegator address (provides delegation).
    /// @param _delegatee  The delegatee/validator address (stakes permissionlessly, withdraws their portion).
    /// @param _cnStaking  The CnStakingV4 contract (must have no PD, this contract must be its owner).
    constructor(
        address _delegator,
        address _delegatee,
        address _cnStaking
    ) notNull(_delegator) notNull(_delegatee) notNull(_cnStaking) {
        _grantRole(DELEGATOR_ROLE, _delegator);
        _grantRole(DELEGATEE_ROLE, _delegatee);
        CN = ICnStaking(payable(_cnStaking));
    }

    /* ========== ROLE MANAGEMENT FUNCTIONS ========== */

    function transferDelegator(
        address _newDelegator
    ) external override onlyRole(DELEGATOR_ROLE) notNull(_newDelegator) {
        if (!_grantRole(DELEGATOR_ROLE, _newDelegator)) revert SameAddress();
        _revokeRole(DELEGATOR_ROLE, msg.sender);
    }

    function transferDelegatee(
        address _newDelegatee
    ) external override onlyRole(DELEGATEE_ROLE) notNull(_newDelegatee) {
        if (!_grantRole(DELEGATEE_ROLE, _newDelegatee)) revert SameAddress();
        _revokeRole(DELEGATEE_ROLE, msg.sender);
    }

    /* ========== DELEGATION FUNCTIONS ========== */

    /// @dev Delegates KAIA to CnStakingV4.
    function delegate() external payable override onlyRole(DELEGATOR_ROLE) {
        if (msg.value == 0) revert ZeroValue();
        delegation += msg.value;
        CN.delegate{value: msg.value}();

        emit Delegate(msg.value);
    }

    /// @dev Initiates withdrawal of delegator's delegation.
    /// @param _to The address to receive the withdrawn delegation.
    /// @param _amount The amount of delegation to withdraw in KAIA.
    function withdrawDelegation(address _to, uint256 _amount) external override onlyRole(DELEGATOR_ROLE) {
        if (delegation < _amount) revert InsufficientDelegation();
        delegation -= _amount;
        uint256 _id = CN.approveStakingWithdrawal(_to, _amount);
        _delegationWithdrawalIds.add(_id);

        emit WithdrawDelegation(_to, _amount, _id);
    }

    /// @dev Claims a delegation withdrawal. If auto-canceled, restores delegation.
    function claimDelegation(uint256 _id) external override onlyRole(DELEGATOR_ROLE) {
        if (!_delegationWithdrawalIds.remove(_id)) revert InvalidWithdrawalId();
        CN.withdrawApprovedStaking(_id);

        if (_isCanceled(_id)) {
            (, uint256 _value, , ) = CN.getApprovedStakingWithdrawalInfo(_id);
            delegation += _value;

            emit ClaimDelegationFailed(_id);
            return;
        }

        emit ClaimDelegation(_id);
    }

    /* ========== STAKING FUNCTIONS ========== */

    /// @dev Initiates withdrawal of validator's staking portion.
    /// @param _to The address to receive the withdrawn staking.
    /// @param _amount The amount of staking to withdraw in KAIA.
    function withdrawStaking(address _to, uint256 _amount) external override onlyRole(DELEGATEE_ROLE) {
        if (withdrawableStaking() < _amount) revert InsufficientStaking();
        uint256 _id = CN.approveStakingWithdrawal(_to, _amount);
        _stakingWithdrawalIds.add(_id);

        emit WithdrawStaking(_to, _amount, _id);
    }

    /// @dev Claims a staking withdrawal. No state update needed on cancel
    ///      because withdrawableStaking() self-adjusts when CN.unstaking decreases.
    function claimStaking(uint256 _id) external override onlyRole(DELEGATEE_ROLE) {
        if (!_stakingWithdrawalIds.remove(_id)) revert InvalidWithdrawalId();
        CN.withdrawApprovedStaking(_id);

        if (_isCanceled(_id)) {
            emit ClaimStakingFailed(_id);
            return;
        }

        emit ClaimStaking(_id);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    /// @dev Transfers CnStakingV4 ownership to the delegatee. Only callable by delegator when delegation is empty.
    ///      _newOwner must hold DELEGATEE_ROLE, so ownership can only move to the designated delegatee.
    function transferCnOwnership(address _newOwner) external override onlyRole(DELEGATOR_ROLE) notNull(_newOwner) {
        if (delegation != 0) revert DelegationNotEmpty();
        if (!hasRole(DELEGATEE_ROLE, _newOwner)) revert NotDelegatee();
        Ownable(address(CN)).transferOwnership(_newOwner);
    }

    /* ========== INTERNAL ========== */

    function _isCanceled(uint256 _id) internal view returns (bool) {
        (, , , ICnStaking.WithdrawalStakingState state) = CN.getApprovedStakingWithdrawalInfo(_id);
        return state == ICnStaking.WithdrawalStakingState.Canceled;
    }

    /* ========== GETTERS ========== */

    /// @dev Returns the validator's withdrawable staking amount.
    /// Formula: CN.staking - CN.unstaking - delegation
    ///   CN.staking - CN.unstaking = total net effective stake
    ///   delegation = delegator's claimed portion
    ///   difference = validator's available portion
    function withdrawableStaking() public view override returns (uint256) {
        return CN.staking() - CN.unstaking() - delegation;
    }

    /// @dev Returns the delegation withdrawal IDs.
    function delegationWithdrawalIds() external view override returns (uint256[] memory) {
        return _delegationWithdrawalIds.values();
    }

    /// @dev Returns the staking withdrawal IDs.
    function stakingWithdrawalIds() external view override returns (uint256[] memory) {
        return _stakingWithdrawalIds.values();
    }
}
