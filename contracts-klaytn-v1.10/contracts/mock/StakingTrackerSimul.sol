// Copyright 2022 The klaytn Authors
// This file is part of the klaytn library.
//
// The klaytn library is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// The klaytn library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with the klaytn library. If not, see <http://www.gnu.org/licenses/>.

// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "../StakingTracker.sol";

interface ICnStakingV3 {
    function publicDelegation() external view returns (address);
}

contract StakingTrackerSimulV3 is StakingTracker {
    // Simulates the result of a createTracker() call
    // without actually making a state change.
    function simulateTracker()
        public
        virtual
        returns (
            uint256 numGCs,
            uint256 totalVotes,
            uint256 numEligible,
            uint256[] memory gcIds,
            uint256[] memory gcBalances,
            uint256[] memory gcVotes
        )
    {
        // A state-changing function can be called via either state-changing way
        // (e.g. eth_sendTransaction) or read-only way (e.g. eth_call).
        // The first case would uselessly write state data.
        // This function is intended to be used as the second case only.
        //
        // Because there is no viable way to eth_sendTransaction with msg.sender == 0x0,
        // this function must be called via eth_call.
        // Then all state changes will be temporary yet return the simulated
        // createTracker() result at current block.
        require(msg.sender == address(0));

        _transferOwnership(msg.sender);
        uint256 trackerId = createTracker(block.number, block.number + 1);

        (, , uint256 _numGCs, uint256 _totalVotes, uint256 _numEligible) = getTrackerSummary(trackerId);
        (uint256[] memory _gcIds, uint256[] memory _gcBalances, uint256[] memory _gcVotes) = getAllTrackedGCs(
            trackerId
        );
        return (_numGCs, _totalVotes, _numEligible, _gcIds, _gcBalances, _gcVotes);
    }

    function dumpAddressBook()
        public
        view
        virtual
        returns (
            address[] memory nodeIds,
            address[] memory stakingContracts,
            address[] memory rewardAddrs,
            address[] memory pdAddrs,
            uint256[] memory stakingContractVersions,
            uint256[] memory stakingContractBalances, // in peb
            uint256[] memory stakingContractEffectiveBalances, // in peb
            uint256[] memory stakingContractGCIds
        )
    {
        (nodeIds, stakingContracts, rewardAddrs) = getAddressBookLists();

        uint256 len = stakingContracts.length;
        pdAddrs = new address[](len);
        stakingContractVersions = new uint256[](len);
        stakingContractBalances = new uint256[](len);
        stakingContractEffectiveBalances = new uint256[](len);
        stakingContractGCIds = new uint256[](len);

        for (uint256 i = 0; i < stakingContracts.length; i++) {
            address staking = stakingContracts[i];

            if (isCnStakingV2(staking)) {
                uint256 version = ICnStakingV2(staking).VERSION();
                pdAddrs[i] = version == 3 ? ICnStakingV3(payable(staking)).publicDelegation() : address(0);
                stakingContractVersions[i] = version;
                stakingContractBalances[i] = staking.balance;
                stakingContractEffectiveBalances[i] = staking.balance - ICnStakingV2(staking).unstaking();
                stakingContractGCIds[i] = ICnStakingV2(staking).gcId();
            } else {
                pdAddrs[i] = address(0);
                stakingContractVersions[i] = 1;
                stakingContractBalances[i] = staking.balance;
                stakingContractEffectiveBalances[i] = 0;
                stakingContractGCIds[i] = 0;
            }
        }
    }
}

contract StakingTrackerSimul is StakingTracker {
    // Simulates the result of a createTracker() call
    // without actually making a state change.
    function simulateTracker()
        public
        virtual
        returns (
            uint256 numGCs,
            uint256 totalVotes,
            uint256 numEligible,
            uint256[] memory gcIds,
            uint256[] memory gcBalances,
            uint256[] memory gcVotes
        )
    {
        // A state-changing function can be called via either state-changing way
        // (e.g. eth_sendTransaction) or read-only way (e.g. eth_call).
        // The first case would uselessly write state data.
        // This function is intended to be used as the second case only.
        //
        // Because there is no viable way to eth_sendTransaction with msg.sender == 0x0,
        // this function must be called via eth_call.
        // Then all state changes will be temporary yet return the simulated
        // createTracker() result at current block.
        require(msg.sender == address(0));

        _transferOwnership(msg.sender);
        uint256 trackerId = createTracker(block.number, block.number + 1);

        (, , uint256 _numGCs, uint256 _totalVotes, uint256 _numEligible) = getTrackerSummary(trackerId);
        (uint256[] memory _gcIds, uint256[] memory _gcBalances, uint256[] memory _gcVotes) = getAllTrackedGCs(
            trackerId
        );
        return (_numGCs, _totalVotes, _numEligible, _gcIds, _gcBalances, _gcVotes);
    }

    function dumpAddressBook()
        public
        view
        virtual
        returns (
            address[] memory nodeIds,
            address[] memory stakingContracts,
            address[] memory rewardAddrs,
            uint256[] memory stakingContractVersions,
            uint256[] memory stakingContractBalances, // in peb
            uint256[] memory stakingContractEffectiveBalances, // in peb
            uint256[] memory stakingContractGCIds
        )
    {
        (nodeIds, stakingContracts, rewardAddrs) = getAddressBookLists();

        uint256 len = stakingContracts.length;
        stakingContractVersions = new uint256[](len);
        stakingContractBalances = new uint256[](len);
        stakingContractEffectiveBalances = new uint256[](len);
        stakingContractGCIds = new uint256[](len);

        for (uint256 i = 0; i < stakingContracts.length; i++) {
            address staking = stakingContracts[i];

            if (isCnStakingV2(staking)) {
                stakingContractVersions[i] = ICnStakingV2(staking).VERSION();
                stakingContractBalances[i] = staking.balance;
                stakingContractEffectiveBalances[i] = staking.balance - ICnStakingV2(staking).unstaking();
                stakingContractGCIds[i] = ICnStakingV2(staking).gcId();
            } else {
                stakingContractVersions[i] = 1;
                stakingContractBalances[i] = staking.balance;
                stakingContractEffectiveBalances[i] = 0;
                stakingContractGCIds[i] = 0;
            }
        }
    }
}

contract StakingTrackerSimulBaobab is StakingTrackerSimul {
    function readCnStaking(
        address staking
    )
        public
        view
        override
        returns (bool isV2, uint256 effectiveBalance, uint256 gcId, address stakingTracker, address voterAddress)
    {
        if (isCnStakingV2(staking)) {
            // Only recognize those configured with the official StakingTracker.
            address tracker = ICnStakingV2(staking).stakingTracker();
            if (tracker == 0x8Fe0f06DF2C95B8D5D9D4232405614E505Ab04C0) {
                tracker = address(this); // The StakingTrackerSimul will recognize this staking contract.
            } else {
                tracker = address(0); // The StakingTrackerSimul will ignore this staking contract.
            }

            return (
                true,
                staking.balance - ICnStakingV2(staking).unstaking(),
                ICnStakingV2(staking).gcId(),
                tracker,
                ICnStakingV2(staking).voterAddress()
            );
        }
        return (false, 0, 0, address(0), address(0));
    }
}

contract StakingTrackerSimulCypress is StakingTrackerSimul {
    function readCnStaking(
        address staking
    )
        public
        view
        override
        returns (bool isV2, uint256 effectiveBalance, uint256 gcId, address stakingTracker, address voterAddress)
    {
        if (isCnStakingV2(staking)) {
            // Only recognize those configured with the official StakingTracker.
            address tracker = ICnStakingV2(staking).stakingTracker();
            if (tracker == 0x9b8688d616D3D5180d29520c6a0E28582E82BF4d) {
                tracker = address(this); // The StakingTrackerSimul will recognize this staking contract.
            } else {
                tracker = address(0); // The StakingTrackerSimul will ignore this staking contract.
            }

            return (
                true,
                staking.balance - ICnStakingV2(staking).unstaking(),
                ICnStakingV2(staking).gcId(),
                tracker,
                ICnStakingV2(staking).voterAddress()
            );
        }
        return (false, 0, 0, address(0), address(0));
    }
}
