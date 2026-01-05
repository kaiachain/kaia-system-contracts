import { execSync } from "child_process";
import { MaxUint256, parseEther, parseUnits, Wallet } from "ethers";
import { formatEther, getAddress } from "ethers";
import hre from "hardhat";

export async function execCommand(command: string): Promise<string> {
  try {
    console.log(`Executing: ${command}`);
    const output = execSync(command, { stdio: ["inherit", "pipe", "inherit"] }).toString();
    return output;
  } catch (error: any) {
    console.error(`❌ Failed to execute command: ${command}`);
    throw error;
  }
}

export async function waitForReceipt(transactionHash: string) {
  let receipt: any;
  let attempts = 0;
  const maxAttempts = 10;

  while (!receipt && attempts < maxAttempts) {
    try {
      receipt = await hre.ethers.provider.getTransactionReceipt(transactionHash);
      if (!receipt) {
        console.log(`Receipt not found yet. Waiting... (attempt ${attempts + 1}/${maxAttempts})`);
        await new Promise((resolve) => setTimeout(resolve, 1000)); // 1 second wait
      }
    } catch (error) {
      console.error(`Error fetching receipt (attempt ${attempts + 1}/${maxAttempts}):`, error);
      await new Promise((resolve) => setTimeout(resolve, 1000)); // 1 second wait on error
    }
    attempts++;
  }

  if (!receipt) {
    console.log(`Gave up waiting for receipt after ${maxAttempts} attempts`);
  }

  return receipt;
}

export async function waitForTargetBlock(targetBlock: number, pollInterval = 1000, maxAttempts = 60): Promise<void> {
  console.log(
    `Waiting for block ${targetBlock} to be reached (current: ${await hre.ethers.provider.getBlockNumber()})...`,
  );

  let attempts = 0;
  while (attempts < maxAttempts) {
    const currentBlock = await hre.ethers.provider.getBlockNumber();

    if (currentBlock >= targetBlock) {
      console.log(`✅ Target block ${targetBlock} reached (current: ${currentBlock})`);
      return;
    }

    attempts++;
    console.log(
      `Current block: ${currentBlock}, waiting for block: ${targetBlock} (attempt ${attempts}/${maxAttempts})`,
    );
    await new Promise((resolve) => setTimeout(resolve, pollInterval));
  }

  throw new Error(`Timeout waiting for block ${targetBlock} after ${maxAttempts} attempts`);
}

export async function checkAndTransferOwnership(gaslessRouterAddress: string, deployer: any) {
  const gaslessRouter = await hre.ethers.getContractAt("GaslessSwapRouter", gaslessRouterAddress);

  const currentOwner = await gaslessRouter.owner();
  console.log("Current owner:", currentOwner);
  console.log("Deployer address:", deployer.address);

  if (currentOwner.toLowerCase() !== deployer.address.toLowerCase()) {
    console.log("Transferring ownership to deployer...");
    const tx = await gaslessRouter.transferOwnership(deployer.address);
    await tx.wait();
    console.log("Ownership transferred to deployer");
  } else {
    console.log("Deployer is already the owner");
  }
}

export async function getApproveRawTx(tester: Wallet, contracts: any) {
  // Create and sign the approve transaction
  console.log("Creating approval transaction...");
  const approveData = contracts.testToken.interface.encodeFunctionData("approve", [
    await contracts.gsr.getAddress(),
    allowanceAmount,
  ]);
  const nonce = await tester.getNonce();
  const chainId = (await hre.ethers.provider.getNetwork()).chainId;
  console.log(`nonce: ${nonce}`, "token", await contracts.testToken.getAddress());

  const approveTx = {
    type: 0,
    to: await contracts.testToken.getAddress(),
    nonce: nonce,
    gasLimit: approveGas,
    gasPrice: gasPriceBN,
    data: approveData,
    value: 0n,
    chainId: chainId,
  };

  // Sign the transaction
  const approveRawTx = await tester.signTransaction(approveTx);
  console.log(`Generated signed approve raw transaction: ${approveRawTx}`);
  return approveRawTx;
}

// If isSingle=false, swapTx is preceded by approveTx.
export async function getSwapRawTx(tester: Wallet, contracts: any, isSingle: boolean, deadline?: number) {
  const nonce = (await tester.getNonce()) + (isSingle ? 0 : 1);
  const chainId = Number((await hre.ethers.provider.getNetwork()).chainId);
  const amountsOut = await contracts.uniRouter.getAmountsOut(swapAmount, [
    await contracts.testToken.getAddress(),
    await contracts.wkaia.getAddress(),
  ]);
  const swapExpectedOutput = BigInt(amountsOut[1]);

  // Calculate required amounts
  const amountRepay = isSingle ? amountRepaySwapOnly : amountRepayApproveAndSwap;
  const margin = (swapExpectedOutput * 1n) / 100n; // 1% margin
  const minAmountOut = amountRepay + margin;

  console.log("\nSwap parameters:");
  console.log(`Amount to swap: ${formatEther(swapAmount)} TT`);
  console.log(`Expected output: ${formatEther(swapExpectedOutput)} KAIA`);
  console.log(`Minimum amount out: ${formatEther(minAmountOut)} KAIA`);
  console.log(`Gas repayment amount: ${formatEther(amountRepay)} KAIA`);
  const currentBlock = await hre.ethers.provider.getBlock("latest");
  if (!currentBlock) {
    throw new Error("Current block not found");
  }
  deadline = deadline ?? currentBlock.timestamp + 300;

  // Create and sign the swap transaction
  const swapData = contracts.gsr.interface.encodeFunctionData("swapForGas", [
    await contracts.testToken.getAddress(),
    swapAmount,
    minAmountOut,
    amountRepay,
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

async function getMiner(blockNum: number) {
  const block = await hre.ethers.provider.getBlock(blockNum);
  return block?.miner.toLowerCase();
}

export async function verifyBalance(tester: Wallet, contracts: any, gaslessBlockNum: number) {
  const preToken = formatEther(await contracts.testToken.balanceOf(tester.address, { blockTag: gaslessBlockNum - 1 }));
  const postToken = formatEther(await contracts.testToken.balanceOf(tester.address, { blockTag: gaslessBlockNum }));

  if (preToken != postToken) {
    console.log(`✅ tester TestToken decreased: ${preToken} -> ${postToken} TT.`);
  } else {
    console.log(`❌ tester TestToken not decreased: ${preToken} -> ${postToken} TT.`);
  }
  const blockReward = parseEther("9.6");
  const miner = await getMiner(gaslessBlockNum);
  console.log(`miner: ${miner}`);
  const council = await hre.ethers.provider.send("kaia_getCouncil", []);
  const proposers: { [key: string]: string } = {};
  for (let i = 0; i < council.length; i++) {
    proposers[`proposer${i}`] = council[i];
  }

  const addrs = {
    tester: tester.address,
    gsr: await contracts.gsr.getAddress(),
    ...proposers,
  };
  for (const [name, addr] of Object.entries(addrs)) {
    const preKaia = await hre.ethers.provider.getBalance(addr, gaslessBlockNum - 1);
    const postKaia = await hre.ethers.provider.getBalance(addr, gaslessBlockNum);
    let changeExpedted = false;
    let isMiner = false;
    if (addr == tester.address) {
      changeExpedted = true;
    }
    if (addr.toLowerCase() == miner) {
      isMiner = true;
    }
    const pass =
      (!changeExpedted && preKaia == postKaia) ||
      (changeExpedted && preKaia != postKaia) ||
      (isMiner && preKaia + blockReward == postKaia);
    console.log(
      `${pass ? "✅" : "❌"} ${name} KAIA ${preKaia == postKaia ? "unchanged" : "changed"}: ${formatEther(
        preKaia,
      )} -> ${formatEther(postKaia)} KAIA.`,
    );
  }
}

export async function verifyLogs(
  tester: any,
  contracts: any,
  txs: any,
  gaslessBlockNum: number,
  customAmountRepay?: bigint,
) {
  const expectedAmountRepaid = customAmountRepay || amountRepayApproveAndSwap;

  const swapSig = "SwappedForGas(address,uint256,address,uint256,uint256)";
  const swapTopic = hre.ethers.id(swapSig);
  const swapReceipt = await hre.network.provider.send("eth_getTransactionReceipt", [txs[1]]);
  const gsrAddr = (await contracts.gsr.getAddress()).toLowerCase();
  const swappedForGasEvent = swapReceipt.logs.find((log: any) => {
    return log.address.toLowerCase() === gsrAddr && log.topics[0] === swapTopic;
  });

  const swapBlockMiner = await getMiner(gaslessBlockNum);

  // Event data
  let proposerFromEvent = "";
  let amountRepaidFromEvent = 0n;
  let finalUserAmountFromEvent = 0n;
  let commissionFromEvent = 0n;
  let totalEventAmount = 0n;

  if (!swappedForGasEvent) {
    console.log("❌ SwappedForGas event not found in transaction logs");
    return;
  }

  console.log("✅ Found SwappedForGas event");

  proposerFromEvent = getAddress("0x" + swappedForGasEvent.topics[1].slice(26)).toLowerCase();
  const userFromEvent = getAddress("0x" + swappedForGasEvent.topics[2].slice(26));

  const dataWithoutPrefix = swappedForGasEvent.data.slice(2);
  const amountRepaidHex = "0x" + dataWithoutPrefix.slice(0, 64);
  const finalUserAmountHex = "0x" + dataWithoutPrefix.slice(64, 128);
  const commissionHex = "0x" + dataWithoutPrefix.slice(128, 192);

  amountRepaidFromEvent = BigInt(amountRepaidHex);
  finalUserAmountFromEvent = BigInt(finalUserAmountHex);
  commissionFromEvent = BigInt(commissionHex);

  console.log("\nEvent data decoded:");
  console.log(`Proposer: ${proposerFromEvent}`);
  console.log(`User: ${userFromEvent}`);
  console.log(`Amount repaid: ${formatEther(amountRepaidFromEvent)} KAIA`);
  console.log(`Final user amount: ${formatEther(finalUserAmountFromEvent)} KAIA`);
  console.log(`Commission: ${formatEther(commissionFromEvent)} KAIA`);

  if (userFromEvent.toLowerCase() === tester.address.toLowerCase()) {
    console.log("✅ User address in event matches test user");
  } else {
    console.log(`❌ User address in event (${userFromEvent}) does not match test user (${tester.address})`);
  }

  if (proposerFromEvent === swapBlockMiner) {
    console.log("✅ Proposer address in event matches block miner");
  } else {
    console.log(`❌ Proposer address in event (${proposerFromEvent}) does not match block miner (${swapBlockMiner})`);
  }

  if (amountRepaidFromEvent === expectedAmountRepaid) {
    console.log("✅ Amount repaid matches expected amount");
  } else {
    console.log(
      `⚠️ Amount repaid (${formatEther(amountRepaidFromEvent)}) differs from expected amount (${formatEther(
        expectedAmountRepaid,
      )})`,
    );
  }

  // exchange ratio before swap
  const amountsOut = await contracts.uniRouter.getAmountsOut(
    swapAmount,
    [await contracts.testToken.getAddress(), await contracts.wkaia.getAddress()],
    {
      blockTag: gaslessBlockNum - 1,
    },
  );
  const swapExpectedOutput = BigInt(amountsOut[1]);
  const receivedAmount = swapExpectedOutput;
  const postKaia = await hre.ethers.provider.getBalance(tester.address, gaslessBlockNum);
  console.log(`Event reported final user amount: ${formatEther(finalUserAmountFromEvent)} KAIA`);
  console.log(`Test user received amount: ${formatEther(postKaia)} KAIA`);

  const calculatedAmount = receivedAmount - amountRepayApproveAndSwap - commissionFromEvent;
  console.log(`Calculated final amount: ${formatEther(calculatedAmount)} KAIA`);

  totalEventAmount = amountRepaidFromEvent + finalUserAmountFromEvent + commissionFromEvent;
  console.log(`Total event amount: ${formatEther(totalEventAmount)} KAIA`);
  console.log(`Expected swap output: ${formatEther(swapExpectedOutput)} KAIA`);
}

export const gasPriceBN = parseUnits("25", "gwei");
export const approveGas = 100000n;
export const swapGas = 500000n;
export const R1 = gasPriceBN * 21000n;
export const R2 = gasPriceBN * approveGas;
export const R3 = gasPriceBN * swapGas;
export const amountRepayApproveAndSwap = R1 + R2 + R3;
export const amountRepaySwapOnly = R1 + R3;
export const swapAmount = parseEther("1.0");
export const allowanceAmount = MaxUint256;
