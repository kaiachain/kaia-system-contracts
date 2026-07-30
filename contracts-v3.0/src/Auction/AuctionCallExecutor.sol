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

/// @title AuctionCallExecutor
/// @notice Executes external calls for AuctionEntryPoint. Holds no roles or ownership on any
///         contract, so it acts as a plain unprivileged account.
/// @dev Stateless and unprivileged by design; MUST never be granted any role or ownership.
contract AuctionCallExecutor {
    /// @notice The only address allowed to drive execution (the AuctionEntryPoint).
    address public immutable entryPoint;

    error OnlyEntryPoint();

    constructor(address _entryPoint) {
        entryPoint = _entryPoint;
    }

    /// @notice Forward a call to `to` with `data`, capped at `gasLimit` gas.
    /// @param to The call target.
    /// @param gasLimit Gas forwarded to the target.
    /// @param data The calldata.
    /// @return success Whether the target call succeeded.
    /// @dev Restricted to `entryPoint`.
    function execute(address to, uint256 gasLimit, bytes calldata data) external returns (bool success) {
        if (msg.sender != entryPoint) revert OnlyEntryPoint();
        (success, ) = to.call{gas: gasLimit}(data);
    }
}
