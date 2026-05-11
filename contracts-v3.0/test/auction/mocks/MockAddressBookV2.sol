// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {NodeInfo, BlsPublicKeyInfo, State} from "../../../src/types/Node.sol";

/// @notice Minimal stand-in for AddressBookV2 — only `getNodeInfo` is implemented since that's
///         the sole entry point AuctionFeeVault exercises.
contract MockAddressBookV2 {
    mapping(address => address) public managers;

    function setManager(address nodeId, address manager) external {
        managers[nodeId] = manager;
    }

    function getNodeInfo(address nodeId) external view returns (NodeInfo memory info) {
        info.manager = managers[nodeId];
        // Other fields stay at default zero/empty values; FeeVault does not read them.
    }
}
