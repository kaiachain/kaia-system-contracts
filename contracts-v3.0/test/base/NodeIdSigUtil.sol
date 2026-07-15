// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";

/// @title NodeIdSigUtil
/// @notice Single source for the nodeId ownership signature that AddressBookV2.createNode /
///         NodeVerifier.registerNode require. The digest matches NodeVerifier._verifyNodeIdProof:
///         keccak256(caller, nodeId, stakingContract, chainId, target), where `target` is the contract
///         that runs the check (the AddressBookV2 proxy in end-to-end tests, or the library harness in
///         NodeVerifier unit tests).
library NodeIdSigUtil {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function sign(uint256 nodeIdPk, address caller, address nodeId, address staking, address target)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = keccak256(abi.encode(caller, nodeId, staking, block.chainid, target));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(nodeIdPk, digest);
        return abi.encodePacked(r, s, v);
    }
}
