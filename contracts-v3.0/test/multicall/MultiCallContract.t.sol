// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Base} from "../base/Base.t.sol";
import {MultiCallContract} from "../../src/Multicall/MultiCallContract.sol";
import {Profile, State} from "../../src/types/Node.sol";
import {MockCnStaking} from "../../src/CnStaking/mocks/MockCnStaking.sol";

contract MultiCallContractTest is Base {
    MultiCallContract internal multiCall;

    function setUp() public override {
        super.setUp();
        multiCall = new MultiCallContract();
    }

    /* ========== multiCallStakingInfoPermissionless ========== */

    function test_multiCallStakingInfoKIP290() public {
        _setupGenesisCommittee();

        // Set staking amounts for genesis nodes
        genesis[0].staking.mockSetStaking(5_000_000 ether);
        genesis[0].staking.mockSetUnstaking(500_000 ether);
        genesis[1].staking.mockSetStaking(10_000_000 ether);
        genesis[1].staking.mockSetUnstaking(1_000_000 ether);
        genesis[2].staking.mockSetStaking(15_000_000 ether);
        genesis[2].staking.mockSetUnstaking(1_500_000 ether);
        genesis[3].staking.mockSetStaking(20_000_000 ether);
        genesis[3].staking.mockSetUnstaking(2_000_000 ether);

        (
            Profile[] memory profiles,
            uint256[] memory stakingAmounts,
            address kefAddr,
            address kifAddr,
            address kpfAddr
        ) = multiCall.multiCallStakingInfoPermissionless();

        assertEq(profiles.length, 4);
        assertEq(stakingAmounts.length, 4);

        assertEq(stakingAmounts[0], 4_500_000 ether);
        assertEq(stakingAmounts[1], 9_000_000 ether);
        assertEq(stakingAmounts[2], 13_500_000 ether);
        assertEq(stakingAmounts[3], 18_000_000 ether);

        assertEq(kefAddr, DEFAULT_KEF_ADDRESS);
        assertEq(kifAddr, DEFAULT_KIF_ADDRESS);
        assertEq(kpfAddr, DEFAULT_KPF_ADDRESS);
    }

    /* ========== multiCallNodeStatesPermissionless ========== */

    function test_multiCallNodeStatesPermissionless_returnsAllFields() public {
        _setupGenesisCommittee();

        // Create 6 additional nodes (indices 5-10) and transition to ValActive
        NodeBundle[] memory extra = new NodeBundle[](6);
        for (uint256 i = 0; i < 6; i++) {
            extra[i] = _createNode(i + 5);
        }

        address[] memory changedIds = new address[](6);
        State[] memory changedStates = new State[](6);
        uint256[] memory timeoutAts = new uint256[](6);
        for (uint256 i = 0; i < 6; i++) {
            changedIds[i] = extra[i].nodeId;
            changedStates[i] = State.ValActive;
        }
        _doSystemTransition(changedIds, changedStates, timeoutAts);

        // Set staking amounts: node[i] staking = (i+1) * 5M, unstaking = 0
        for (uint256 i = 0; i < 4; i++) {
            genesis[i].staking.mockSetStaking((i + 1) * 5_000_000 ether);
        }
        for (uint256 i = 0; i < 6; i++) {
            extra[i].staking.mockSetStaking((i + 5) * 5_000_000 ether);
        }

        MultiCallContract.NodeStatesResult memory result = multiCall.multiCallNodeStatesPermissionless();

        assertEq(result.profiles.length, 10);
        assertEq(result.stakingAmounts.length, 10);
        for (uint256 i = 0; i < 10; i++) {
            assertEq(result.stakingAmounts[i], (i + 1) * 5_000_000 ether);
        }

        assertEq(result.pauseTimeout, DEFAULT_PAUSE_TIMEOUT);
        assertEq(result.idleTimeout, DEFAULT_IDLE_TIMEOUT);
        assertEq(result.pfsThreshold, DEFAULT_PFS_THRESHOLD);
        assertEq(result.cfsThreshold, 300);

        // epochVACount = 10 (10 active validators)
        assertEq(result.epochVACount, 10);
        // maxSlotAvailable(10) = (10/3+1)/2 = 2, minActiveCount(10) = (20+2)/3 = 7
        assertEq(result.maxSlotAvailable, 2);
        assertEq(result.minActiveCount, 7);
    }
}
