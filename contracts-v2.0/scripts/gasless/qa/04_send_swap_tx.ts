import hre, { ethers } from "hardhat";
import { getContractFromDeployment } from "../../../helpers/utils";
import { formatEther, Wallet } from "ethers";
import {
  verifyLogs,
  verifyBalance,
  gasPriceBN,
  swapGas,
  swapAmount,
  waitForReceipt,
  amountRepaySwapOnly,
} from "./utils";

function calculateSwapOnlyAmountRepay() {
  // V1 = LendTx.Fee() = SwapTx.GasPrice() * 21000
  const V1 = gasPriceBN * 21000n;
  // V3 = SwapTx.Fee() = SwapTx.GasPrice() * SwapTx.GasLimit
  const V3 = gasPriceBN * swapGas;
  return V1 + V3;
}

async function getSwapOnlyRawTx(tester: Wallet, contracts: any) {
  const nonce = await tester.getNonce();
  console.log(`Current nonce for tester: ${nonce}`);

  const chainId = (await ethers.provider.getNetwork()).chainId;
  const amountsOut = await contracts.uniRouter.getAmountsOut(swapAmount, [
    await contracts.testToken.getAddress(),
    await contracts.wkaia.getAddress(),
  ]);
  const swapExpectedOutput = amountsOut[1];

  // Calculate required amounts
  const margin = (swapExpectedOutput * 1n) / 100n; // 1% margin
  const minAmountOut = amountRepaySwapOnly + margin;

  console.log("\nSwap parameters for Swap-only transaction:");
  console.log(`Amount to swap: ${formatEther(swapAmount)} TT`);
  console.log(`Expected output: ${formatEther(swapExpectedOutput)} KAIA`);
  console.log(`Minimum amount out: ${formatEther(minAmountOut)} KAIA`);
  console.log(`Gas repayment amount (V1+V3): ${formatEther(amountRepaySwapOnly)} KAIA`);
  console.log(`V1 (LendTx.Fee): ${formatEther(gasPriceBN * 21000n)} KAIA`);
  console.log(`V3 (SwapTx.Fee): ${formatEther(gasPriceBN * swapGas)} KAIA`);
  const currentBlock = await hre.ethers.provider.getBlock("latest");
  if (!currentBlock) {
    throw new Error("Current block not found");
  }
  const deadline = currentBlock.timestamp + 300;

  // Create and sign the swap transaction
  const swapData = contracts.gsr.interface.encodeFunctionData("swapForGas", [
    await contracts.testToken.getAddress(),
    swapAmount,
    minAmountOut,
    amountRepaySwapOnly,
    deadline,
  ]);

  const swapTx = {
    type: 0,
    to: await contracts.gsr.getAddress(),
    nonce: nonce,
    gasLimit: swapGas,
    gasPrice: gasPriceBN,
    data: swapData,
    chainId: chainId,
  };

  // Sign the transaction
  const swapRawTx = await tester.signTransaction(swapTx);
  console.log(`Generated signed swap raw transaction: ${swapRawTx}`);
  return swapRawTx;
}

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

  // Check token allowance to ensure approve transaction was successful
  const allowance = await testToken.allowance(tester.address, await gsr.getAddress());
  console.log(`Current allowance from tester to GSR: ${formatEther(allowance)} TT`);
  if (allowance < swapAmount) {
    throw new Error(
      `Insufficient allowance. Please run 03_send_approve_swap_tx.ts first to approve tokens for GSR contract.`,
    );
  }

  // Check token balance
  const kaiaBalanceBefore = await ethers.provider.getBalance(tester.address);
  const tokenBalanceBefore = await testToken.balanceOf(tester.address);

  console.log("\n2. Generating swap transaction...");
  // Generate swap transaction with updated amountRepay calculation for Swap-only case
  const swapRawTx = await getSwapOnlyRawTx(tester, contracts);

  console.log("\n3. Sending transactions using kaia_sendRawTransactions...");
  const chainId = (await ethers.provider.getNetwork()).chainId;
  let txs = [];
  if (chainId == 31337n) {
    console.log("It's a hardhat network, so using eth_sendRawTransaction");
    // Hardhat network - send transaction directly
    const tx = await hre.network.provider.send("eth_sendRawTransaction", [swapRawTx]);
    txs.push(tx);
  } else {
    // Use kaia_sendRawTransactions for single transaction
    txs = await hre.network.provider.send("kaia_sendRawTransactions", [[swapRawTx]]);
  }

  const receipt = await waitForReceipt(txs[0]);
  if (!receipt) {
    console.log("❌ No receipt found for swap transaction.");
    return;
  }

  const gaslessBlockNum = receipt.blockNumber;

  console.log("\n4. Verifying transaction results:");
  await verifyBalance(tester, contracts, gaslessBlockNum);
  await verifyLogs(tester, contracts, [null, txs[0]], gaslessBlockNum, calculateSwapOnlyAmountRepay());

  console.log("\n5. Comparing expected and actual amountRepay:");
  const expectedAmountRepay = calculateSwapOnlyAmountRepay();
  console.log(`Expected amountRepay for Swap-only (V1+V3): ${formatEther(expectedAmountRepay)} KAIA`);

  const block = await ethers.provider.getBlock(gaslessBlockNum);
  const kaiaBalanceAfter = await ethers.provider.getBalance(tester.address);
  const tokenBalanceAfter = await testToken.balanceOf(tester.address);

  console.log("\n6. Test summary:");
  console.log(`✅ Transaction successfully mined in block ${gaslessBlockNum}`);
  console.log(`  * Swap Transaction Hash: ${txs[0]}`);
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
