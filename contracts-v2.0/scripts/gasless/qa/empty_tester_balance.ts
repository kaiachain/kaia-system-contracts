import { ethers } from "hardhat";
import { gasPriceBN } from "./utils";
import hre from "hardhat";
import { formatEther } from "ethers";

async function main() {
  if (!process.env.TESTER) {
    throw new Error("TESTER environment variables must be set");
  }
  if (!process.env.RICH) {
    throw new Error("RICH environment variables must be set");
  }

  const tester = new hre.ethers.Wallet(process.env.TESTER, hre.ethers.provider);
  const rich = new hre.ethers.Wallet(process.env.RICH, hre.ethers.provider);
  const kaiaBalance = await ethers.provider.getBalance(tester.address);
  const gasLimit = 21000; // Standard transfer gas
  const gasCost = BigInt(gasLimit) * gasPriceBN;
  if (kaiaBalance < gasCost) {
    console.log("Tester KAIA balance is less than gas cost, so no need to empty it");
    return;
  }
  const amountToTransfer = kaiaBalance - gasCost;

  const tx = await tester.sendTransaction({
    to: rich.address,
    value: amountToTransfer,
    gasLimit: 21000,
    gasPrice: gasPriceBN, // manual gas required because estimateGas fails
  });
  console.log(`Sent transaction: ${tx.hash}`);
  const receipt = await tx.wait();
  console.log(`✅ Transaction successfully mined in block ${receipt!.blockNumber}`);
  console.log(`✅ Send ${formatEther(amountToTransfer)} KAIA from TESTER -> RICH`);
  console.log(`✅ Tester KAIA balance: ${formatEther(await ethers.provider.getBalance(tester.address))} KAIA`);
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
