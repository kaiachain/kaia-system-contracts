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

import {IPublicDelegationDelegator, IPublicDelegation} from "./interfaces/IPublicDelegationDelegator.sol";
import {ICnStaking} from "../CnStaking/CnStakingV4/interfaces/ICnStaking.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title PublicDelegationDelegator
/// @notice Delegator contract for CnStakingV4 with PublicDelegation.
///
/// Separates the delegator's delegation from the delegatee's reward.
/// - DELEGATOR_ROLE: provides delegation, withdraws/claims delegation.
/// - DELEGATEE_ROLE: withdraws/claims reward (PD.maxWithdraw - delegation).
///
/// Both delegation and reward flow through the PublicDelegation (ERC4626 vault).
/// PD uses CN withdrawal request IDs directly — this contract tracks those IDs
/// to separate delegation claims from reward claims.
contract PublicDelegationDelegator is IPublicDelegationDelegator, AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.UintSet;

    /* ========== CONSTANTS ========== */

    bytes32 public constant DELEGATOR_ROLE = keccak256("DELEGATOR_ROLE");
    bytes32 public constant DELEGATEE_ROLE = keccak256("DELEGATEE_ROLE");

    IPublicDelegation public immutable PD;
    ICnStaking public immutable CN;

    /* ========== STATE VARIABLES ========== */

    /// @notice Total delegation from the delegator in KAIA.
    uint256 public delegation;

    // Delegation withdrawal ids.
    EnumerableSet.UintSet private _delegationWithdrawalIds;

    // Reward withdrawal ids.
    EnumerableSet.UintSet private _rewardWithdrawalIds;

    /* ========== MODIFIER ========== */

    modifier notNull(address _address) {
        if (_address == address(0)) revert ZeroAddress();
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _delegator,
        address _delegatee,
        address _publicDelegation
    ) notNull(_delegator) notNull(_delegatee) notNull(_publicDelegation) {
        _grantRole(DELEGATOR_ROLE, _delegator);
        _grantRole(DELEGATEE_ROLE, _delegatee);
        PD = IPublicDelegation(payable(_publicDelegation));
        CN = ICnStaking(payable(PD.baseCnStaking()));
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

    /// @dev Delegates to the Public Delegation contract.
    function delegate() external payable override onlyRole(DELEGATOR_ROLE) {
        if (msg.value == 0) revert ZeroValue();
        delegation += msg.value;
        PD.stake{value: msg.value}();

        emit Delegate(msg.value);
    }

    /* ========== WITHDRAWAL FUNCTIONS ========== */

    /// @dev Withdraws delegation from the Public Delegation contract.
    /// @param _to The address to withdraw the delegation to.
    /// @param _amount The amount of delegation to withdraw in KAIA.
    function withdrawDelegation(address _to, uint256 _amount) external override onlyRole(DELEGATOR_ROLE) {
        if (delegation < _amount) revert InsufficientDelegation();
        delegation -= _amount;
        PD.withdraw(_to, _amount);

        /// @dev userRequestId can't be duplicated
        uint256 _id = PD.userRequestIds(address(this), PD.getUserRequestCount(address(this)) - 1);
        _delegationWithdrawalIds.add(_id);

        emit WithdrawDelegation(_to, _amount, _id);
    }

    /// @dev Withdraws reward from the Public Delegation contract.
    /// @param _to The address to withdraw the reward to.
    /// @param _amount The amount of reward to withdraw in KAIA.
    function withdrawReward(address _to, uint256 _amount) external override onlyRole(DELEGATEE_ROLE) {
        if (withdrawableReward() < _amount) revert InsufficientReward();
        PD.withdraw(_to, _amount);

        /// @dev userRequestId can't be duplicated
        uint256 _id = PD.userRequestIds(address(this), PD.getUserRequestCount(address(this)) - 1);
        _rewardWithdrawalIds.add(_id);

        emit WithdrawReward(_to, _amount, _id);
    }

    /// @dev Claims delegation from the Public Delegation contract.
    /// If the delegation withdrawal was canceled, the delegation should be increased.
    function claimDelegation(uint256 _id) external override onlyRole(DELEGATOR_ROLE) {
        if (!_delegationWithdrawalIds.remove(_id)) revert InvalidWithdrawalId();
        PD.claim(_id);

        if (_isCanceledWithdrawal(_id)) {
            (, uint256 _value, , ) = CN.getApprovedStakingWithdrawalInfo(_id);
            delegation += _value;

            emit ClaimDelegationFailed(_id);
            return;
        }

        emit ClaimDelegation(_id);
    }

    /// @dev Claims reward from the Public Delegation contract.
    function claimReward(uint256 _id) external override onlyRole(DELEGATEE_ROLE) {
        if (!_rewardWithdrawalIds.remove(_id)) revert InvalidWithdrawalId();
        PD.claim(_id);

        if (_isCanceledWithdrawal(_id)) {
            emit ClaimRewardFailed(_id);
            return;
        }

        emit ClaimReward(_id);
    }

    /* ========== INTERNAL ========== */

    function _isCanceledWithdrawal(uint256 _id) internal view returns (bool) {
        return PD.getCurrentWithdrawalRequestState(_id) == IPublicDelegation.WithdrawalRequestState.Canceled;
    }

    /* ========== GETTERS ========== */

    /// @dev Returns the maximum withdrawable reward in KAIA.
    function withdrawableReward() public view override returns (uint256) {
        /// @dev Since maxWithdraw is floor-rounded, it may be less than delegation, which would cause underflow.
        uint256 _maxWithdraw = PD.maxWithdraw(address(this));
        return _maxWithdraw > delegation ? _maxWithdraw - delegation : 0;
    }

    /// @dev Returns the delegation withdrawal ids.
    function delegationWithdrawalIds() external view override returns (uint256[] memory) {
        return _delegationWithdrawalIds.values();
    }

    /// @dev Returns the reward withdrawal ids.
    function rewardWithdrawalIds() external view override returns (uint256[] memory) {
        return _rewardWithdrawalIds.values();
    }
}
