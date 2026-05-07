// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {CnStakingDelegator} from "../src/Delegator/CnStakingDelegator.sol";
import {PublicDelegationDelegator} from "../src/Delegator/PublicDelegationDelegator.sol";

/// @title DeployCnStakingDelegator
/// @notice Deploys CnStakingDelegator for an already-deployed CnStakingV4 (without PD).
///
/// Prerequisites:
///   - CnStakingV4 must already be deployed without PublicDelegation.
///   - After deployment, the CnStakingV4 owner must transfer ownership to the deployed
///     CnStakingDelegator contract (required for unstaking access: onlyUnstakingManager = owner).
///
/// Environment variables:
///   CN_STAKING  - Address of the deployed CnStakingV4 proxy.
///   DELEGATOR   - Address that provides delegation (DELEGATOR_ROLE).
///   DELEGATEE   - Address that withdraws validator's portion (DELEGATEE_ROLE).
///
/// Usage:
///   CN_STAKING=0x... DELEGATOR=0x... DELEGATEE=0x... \
///     forge script script/DeployDelegator.s.sol:DeployCnStakingDelegator --rpc-url $RPC_URL --broadcast
contract DeployCnStakingDelegator is Script {
    function run() external {
        address cnStaking = vm.envAddress("CN_STAKING");
        address delegator = vm.envAddress("DELEGATOR");
        address delegatee = vm.envAddress("DELEGATEE");

        vm.startBroadcast();

        CnStakingDelegator d = new CnStakingDelegator(delegator, delegatee, cnStaking);

        vm.stopBroadcast();

        console.log("=== CnStakingDelegator Deployed ===");
        console.log("CnStaking:", cnStaking);
        console.log("CnStakingDelegator:", address(d));
        console.log("Delegator (DELEGATOR_ROLE):", delegator);
        console.log("Delegatee (DELEGATEE_ROLE):", delegatee);
        console.log("");
        console.log("ACTION REQUIRED: Transfer CnStakingV4 ownership to the CnStakingDelegator contract.");
        console.log("  CnStakingV4(CN_STAKING).transferOwnership(", address(d), ")");
    }
}

/// @title DeployPublicDelegationDelegator
/// @notice Deploys PublicDelegationDelegator for an already-deployed PublicDelegation.
///
/// Prerequisites:
///   - CnStakingV4 with PublicDelegation must already be deployed.
///
/// Environment variables:
///   PUBLIC_DELEGATION  - Address of the deployed PublicDelegation proxy.
///   DELEGATOR          - Address that provides delegation (DELEGATOR_ROLE).
///   DELEGATEE          - Address that withdraws reward (DELEGATEE_ROLE).
///
/// Usage:
///   PUBLIC_DELEGATION=0x... DELEGATOR=0x... DELEGATEE=0x... \
///     forge script script/DeployDelegator.s.sol:DeployPublicDelegationDelegator --rpc-url $RPC_URL --broadcast
contract DeployPublicDelegationDelegator is Script {
    function run() external {
        address publicDelegation = vm.envAddress("PUBLIC_DELEGATION");
        address delegator = vm.envAddress("DELEGATOR");
        address delegatee = vm.envAddress("DELEGATEE");

        vm.startBroadcast();

        PublicDelegationDelegator d = new PublicDelegationDelegator(delegator, delegatee, publicDelegation);

        vm.stopBroadcast();

        console.log("=== PublicDelegationDelegator Deployed ===");
        console.log("PublicDelegation:", publicDelegation);
        console.log("CnStaking (resolved from PD):", address(d.CN()));
        console.log("PublicDelegationDelegator:", address(d));
        console.log("Delegator (DELEGATOR_ROLE):", delegator);
        console.log("Delegatee (DELEGATEE_ROLE):", delegatee);
    }
}
