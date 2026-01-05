import { ethers } from "hardhat";
import { gasPriceBN } from "./utils";
import hre from "hardhat";
import { formatEther, parseUnits } from "ethers";

async function main() {
  if (!process.env.TESTER) {
    throw new Error("TESTER environment variables must be set");
  }
  if (!process.env.RICH) {
    throw new Error("RICH environment variables must be set");
  }

  const tester = new hre.ethers.Wallet(process.env.TESTER, hre.ethers.provider);
  const rich = new hre.ethers.Wallet(process.env.RICH, hre.ethers.provider);
  const tx = await rich.sendTransaction({
    to: tester.address,
    value: parseUnits("1", "ether"),
  });
  console.log(`Sent transaction: ${tx.hash}`);
  const receipt = await tx.wait();
  console.log(`✅ Transaction successfully mined in block ${receipt!.blockNumber}`);
  console.log(`✅ Send 1 KAIA from RICH -> TESTER`);
  console.log(`✅ Tester KAIA balance: ${formatEther(await ethers.provider.getBalance(tester.address))} KAIA`);
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
