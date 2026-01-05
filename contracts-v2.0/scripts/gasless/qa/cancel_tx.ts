import { Wallet, TxType } from "@kaiachain/ethers-ext/src/v6";
import hre from "hardhat";

async function main() {
  if (!process.env.TESTER) {
    throw new Error("TESTER environment variables must be set");
  }

  const tester = new hre.ethers.Wallet(process.env.TESTER, hre.ethers.provider);
  const wallet = new Wallet(tester.privateKey, hre.ethers.provider);

  const tx = {
    type: TxType.Cancel,
    from: tester.address,
  };

  const sentTx = await wallet.sendTransaction(tx);
  console.log(`Sent transaction: ${sentTx.hash}`);
  const receipt = await sentTx.wait();
  console.log(`✅ Transaction successfully mined in block ${receipt!.blockNumber}`);
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
