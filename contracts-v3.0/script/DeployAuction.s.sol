// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {AuctionEntryPoint} from "../src/Auction/AuctionEntryPoint.sol";
import {AuctionFeeVault} from "../src/Auction/AuctionFeeVault.sol";
import {IAuctionDepositVault} from "../src/Auction/interfaces/IAuctionDepositVault.sol";

/// @title DeployAuction
/// @notice Deploys the v3.0 auction stack: AuctionFeeVault + AuctionEntryPoint.
///         AuctionDepositVault is NOT redeployed — the v2.1 deployment is reused. v3.0
///         contracts integrate with it through the verbatim IAuctionDepositVault ABI.
///
/// Required env vars:
///   DEPLOYER_PRIVATE_KEY    Private key broadcasting the txs.
///   AUCTION_OWNER           Owner of both new contracts (EOA or multisig).
///   AUCTION_DEPOSIT_VAULT   Address of the existing (v2.1) AuctionDepositVault.
///   AUCTIONEER              Address that countersigns searcher bids.
///   SEARCHER_PAYBACK_RATE   Share of bid refunded to the searcher, in bps out of 10000.
///   VALIDATOR_PAYBACK_RATE  Share of bid paid to the block validator, in bps out of 10000.
///                           (SEARCHER_PAYBACK_RATE + VALIDATOR_PAYBACK_RATE must be ≤ 10000.)
///
/// Usage:
///   # Dry-run
///   DEPLOYER_PRIVATE_KEY=0x... AUCTION_OWNER=0x... AUCTION_DEPOSIT_VAULT=0x... \
///   AUCTIONEER=0x... SEARCHER_PAYBACK_RATE=2000 VALIDATOR_PAYBACK_RATE=5000 \
///     forge script script/DeployAuction.s.sol -v
///
///   # Broadcast
///   DEPLOYER_PRIVATE_KEY=0x... AUCTION_OWNER=0x... AUCTION_DEPOSIT_VAULT=0x... \
///   AUCTIONEER=0x... SEARCHER_PAYBACK_RATE=2000 VALIDATOR_PAYBACK_RATE=5000 \
///     forge script script/DeployAuction.s.sol --rpc-url $RPC_URL --broadcast --verify
///
/// POST-DEPLOY GOVERNANCE ACTIONS (printed at end of run; not executed by this script):
///   1. Registry (0x...0401): set getActiveAddr("AuctionEntryPoint") to the new EntryPoint.
///      Until this lands, the existing DepositVault rejects takeBid/takeGas from the new
///      EntryPoint with OnlyEntryPoint.
///   2. Existing DepositVault owner calls changeAuctionFeeVault(newFeeVault) so bids flow
///      to the v3.0 FeeVault. Until this lands, bids still route to the v2.1 FeeVault.
contract DeployAuction is Script {
    uint256 internal constant MAX_PAYBACK_RATE = 10000;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.envAddress("AUCTION_OWNER");
        address depositVault = vm.envAddress("AUCTION_DEPOSIT_VAULT");
        address auctioneer = vm.envAddress("AUCTIONEER");
        uint256 searcherRate = vm.envUint("SEARCHER_PAYBACK_RATE");
        uint256 validatorRate = vm.envUint("VALIDATOR_PAYBACK_RATE");

        // Pre-flight checks — fail fast on misconfiguration before any tx is broadcast.
        require(owner != address(0), "AUCTION_OWNER is zero");
        require(depositVault != address(0), "AUCTION_DEPOSIT_VAULT is zero");
        require(auctioneer != address(0), "AUCTIONEER is zero");
        require(searcherRate + validatorRate <= MAX_PAYBACK_RATE, "payback rates exceed 100%");
        require(depositVault.code.length > 0, "AUCTION_DEPOSIT_VAULT has no code");

        // Sanity-check the deposit vault answers the ABI we depend on. Reverts if the address
        // does not point at a contract that implements depositBalances(address).
        IAuctionDepositVault(depositVault).depositBalances(address(0));

        console.log("=== DeployAuction ===");
        console.log("Deployer            :", vm.addr(deployerKey));
        console.log("Owner               :", owner);
        console.log("DepositVault (v2.1) :", depositVault);
        console.log("Auctioneer          :", auctioneer);
        console.log("Searcher payback bps:", searcherRate);
        console.log("Validator payback bps:", validatorRate);

        vm.startBroadcast(deployerKey);

        AuctionFeeVault feeVault = new AuctionFeeVault(owner, searcherRate, validatorRate);
        AuctionEntryPoint entryPoint = new AuctionEntryPoint(owner, depositVault, auctioneer);

        vm.stopBroadcast();

        // Post-deploy verification — assert constructor state matches inputs.
        require(feeVault.owner() == owner, "FeeVault owner mismatch");
        require(feeVault.searcherPaybackRate() == searcherRate, "searcherPaybackRate mismatch");
        require(feeVault.validatorPaybackRate() == validatorRate, "validatorPaybackRate mismatch");
        require(entryPoint.owner() == owner, "EntryPoint owner mismatch");
        require(entryPoint.auctioneer() == auctioneer, "auctioneer mismatch");
        require(address(entryPoint.depositVault()) == depositVault, "depositVault mismatch");

        console.log("");
        console.log("=== Deployed ===");
        console.log("AuctionFeeVault   :", address(feeVault));
        console.log("AuctionEntryPoint :", address(entryPoint));

        console.log("");
        console.log("=== Required governance actions (NOT executed) ===");
        console.log("1. Registry(0x...0401).setActiveAddr(\"AuctionEntryPoint\", %s)", address(entryPoint));
        console.log(
            "   Until this lands, the existing DepositVault rejects calls from the v3.0 EntryPoint."
        );
        console.log("2. DepositVault(%s).changeAuctionFeeVault(%s)", depositVault, address(feeVault));
        console.log("   Until this lands, bids still route to the v2.1 FeeVault.");
    }
}
