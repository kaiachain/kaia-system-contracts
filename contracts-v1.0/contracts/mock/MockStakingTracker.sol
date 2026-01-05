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

contract MockStakingTracker {
    string public CONTRACT_TYPE = "StakingTracker";
    uint256 public VERSION = 1;

    mapping(address => uint256) public voterToGCId;
    uint256[] public liveTrackerIds;

    function mockSetContractType(string memory _contractType) external {
        CONTRACT_TYPE = _contractType;
    }

    function mockSetVersion(uint256 _version) external {
        VERSION = _version;
    }

    function mockSetVoterToGCId(address _voter, uint256 _gcId) external {
        voterToGCId[_voter] = _gcId;
    }

    function mockSetLiveTrackerIds(uint256[] memory _liveTrackerIds) external {
        liveTrackerIds = _liveTrackerIds;
    }

    function getLiveTrackerIds() external view returns (uint256[] memory) {
        return liveTrackerIds;
    }

    function refreshVoter(address _voter) external {
        // Do nothing
    }

    function refreshStake(address _cnStaking) external {
        // Do nothing
    }
}

contract StakingTrackerMockReceiver {
    event RefreshStake();
    event RefreshVoter();

    function refreshStake(address) external {
        emit RefreshStake();
    }

    function refreshVoter(address) external {
        emit RefreshVoter();
    }

    function CONTRACT_TYPE() external pure returns (string memory) {
        return "StakingTracker";
    }

    function VERSION() external pure returns (uint256) {
        return 1;
    }

    function voterToGCId(address) external pure returns (uint256) {
        return 0;
    }

    function getLiveTrackerIds() external pure returns (uint256[] memory) {
        return new uint256[](0);
    }
}

contract StakingTrackerMockActive {
    event RefreshStake();

    function CONTRACT_TYPE() external pure returns (string memory) {
        return "StakingTracker";
    }

    function VERSION() external pure returns (uint256) {
        return 1;
    }

    function refreshStake(address) external {
        emit RefreshStake();
    }

    function getLiveTrackerIds() external pure returns (uint256[] memory) {
        return new uint256[](1);
    }
}

contract StakingTrackerMockWrong {
    function CONTRACT_TYPE() external pure returns (string memory) {
        return "Wrong";
    }

    function VERSION() external pure returns (uint256) {
        return 1;
    }
}
