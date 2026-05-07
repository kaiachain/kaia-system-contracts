// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {AddressBookV2} from "../src/AddressBookV2/AddressBookV2.sol";

/// @title DeployABv2Impl
/// @notice Deploys a bare AddressBookV2 implementation (initializers disabled).
///         Initialization is done separately via proxy.
/// @dev Usage:
///   # Dry-run (simulation):
///   DEPLOYER_PRIVATE_KEY=0x... forge script script/DeployABv2Impl.s.sol -v
///
///   # Broadcast (live):
///   DEPLOYER_PRIVATE_KEY=0x... EPOCH_BLOCK_INTERVAL=86400 forge script script/DeployABv2Impl.s.sol \
///     --rpc-url $RPC_URL --broadcast
///
///   Environment variables:
///     DEPLOYER_PRIVATE_KEY    - Private key of the deployer (required)
///     EPOCH_BLOCK_INTERVAL    - Blocks per epoch (default: 86400)
contract DeployABv2Impl is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 epochBlockInterval = vm.envOr("EPOCH_BLOCK_INTERVAL", uint256(86_400));
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("epochBlockInterval:", epochBlockInterval);

        vm.startBroadcast(deployerKey);
        AddressBookV2 impl = new AddressBookV2(epochBlockInterval);
        vm.stopBroadcast();

        console.log("AddressBookV2 implementation deployed at:", address(impl));
    }
}
