// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AddressBookV2} from "../../src/AddressBookV2/AddressBookV2.sol";
import {State, NodeInfo} from "../../src/types/Node.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @notice Test harness exposing AddressBookV2Base internal functions for defense-in-depth testing.
contract AddressBookV2Harness is AddressBookV2 {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(uint256 _epochBlockInterval) AddressBookV2(_epochBlockInterval) {}

    function exposed_createNode(address nodeId, NodeInfo memory info) external {
        ABv2Storage storage $ = _getStorage();
        $.nodeInfo[nodeId] = info;
        $.registeredNodes.add(nodeId);
        $.stateCount[State.Registered]++;
        emit NodeCreated(nodeId);
    }

    function exposed_deleteNode(address nodeId) external {
        ABv2Storage storage $ = _getStorage();
        if ($.nodeInfo[nodeId].state != State.Registered) revert InvalidState();
        $.stateCount[State.Registered]--;
        $.registeredNodes.remove(nodeId);
        delete $.nodeInfo[nodeId];
        emit NodeDeleted(nodeId);
    }

    function exposed_batchTransition(
        address[] calldata nodeIds,
        State[] calldata newStates,
        uint256[] calldata timeouts
    ) external {
        uint256 len = nodeIds.length;
        for (uint256 i; i < len; ++i) {
            _transition(nodeIds[i], newStates[i], timeouts[i]);
        }
    }
}
