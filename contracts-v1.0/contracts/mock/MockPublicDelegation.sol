// Copyright 2025 The kaia Authors
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
pragma solidity ^0.8.0;

contract MockPublicDelegation {
    mapping(address => uint256) public maxRedeem;
    mapping(uint256 => address) public requestIdToOwner;

    function mockSetMaxRedeem(address _address, uint256 _maxRedeem) external {
        maxRedeem[_address] = _maxRedeem;
    }

    function mockSetRequestIdToOwner(uint256 _requestId, address _owner) external {
        requestIdToOwner[_requestId] = _owner;
    }

    function redeem(address _to, uint256 _shares) external {
        require(_shares <= maxRedeem[_to], "MockPublicDelegation: shares exceed max redeem");
    }

    function claim(uint256 _requestId) external {
        require(requestIdToOwner[_requestId] == msg.sender, "MockPublicDelegation: invalid request owner");
    }
}
