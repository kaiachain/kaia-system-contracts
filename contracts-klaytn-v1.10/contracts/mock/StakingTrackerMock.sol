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
import "./StakingTrackerSimul.sol";

contract StakingTrackerMock is StakingTracker, StakingTrackerSimul {
    address private addressBookAddress = 0x0000000000000000000000000000000000000400;

    function mockSetAddressBookAddress(address _addr) external {
        addressBookAddress = _addr;
    }

    function ADDRESS_BOOK_ADDRESS() public view override returns (address) {
        return addressBookAddress;
    }

    function mockSetOwner(address newOwner) external {
        _transferOwnership(newOwner);
    }

    function mockSetVoter(uint256 gcId, address newVoter) external {
        updateVoter(gcId, newVoter);
        emit RefreshVoter(gcId, address(0), newVoter);
    }
}

contract StakingTrackerMockIgnoreST is StakingTrackerMock {
    function readCnStaking(
        address staking
    )
        public
        view
        override
        returns (bool isV2, uint256 effectiveBalance, uint256 gcId, address stakingTracker, address voterAddress)
    {
        if (isCnStakingV2(staking)) {
            return (
                true,
                staking.balance - ICnStakingV2(staking).unstaking(),
                ICnStakingV2(staking).gcId(),
                address(this), // MOCK
                ICnStakingV2(staking).voterAddress()
            );
        }
        return (false, 0, 0, address(0), address(0));
    }
}

contract StakingTrackerMockIncludeV1 is StakingTrackerMock {
    function readCnStaking(
        address staking
    )
        public
        view
        override
        returns (bool isV2, uint256 effectiveBalance, uint256 gcId, address stakingTracker, address voterAddress)
    {
        // To take V1 into account, we give up several features.
        address rewardAddr = ICnStakingV2(staking).rewardAddress();
        uint256 mockGCId = uint256(uint8(uint160(rewardAddr)));
        return (
            true, // MOCK: treat V1 as V2
            staking.balance, // MOCK: ignore unstaking()
            mockGCId, // MOCK: derive mock gcId from rewardAddr
            address(this), // MOCK: assume that the staking points to this.
            address(0)
        ); // MOCK: ignore voter account
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

contract StakingTrackerMockInvalid {
    function CONTRACT_TYPE() external pure returns (string memory) {
        return "";
    }
    // no VERSION() function
}

contract StakingTrackerMockBaobabHardcode is StakingTracker {
    function createTracker(uint256 trackStart, uint256 trackEnd) public override onlyOwner returns (uint256 trackerId) {
        trackerId = getLastTrackerId() + 1;
        allTrackerIds.push(trackerId);
        liveTrackerIds.push(trackerId);

        Tracker storage tracker = trackers[trackerId];
        tracker.trackStart = trackStart;
        tracker.trackEnd = trackEnd;

        // https://baobab-square.qa.klaytn.net/GC
        // GroundX 16,17,18,19
        tracker.gcIds.push(113);
        tracker.gcIds.push(114);
        tracker.gcIds.push(115);
        tracker.gcIds.push(116);

        tracker.gcBalances[113] = 1 * 5000000 ether;
        tracker.gcBalances[114] = 2 * 5000000 ether;
        tracker.gcBalances[115] = 3 * 5000000 ether;
        tracker.gcBalances[116] = 4 * 5000000 ether;

        gcIdToVoter[113] = 0x3679920907350c3abd23480F47919966B178307a;
        gcIdToVoter[114] = 0xC129C1CAFB33Bb1C387749F71978Cb5d82aD2f8c;
        gcIdToVoter[115] = 0xb43aBE0bc4a8777F247382e7C65E23D213908994;
        gcIdToVoter[116] = 0x93182F679ED3956380482D33b22D8B67F85Ba763;
        voterToGCId[0x3679920907350c3abd23480F47919966B178307a] = 113;
        voterToGCId[0xC129C1CAFB33Bb1C387749F71978Cb5d82aD2f8c] = 114;
        voterToGCId[0xb43aBE0bc4a8777F247382e7C65E23D213908994] = 115;
        voterToGCId[0x93182F679ED3956380482D33b22D8B67F85Ba763] = 116;

        calcAllVotes(trackerId);
        return trackerId;
    }
}

contract StakingTrackerMockCypressHardcode is StakingTracker {
    function createTracker(uint256 trackStart, uint256 trackEnd) public override onlyOwner returns (uint256 trackerId) {
        trackerId = getLastTrackerId() + 1;
        allTrackerIds.push(trackerId);
        liveTrackerIds.push(trackerId);

        Tracker storage tracker = trackers[trackerId];
        tracker.trackStart = trackStart;
        tracker.trackEnd = trackEnd;

        // https://klaytn-foundation.atlassian.net/browse/KSV-124
        tracker.gcIds.push(23);
        tracker.gcIds.push(24);
        tracker.gcIds.push(25);
        tracker.gcIds.push(26);
        tracker.gcIds.push(27);
        tracker.gcIds.push(28);
        tracker.gcIds.push(29);
        tracker.gcIds.push(30);
        tracker.gcIds.push(31);
        tracker.gcIds.push(32);
        tracker.gcIds.push(33);
        tracker.gcIds.push(34);
        tracker.gcIds.push(35);
        tracker.gcIds.push(38);
        tracker.gcIds.push(39);
        tracker.gcIds.push(40);
        tracker.gcIds.push(41);
        tracker.gcIds.push(44);
        tracker.gcIds.push(45);
        tracker.gcIds.push(46);
        tracker.gcIds.push(47);
        tracker.gcIds.push(49);
        tracker.gcIds.push(51);
        tracker.gcIds.push(52);
        tracker.gcIds.push(55);
        tracker.gcIds.push(56);
        tracker.gcIds.push(58);
        tracker.gcIds.push(61);
        tracker.gcIds.push(67);
        tracker.gcIds.push(76);

        tracker.gcBalances[23] = 269705495 ether;
        tracker.gcBalances[24] = 134117272 ether;
        tracker.gcBalances[25] = 10000000 ether;
        tracker.gcBalances[26] = 94987942 ether;
        tracker.gcBalances[27] = 36358982 ether;
        tracker.gcBalances[28] = 31354353 ether;
        tracker.gcBalances[29] = 35822819 ether;
        tracker.gcBalances[30] = 26269640 ether;
        tracker.gcBalances[31] = 53333332 ether;
        tracker.gcBalances[32] = 27419082 ether;
        tracker.gcBalances[33] = 31352727 ether;
        tracker.gcBalances[34] = 29058553 ether;
        tracker.gcBalances[35] = 12411000 ether;
        tracker.gcBalances[38] = 20422474 ether;
        tracker.gcBalances[39] = 14967342 ether;
        tracker.gcBalances[40] = 10000000 ether;
        tracker.gcBalances[41] = 10000000 ether;
        tracker.gcBalances[44] = 9080099 ether;
        tracker.gcBalances[45] = 6847450 ether;
        tracker.gcBalances[46] = 6597571 ether;
        tracker.gcBalances[47] = 6570001 ether;
        tracker.gcBalances[49] = 31352808 ether;
        tracker.gcBalances[51] = 37975291 ether;
        tracker.gcBalances[52] = 5000001 ether;
        tracker.gcBalances[55] = 5000000 ether;
        tracker.gcBalances[56] = 5000000 ether;
        tracker.gcBalances[58] = 5000000 ether;
        tracker.gcBalances[61] = 5078101 ether;
        tracker.gcBalances[67] = 5001050 ether;
        tracker.gcBalances[76] = 5000012 ether;

        gcIdToVoter[23] = 0x2F8696aB2B65F699185D77380ee344701a10756c;
        gcIdToVoter[24] = 0x78B55BCA9d52D328B8b95cbDfae697639c75F1eE;
        gcIdToVoter[25] = 0xAd1eB9e472234A862b5632E0262343f5E2159905;
        gcIdToVoter[26] = 0xDfD9B804ebC47d8b75908297142e19eF7B0bc123;
        gcIdToVoter[27] = 0xDDE26721b0F972b73bb3a8936882c31D54E4beE0;
        gcIdToVoter[28] = 0xD8de51A515Dd8c8EECa97bDAa87fa2116B855213;
        gcIdToVoter[29] = 0x9e716Bb240a8eD4b72FEDE6e02bD833F5576CcCb;
        gcIdToVoter[30] = 0x36a4323EAa247371c69FFD16DAe7076DB7fe1bD8;
        gcIdToVoter[31] = 0xe4b331A187A6f1ae7a51c59F10f84d5Dc2FbBc3e;
        gcIdToVoter[32] = 0x83d5C926D644900b10cB95F95DE3653dd774C3f5;
        gcIdToVoter[33] = 0x8e42760A9dcD8814c3C5D93FB5C43BDbFb3e219F;
        gcIdToVoter[34] = 0x0227e631636226F58aE41E66386B3CB123C7028D;
        gcIdToVoter[35] = 0x5dDd5C947BC56E1EE94F409b18776cDadF370F64;
        gcIdToVoter[38] = 0x0CdfF4ef792D8A23162A8aaF6ec2DB8B5AA3eA1D;
        gcIdToVoter[39] = 0x6230CF1C09B75B8FC8545862D3D77033C1e68aC4;
        gcIdToVoter[40] = 0x82602d425FA00137Dd2E0e61afB310a59b62F0DB;
        gcIdToVoter[41] = 0x064f17325250CC5f86fe5d0D95cbDF6F86c93E69;
        gcIdToVoter[44] = 0x81d5548443ae8cb367403D90c5589324B089331d;
        gcIdToVoter[45] = 0xa1d36A12633A3734cc47eC559f6C8d95c577F271;
        gcIdToVoter[46] = 0x9B2FdF1E122A0c4cF6283Bd4F6a4FF149A67d82f;
        gcIdToVoter[47] = 0x36c36b807da7e409bf73FC1248Aeb172A6E4Daa7;
        gcIdToVoter[49] = 0x99216B33b44D4028452f46b5b88d98E8045715B5;
        gcIdToVoter[51] = 0x4E2163fC741c694d225eD9D54317F7C52288A88a;
        gcIdToVoter[52] = 0x455B9635325AEEBBcc5EE97A07Fb57e2B876d716;
        gcIdToVoter[55] = 0x71B3522348309bC5b5722cf211a6EDC3Ec8F1F97;
        gcIdToVoter[56] = 0xb9a123CE2D55563047d88bEa7c5FbC13a501af98;
        gcIdToVoter[58] = 0x69bb34e597F3f6dC7FE7657d3f293F342Ee7faFB;
        gcIdToVoter[61] = 0xFa110469D00b43c4cF2c81788A6B3129ff33AF18;
        gcIdToVoter[67] = 0x7219Dfcc5ccB5b336503467068B27b51Faf72B7D;
        gcIdToVoter[76] = 0x8AbB6fCDB26ffa76d1d9fFe1418dFB604C604d25;

        voterToGCId[0x2F8696aB2B65F699185D77380ee344701a10756c] = 23;
        voterToGCId[0x78B55BCA9d52D328B8b95cbDfae697639c75F1eE] = 24;
        voterToGCId[0xAd1eB9e472234A862b5632E0262343f5E2159905] = 25;
        voterToGCId[0xDfD9B804ebC47d8b75908297142e19eF7B0bc123] = 26;
        voterToGCId[0xDDE26721b0F972b73bb3a8936882c31D54E4beE0] = 27;
        voterToGCId[0xD8de51A515Dd8c8EECa97bDAa87fa2116B855213] = 28;
        voterToGCId[0x9e716Bb240a8eD4b72FEDE6e02bD833F5576CcCb] = 29;
        voterToGCId[0x36a4323EAa247371c69FFD16DAe7076DB7fe1bD8] = 30;
        voterToGCId[0xe4b331A187A6f1ae7a51c59F10f84d5Dc2FbBc3e] = 31;
        voterToGCId[0x83d5C926D644900b10cB95F95DE3653dd774C3f5] = 32;
        voterToGCId[0x8e42760A9dcD8814c3C5D93FB5C43BDbFb3e219F] = 33;
        voterToGCId[0x0227e631636226F58aE41E66386B3CB123C7028D] = 34;
        voterToGCId[0x5dDd5C947BC56E1EE94F409b18776cDadF370F64] = 35;
        voterToGCId[0x0CdfF4ef792D8A23162A8aaF6ec2DB8B5AA3eA1D] = 38;
        voterToGCId[0x6230CF1C09B75B8FC8545862D3D77033C1e68aC4] = 39;
        voterToGCId[0x82602d425FA00137Dd2E0e61afB310a59b62F0DB] = 40;
        voterToGCId[0x064f17325250CC5f86fe5d0D95cbDF6F86c93E69] = 41;
        voterToGCId[0x81d5548443ae8cb367403D90c5589324B089331d] = 44;
        voterToGCId[0xa1d36A12633A3734cc47eC559f6C8d95c577F271] = 45;
        voterToGCId[0x9B2FdF1E122A0c4cF6283Bd4F6a4FF149A67d82f] = 46;
        voterToGCId[0x36c36b807da7e409bf73FC1248Aeb172A6E4Daa7] = 47;
        voterToGCId[0x99216B33b44D4028452f46b5b88d98E8045715B5] = 49;
        voterToGCId[0x4E2163fC741c694d225eD9D54317F7C52288A88a] = 51;
        voterToGCId[0x455B9635325AEEBBcc5EE97A07Fb57e2B876d716] = 52;
        voterToGCId[0x71B3522348309bC5b5722cf211a6EDC3Ec8F1F97] = 55;
        voterToGCId[0xb9a123CE2D55563047d88bEa7c5FbC13a501af98] = 56;
        voterToGCId[0x69bb34e597F3f6dC7FE7657d3f293F342Ee7faFB] = 58;
        voterToGCId[0xFa110469D00b43c4cF2c81788A6B3129ff33AF18] = 61;
        voterToGCId[0x7219Dfcc5ccB5b336503467068B27b51Faf72B7D] = 67;
        voterToGCId[0x8AbB6fCDB26ffa76d1d9fFe1418dFB604C604d25] = 76;

        calcAllVotes(trackerId);
        return trackerId;
    }
}
