// Copyright 2024 The kaia Authors
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

import "../PublicDelegation/interfaces/IPublicDelegation.sol";

interface IDelegator {
    /* ========== EVENTS ========== */

    event Delegate(uint256 amount);

    event WithdrawDelegation(address indexed to, uint256 amount, uint256 id);

    event WithdrawReward(address indexed to, uint256 amount, uint256 id);

    event ClaimDelegation(uint256 id);

    event ClaimDelegationFailed(uint256 id);

    event ClaimReward(uint256 id);

    event ClaimRewardFailed(uint256 id);

    /* ========== CONSTANT/IMMUTABLE GETTERS ========== */

    function DELEGATOR_ROLE() external view returns (bytes32);

    function DELEGATEE_ROLE() external view returns (bytes32);

    function PD() external view returns (IPublicDelegation);

    /* ========== ROLE MANAGEMENT FUNCTIONS ========== */

    function transferDelegator(address _newDelegator) external;

    function transferDelegatee(address _newDelegatee) external;

    /* ========== DELEGATION FUNCTIONS ========== */

    function delegate() external payable;

    function withdrawDelegation(address _to, uint256 _amount) external;

    function withdrawReward(address _to, uint256 _amount) external;

    function claimDelegation(uint256 _id) external;

    function claimReward(uint256 _id) external;

    /* ========== PUBLIC GETTERS ========== */

    function delegation() external view returns (uint256);

    function withdrawableReward() external view returns (uint256);

    function delegationWithdrawalIds() external view returns (uint256[] memory);

    function rewardWithdrawalIds() external view returns (uint256[] memory);
}
