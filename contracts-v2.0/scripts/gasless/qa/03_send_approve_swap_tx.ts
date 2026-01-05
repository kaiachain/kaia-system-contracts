import hre, { ethers } from "hardhat";
import { formatEther, Wallet } from "ethers";
import { getContractFromDeployment } from "../../../helpers/utils";
import { getApproveRawTx, getSwapRawTx, verifyBalance, verifyLogs, waitForReceipt } from "./utils";

async function main() {
  console.log("\n1. Checking if TESTER address exists from previous run...");
  if (!process.env.TESTER) {
    throw new Error(
      "TESTER environment variable is not set. Please run 02_transfer_token.ts or set TESTER to an account with test tokens.",
    );
  }

  const tester = new Wallet(process.env.TESTER, hre.ethers.provider);

  // Get contract instances
  const testToken = await getContractFromDeployment(hre, "TestToken");
  const wkaia = await getContractFromDeployment(hre, "WKAIA");
  const uniRouter = await getContractFromDeployment(hre, "UniswapV2Router02");
  const gsr = await getContractFromDeployment(hre, "GaslessSwapRouter");
  const contracts = { testToken, wkaia, uniRouter, gsr };

  // Check token balance
  const kaiaBalanceBefore = await ethers.provider.getBalance(tester.address);
  const tokenBalanceBefore = await testToken.balanceOf(tester.address);

  console.log("\n2. Generating approve+swap transaction...");
  const approveRawTx = await getApproveRawTx(tester, contracts);
  const swapRawTx = await getSwapRawTx(tester, contracts, false);

  console.log("\n3. Sending transactions using kaia_sendRawTransactions...");
  const chainId = (await ethers.provider.getNetwork()).chainId;
  let txs = [];
  if (chainId == 31337n) {
    console.log("It's a hardhat network, so use eth_sendRawTransaction");
    // Hardhat network - send transaction directly
    let tx = await hre.network.provider.send("eth_sendRawTransaction", [approveRawTx]);
    txs.push(tx);
    tx = await hre.network.provider.send("eth_sendRawTransaction", [swapRawTx]);
    txs.push(tx);
  } else {
    // Use kaia_sendRawTransactions for single transaction
    txs = await hre.network.provider.send("kaia_sendRawTransactions", [[approveRawTx, swapRawTx]]);
  }

  const receipt = await waitForReceipt(txs[1]);
  if (!receipt) {
    console.log("❌ No receipt found for swap transaction.");
    return;
  }

  const gaslessBlockNum = receipt?.blockNumber;

  console.log("\n4. Verifying transaction results:");
  await verifyBalance(tester, contracts, gaslessBlockNum);
  await verifyLogs(tester, contracts, txs, gaslessBlockNum);

  const block = await ethers.provider.getBlock(gaslessBlockNum);
  const kaiaBalanceAfter = await ethers.provider.getBalance(tester.address);
  const tokenBalanceAfter = await testToken.balanceOf(tester.address);

  console.log("\n5. Test summary:");
  console.log(`✅ Transaction successfully mined in block ${gaslessBlockNum}`);
  console.log(`  * Approve Transaction Hash: ${txs[0]}`);
  console.log(`  * Swap Transaction Hash: ${txs[1]}`);
  console.log(`  * Block miner: ${block?.miner}`);
  console.log(`* Tester address: ${tester.address}`);
  console.log(`  * Tester KAIA balance: ${formatEther(kaiaBalanceBefore)} -> ${formatEther(kaiaBalanceAfter)} KAIA`);
  console.log(`  * Tester token balance: ${formatEther(tokenBalanceBefore)} -> ${formatEther(tokenBalanceAfter)} TT`);
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
