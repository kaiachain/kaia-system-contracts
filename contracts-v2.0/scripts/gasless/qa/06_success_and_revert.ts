import hre, { ethers } from "hardhat";
import { formatEther, parseEther } from "ethers";
import { getContractFromDeployment, getFromEnvOrGenerate } from "../../../helpers/utils";
import { getApproveRawTx, getSwapRawTx, waitForReceipt, verifyBalance, verifyLogs } from "./utils";

/**
 * Test for reverting swap due to insufficient token balance
 * This tests transaction batching with kaia_sendRawTransactions where some transactions fail
 */
async function main() {
  console.log("\n1. Setting up test environment...");
  if (!process.env.TESTER) {
    throw new Error("TESTER environment variables must be set");
  }

  // Get contracts
  const testToken = await getContractFromDeployment(hre, "TestToken");
  const wkaia = await getContractFromDeployment(hre, "WKAIA");
  const uniRouter = await getContractFromDeployment(hre, "UniswapV2Router02");
  const gsr = await getContractFromDeployment(hre, "GaslessSwapRouter");
  const contracts = { testToken, wkaia, uniRouter, gsr };

  // Setup test wallets
  console.log("\n2. Preparing test wallets...");
  const tester1 = new hre.ethers.Wallet(process.env.TESTER, hre.ethers.provider);
  const tester2 = getFromEnvOrGenerate(hre, "TESTER2");
  const failingEOA = getFromEnvOrGenerate(hre, "FAILING"); // Create a new EOA for the failing transaction (with zero tokens)

  console.log(`Tester1 address: ${tester1.address}`);
  console.log(`Tester2 address: ${tester2.address}`);
  console.log(`Failing EOA address: ${failingEOA.address}`);

  // Transfer test tokens to tester1 and tester2 accounts only (not to failingEOA)
  console.log("\n3. Transferring test tokens to test accounts...");
  const transferAmount = parseEther("2");

  // Check if accounts already have tokens, transfer if needed
  let tx;
  const tester1Balance = await testToken.balanceOf(tester1.address);
  if (tester1Balance == 0n) {
    tx = await testToken.transfer(tester1.address, transferAmount);
    await tx.wait();
    console.log(`Transferred ${formatEther(transferAmount)} test tokens to Tester1`);
  } else {
    console.log(`Tester1 already has ${formatEther(tester1Balance)} test tokens`);
  }

  const tester2Balance = await testToken.balanceOf(tester2.address);
  if (tester2Balance == 0n) {
    tx = await testToken.transfer(tester2.address, transferAmount);
    await tx.wait();
    console.log(`Transferred ${formatEther(transferAmount)} test tokens to Tester2`);
  } else {
    console.log(`Tester2 already has ${formatEther(tester2Balance)} test tokens`);
  }

  // Check token balance of failingEOA (should be zero)
  const failingEOABalance = await testToken.balanceOf(failingEOA.address);
  console.log(`Failing EOA's test token balance: ${formatEther(failingEOABalance)} test tokens`);

  // Generate approve and swap transactions for all 3 testers
  console.log("\n4. Generating approve and swap transactions for all testers...");

  // Tester1
  console.log("Generating transactions for Tester1...");
  const tester1ApproveTx = await getApproveRawTx(tester1, contracts);
  const tester1SwapTx = await getSwapRawTx(tester1, contracts, false);

  // FailingEOA (will fail due to insufficient token balance)
  console.log("Generating transactions for Failing EOA...");
  const failingEOAApproveTx = await getApproveRawTx(failingEOA, contracts);
  const failingEOASwapTx = await getSwapRawTx(failingEOA, contracts, false);

  // Tester2
  console.log("Generating transactions for Tester2...");
  const tester2ApproveTx = await getApproveRawTx(tester2, contracts);
  const tester2SwapTx = await getSwapRawTx(tester2, contracts, false);

  // Send all transactions at once using kaia_sendRawTransactions
  console.log("\n5. Sending all transactions using kaia_sendRawTransactions...");

  // Combine all transactions in the required order
  const allRawTxs = [
    tester1ApproveTx, // tx1
    tester1SwapTx, // tx2
    failingEOAApproveTx, // tx3
    failingEOASwapTx, // tx4
    tester2ApproveTx, // tx5
    tester2SwapTx, // tx6
  ];

  const chainId = (await ethers.provider.getNetwork()).chainId;
  let txs = [];

  if (chainId == 31337n) {
    console.log("It's a hardhat network, so use eth_sendRawTransaction");
    // hardhat network - send transactions one by one
    for (const rawTx of allRawTxs) {
      try {
        const tx = await hre.network.provider.send("eth_sendRawTransaction", [rawTx]);
        txs.push(tx);
      } catch (error: any) {
        console.error(`Error sending transaction: ${error.message}`);
        txs.push(null);
      }
    }
  } else {
    // Production network - send all transactions at once
    try {
      txs = await hre.network.provider.send("kaia_sendRawTransactions", [allRawTxs]);
    } catch (error: any) {
      console.error(`Error with kaia_sendRawTransactions: ${error.message}`);
    }
  }

  // Wait for all transactions to be mined
  console.log("\n6. Waiting for all transactions to complete and verifying results...");

  // Wait for Tester1's swap to complete
  if (txs[1]) {
    console.log("\nVerifying Tester1's transactions:");
    const tester1Receipt = await waitForReceipt(txs[1]);
    if (!tester1Receipt) {
      console.log("❌ No receipt found for Tester1's swap transaction.");
      return;
    }

    const gaslessBlockNum1 = tester1Receipt.blockNumber;
    console.log(`Tester1's transaction included in block: ${gaslessBlockNum1}`);

    if (tester1Receipt.status) {
      console.log("✅ Tester1's swap transaction was successful");
      await verifyBalance(tester1, contracts, gaslessBlockNum1);
      await verifyLogs(tester1, contracts, [txs[0], txs[1]], gaslessBlockNum1);
    } else {
      console.log("❌ Tester1's swap transaction failed");
    }
  }

  // Verify Failing EOA transactions failed as expected due to insufficient tokens
  if (txs[3]) {
    console.log("\nVerifying Failing EOA transactions:");
    try {
      const failingEOAReceipt = await waitForReceipt(txs[3]);
      if (!failingEOAReceipt) {
        console.log("✅ No receipt found for Failing EOA's swap - failed as expected");
      } else if (failingEOAReceipt.status) {
        console.log("❌ Failing EOA swap transaction succeeded unexpectedly");
      }
    } catch (error) {
      console.log("✅ Failing EOA swap transaction failed as expected with error");
      console.error(error);
    }
  } else {
    console.log("✅ Failing EOA transactions were not accepted by the network as expected");
  }

  // Wait for Tester2's swap to complete
  if (txs[5]) {
    console.log("\nVerifying Tester2's transactions:");
    const tester2Receipt = await waitForReceipt(txs[5]);
    if (!tester2Receipt) {
      console.log("❌ No receipt found for Tester2's swap transaction.");
      return;
    }

    const gaslessBlockNum2 = tester2Receipt.blockNumber;
    console.log(`Tester2's transaction included in block: ${gaslessBlockNum2}`);

    if (tester2Receipt.status) {
      console.log("✅ Tester2's swap transaction was successful");
      await verifyBalance(tester2, contracts, gaslessBlockNum2);
      await verifyLogs(tester2, contracts, [txs[4], txs[5]], gaslessBlockNum2);
    } else {
      console.log("❌ Tester2's swap transaction failed");
    }
  }

  console.log("\n7. Test complete!");
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
