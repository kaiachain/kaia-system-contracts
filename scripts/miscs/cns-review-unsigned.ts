import { Contract, ethers, toBeHex } from "ethers";
import { CN_TARGET_ADDRESS, CnStaking_ABI, provider } from "../utils";

const reviewerAddr = "0x7ad2B77835076225B48447eABC4f2A2E640CCE33";

// unsigned tx for signer V2
async function main() {
  if (CN_TARGET_ADDRESS == null) {
    console.error("environment variable CN_TARGET_ADDRESS not set");
    return;
  }
  const cns = new Contract(CN_TARGET_ADDRESS!, CnStaking_ABI, provider);
  const sender = new ethers.VoidSigner(reviewerAddr);
  let unsignedTx: any = await cns.reviewInitialConditions.populateTransaction({ from: sender.address });

  unsignedTx.from = sender.address;
  const chainId = Number((await provider.getNetwork()).chainId);
  const gasPrice = (await provider.getFeeData()).gasPrice?.toString();
  const nonce = await provider.getTransactionCount(sender.address);
  const gas = toBeHex(await cns.reviewInitialConditions.estimateGas({ from: sender.address }));

  unsignedTx = {
    ...unsignedTx,
    ...{
      type: "smartContractExecution",
      gas,
      gasPrice,
      chainId,
      nonce,
      value: "0x",
    },
  };

  console.log(JSON.stringify(unsignedTx));
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
