// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

/// @title NodeIdSigUtil
/// @notice Builds the nodeId ownership signature for createNode. Digest matches
///         NodeVerifier._verifyNodeIdProof; `target` is the verifying contract.
library NodeIdSigUtil {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Must match NodeVerifier.CREATE_NODE_TAG.
    bytes32 private constant CREATE_NODE_TAG = keccak256("KAIA_ADDRESS_BOOK_V2_CREATE_NODE_V1");

    function sign(uint256 nodeIdPk, address caller, address nodeId, address staking, address target)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = keccak256(abi.encode(CREATE_NODE_TAG, block.chainid, target, caller, nodeId, staking));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(nodeIdPk, digest);
        return abi.encodePacked(r, s, v);
    }
}
