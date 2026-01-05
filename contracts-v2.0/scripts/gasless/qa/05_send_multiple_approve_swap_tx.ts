import hre, { ethers } from "hardhat";
import { formatEther, parseEther } from "ethers";
import { getContractFromDeployment, getFromEnvOrGenerate } from "../../../helpers/utils";
import { getApproveRawTx, getSwapRawTx, verifyLogs, verifyBalance, swapAmount, waitForReceipt } from "./utils";

// Number of users to test with
const NUM_USERS = 3;

/**
 * Sets up multiple test users with proper token balances
 * @param contracts Contract objects needed for transactions
 * @returns Array of wallet objects for each test user
 */
async function setupTestUsers(contracts: any) {
  const [deployer] = await ethers.getSigners();
  const testers = [];

  console.log("\nSetting up test users...");
  for (let i = 0; i < NUM_USERS; i++) {
    const tester = getFromEnvOrGenerate(hre, `TESTER${i + 1}`);
    testers.push(tester);

    // Check token balance and send tokens if needed
    const tokenBalance = await contracts.testToken.balanceOf(tester.address);
    if (tokenBalance < swapAmount) {
      console.log(`Sending test tokens to tester${i + 1}...`);
      const transferAmount = parseEther("2");
      const tx = await contracts.testToken.connect(deployer).transfer(tester.address, transferAmount);
      await tx.wait();

      const newBalance = await contracts.testToken.balanceOf(tester.address);
      console.log(`Tester${i + 1} token balance: ${formatEther(newBalance)} TT`);
    } else {
      console.log(`Tester${i + 1} already has ${formatEther(tokenBalance)} TT`);
    }

    // Check KAIA balance
    const kaiaBalance = await ethers.provider.getBalance(tester.address);
    console.log(`Tester${i + 1} KAIA balance: ${formatEther(kaiaBalance)} KAIA`);
  }

  return testers;
}

/**
 * Verify balances for all testers after transactions are executed
 * @param testers Array of test user wallets
 * @param contracts Contract objects
 * @param gaslessBlockNum Block number where transactions were executed
 */
async function verifyAllBalances(testers: any[], contracts: any, gaslessBlockNum: number) {
  console.log("\nVerifying balances for all users...");

  for (let i = 0; i < testers.length; i++) {
    const tester = testers[i];
    console.log(`\n--- Tester${i + 1} (${tester.address}) ---`);
    await verifyBalance(tester, contracts, gaslessBlockNum);
  }
}

/**
 * Verify logs for all transactions
 * @param testers Array of test user wallets
 * @param contracts Contract objects
 * @param txs Array of transaction hashes
 * @param gaslessBlockNum Block number where transactions were executed
 */
async function verifyAllLogs(testers: any[], contracts: any, txs: any[], gaslessBlockNum: number) {
  console.log("\nVerifying transaction logs for all users...");

  for (let i = 0; i < testers.length; i++) {
    const tester = testers[i];
    const swapTxIndex = i * 2 + 1; // Swap transactions are at odd indices

    console.log(`\n--- Tester${i + 1} (${tester.address}) ---`);
    console.log(`Transaction hash: ${txs[swapTxIndex]}`);

    // We need to pass an array with two transactions for compatibility with the original function
    const userTxs = [txs[swapTxIndex - 1], txs[swapTxIndex]];
    await verifyLogs(tester, contracts, userTxs, gaslessBlockNum);
  }
}

async function main() {
  console.log("\n1. Setting up contracts and test users...");
  const testToken = await getContractFromDeployment(hre, "TestToken");
  const wkaia = await getContractFromDeployment(hre, "WKAIA");
  const uniRouter = await getContractFromDeployment(hre, "UniswapV2Router02");
  const gsr = await getContractFromDeployment(hre, "GaslessSwapRouter");
  const contracts = { testToken, wkaia, uniRouter, gsr };

  // Setup test users and check balances
  const testers = await setupTestUsers(contracts);

  console.log("\n2. Generating transactions for all testers...");
  const rawTxs = [];

  for (let i = 0; i < testers.length; i++) {
    const tester = testers[i];

    // Generate approve transaction
    console.log(`\nGenerating transactions for tester${i + 1} (${tester.address})...`);
    const approveRawTx = await getApproveRawTx(tester, contracts);
    rawTxs.push(approveRawTx);

    // Generate swap transaction
    const swapRawTx = await getSwapRawTx(tester, contracts, false);
    rawTxs.push(swapRawTx);
  }

  console.log(`\n3. Sending ${rawTxs.length} transactions using kaia_sendRawTransactions...`);
  const chainId = (await ethers.provider.getNetwork()).chainId;
  let txs = [];

  if (chainId == 31337n) {
    console.log("It's a hardhat network, so using eth_sendRawTransaction for each transaction");
    // Hardhat network - send transactions one by one
    for (const rawTx of rawTxs) {
      const tx = await hre.network.provider.send("eth_sendRawTransaction", [rawTx]);
      txs.push(tx);
    }
  } else {
    // Use kaia_sendRawTransactions for batch sending
    txs = await hre.network.provider.send("kaia_sendRawTransactions", [rawTxs]);
  }

  // Print transaction hashes
  for (let i = 0; i < txs.length; i++) {
    const userIndex = Math.floor(i / 2) + 1;
    const txType = i % 2 === 0 ? "Approve" : "Swap";
    console.log(`Tester${userIndex} ${txType} Transaction Hash: ${txs[i]}`);
  }

  // Wait for the last swap transaction to be mined
  const lastSwapTxHash = txs[txs.length - 1];
  console.log(`\nWaiting for the last swap transaction (${lastSwapTxHash}) to be mined...`);
  const receipt = await waitForReceipt(lastSwapTxHash);

  if (!receipt) {
    console.log("❌ No receipt found for the last swap transaction.");
    return;
  }

  const gaslessBlockNum = receipt?.blockNumber;
  console.log(`Transaction mined in block: ${gaslessBlockNum}`);

  // Verify balances and logs
  await verifyAllBalances(testers, contracts, gaslessBlockNum);
  await verifyAllLogs(testers, contracts, txs, gaslessBlockNum);
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
