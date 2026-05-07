// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakingTrackerV3} from "../src/StakingTrackerV3/StakingTrackerV3.sol";

/// @title DeploySTv3
/// @notice Deploys StakingTrackerV3 implementation + ERC1967 (UUPS) proxy.
///         The proxy is initialized with the given owner (typically the Voting contract).
///
/// DEPLOYMENT ORDER (important):
///   1. Deploy STv3 proxy (this script)
///   2. Register STv3 in Registry as "StakingTracker"
///   3. THEN upgrade AddressBookV2
///
///   ABv2's _refreshVoter now calls refreshVoter(nodeId) instead of refreshVoter(staking).
///   If ABv2 is upgraded before STv3 is registered, the old STv2 in Registry would receive
///   a nodeId argument it does not expect, causing refreshVoter to revert.
///
/// Environment variables:
///   DEPLOYER_PRIVATE_KEY - Private key of the deployer (required)
///   STV3_OWNER           - Address that owns the STv3 proxy (calls createTracker). Typically the Voting contract.
///
/// Usage:
///   # Dry-run:
///   DEPLOYER_PRIVATE_KEY=0x... STV3_OWNER=0x... forge script script/DeploySTv3.s.sol -v
///
///   # Broadcast:
///   DEPLOYER_PRIVATE_KEY=0x... STV3_OWNER=0x... forge script script/DeploySTv3.s.sol \
///     --rpc-url $RPC_URL --broadcast --verify
contract DeploySTv3 is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address stv3Owner = vm.envAddress("STV3_OWNER");

        console.log("Deployer:", vm.addr(deployerKey));
        console.log("STv3 owner:", stv3Owner);

        vm.startBroadcast(deployerKey);

        // 1. Deploy implementation (initializers disabled in constructor)
        StakingTrackerV3 impl = new StakingTrackerV3();

        // 2. Deploy UUPS proxy and initialize
        bytes memory initCall = abi.encodeCall(StakingTrackerV3.initialize, (stv3Owner));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initCall);

        vm.stopBroadcast();

        // 3. Verify
        StakingTrackerV3 stv3 = StakingTrackerV3(address(proxy));
        require(stv3.owner() == stv3Owner, "Owner mismatch");
        require(stv3.VERSION() == 3, "Version mismatch");

        console.log("=== Deployment Results ===");
        console.log("StakingTrackerV3 implementation:", address(impl));
        console.log("StakingTrackerV3 proxy:", address(proxy));
        console.log("Owner:", stv3Owner);
    }
}
