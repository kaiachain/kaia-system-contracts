// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CnStakingV4} from "../src/CnStaking/CnStakingV4/CnStakingV4.sol";
import {PublicDelegation} from "../src/PublicDelegation/PublicDelegation.sol";
import {CnStakingV4Factory} from "../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";

/// @title DeployBeaconsAndFactory
/// @notice Deploys CnStakingV4 and PublicDelegation implementations, their UpgradeableBeacons,
///         and the CnStakingV4Factory that uses them.
///
/// Environment variables:
///   BEACON_OWNER  - Address that can upgrade beacon implementations.
///                   Must be the Voting contract: beacon upgrades affect ALL deployed
///                   CnStaking and PublicDelegation proxies at once, so this is a
///                   chain-level governance action that must go through on-chain voting.
///
/// Usage:
///   BEACON_OWNER=0x... forge script script/DeployBeaconsAndFactory.s.sol \
///     --rpc-url $RPC_URL --broadcast --verify
contract DeployBeaconsAndFactory is Script {
    function run() external {
        address beaconOwner = vm.envAddress("BEACON_OWNER");

        vm.startBroadcast();

        // 1. Deploy implementations (bare, initializers disabled)
        CnStakingV4 cnImpl = new CnStakingV4();
        PublicDelegation pdImpl = new PublicDelegation();

        // 2. Deploy beacons pointing to implementations
        UpgradeableBeacon cnBeacon = new UpgradeableBeacon(address(cnImpl), beaconOwner);
        UpgradeableBeacon pdBeacon = new UpgradeableBeacon(address(pdImpl), beaconOwner);

        // 3. Deploy factory
        CnStakingV4Factory factory = new CnStakingV4Factory(address(cnBeacon), address(pdBeacon));

        vm.stopBroadcast();

        console.log("=== Deployment Results ===");
        console.log("CnStakingV4 implementation:", address(cnImpl));
        console.log("PublicDelegation implementation:", address(pdImpl));
        console.log("CnStaking beacon:", address(cnBeacon));
        console.log("PublicDelegation beacon:", address(pdBeacon));
        console.log("CnStakingV4Factory:", address(factory));
        console.log("Beacon owner:", beaconOwner);
    }
}
