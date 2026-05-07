// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {CnStakingV4Factory} from "../src/CnStaking/CnStakingV4Factory/CnStakingV4Factory.sol";
import {IPublicDelegation} from "../src/PublicDelegation/interfaces/IPublicDelegation.sol";

/// @title DeployCnStaking
/// @notice Deploys CnStakingV4 (with or without PublicDelegation) via the factory.
///
/// Environment variables (required):
///   FACTORY    - Address of the deployed CnStakingV4Factory.
///   OWNER      - Owner of the CnStaking (and PD if deployed). Can be EOA or multisig.
///
/// Environment variables (optional, enables PD deployment):
///   COMMISSION_TO    - Commission recipient address.
///   COMMISSION_RATE  - Commission rate (0-10000, where 10000 = 100%).
///   GC_NAME          - GC name used as token name/symbol prefix (e.g., "MyGC" → "MyGC-pdKAIA").
///
/// Usage (without PD):
///   FACTORY=0x... OWNER=0x... \
///     forge script script/DeployCnStaking.s.sol --rpc-url $RPC_URL --broadcast
///
/// Usage (with PD):
///   FACTORY=0x... OWNER=0x... \
///     COMMISSION_TO=0x... COMMISSION_RATE=1000 GC_NAME="MyGC" \
///     forge script script/DeployCnStaking.s.sol --rpc-url $RPC_URL --broadcast --value 1000000000
contract DeployCnStaking is Script {
    function run() external {
        CnStakingV4Factory factory = CnStakingV4Factory(vm.envAddress("FACTORY"));
        address owner = vm.envAddress("OWNER");

        // Check if PD-related env vars are set
        bool withPD = _hasPDArgs();

        vm.startBroadcast();

        if (withPD) {
            _deployWithPD(factory, owner);
        } else {
            _deployWithoutPD(factory, owner);
        }

        vm.stopBroadcast();
    }

    function _deployWithoutPD(CnStakingV4Factory factory, address owner) private {
        address proxy = factory.deployCnStaking(owner);

        console.log("=== CnStaking Deployed (without PD) ===");
        console.log("CnStaking proxy:", proxy);
        console.log("Owner:", owner);
    }

    function _deployWithPD(CnStakingV4Factory factory, address owner) private {
        address commissionTo = vm.envAddress("COMMISSION_TO");
        uint256 commissionRate = vm.envUint("COMMISSION_RATE");
        string memory gcName = vm.envString("GC_NAME");

        IPublicDelegation.PDConstructorArgs memory pdArgs = IPublicDelegation.PDConstructorArgs({
            owner: owner,
            commissionTo: commissionTo,
            commissionRate: commissionRate,
            gcName: gcName
        });

        // INITIAL_LOCKUP (1e9 wei) is the minimum value required by the factory to mint dead shares.
        // The broadcaster must have sufficient balance; Foundry deducts from the broadcaster's account.
        uint256 initialLockup = factory.INITIAL_LOCKUP();

        (address cnProxy, address pdProxy) = factory.deployCnStakingWithPD{value: initialLockup}(owner, pdArgs);

        console.log("=== CnStaking Deployed (with PD) ===");
        console.log("CnStaking proxy:", cnProxy);
        console.log("PublicDelegation proxy:", pdProxy);
        console.log("Owner:", owner);
        console.log("Commission to:", commissionTo);
        console.log("Commission rate:", commissionRate);
        console.log("GC name:", gcName);
    }

    /// @dev Returns true if COMMISSION_TO env var is set, indicating PD deployment is desired.
    function _hasPDArgs() private view returns (bool) {
        try vm.envAddress("COMMISSION_TO") {
            return true;
        } catch {
            return false;
        }
    }
}
