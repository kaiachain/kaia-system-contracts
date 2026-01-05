import * as fs from "fs";
import { ethers, toBeHex, VoidSigner } from "ethers";
import { provider, ABook_ABI, ADDRESS_BOOK_ADDRESS, PENDING_REWARD_ADDRESS, CN_TARGET_ADDRESS } from "../utils";
import { Interface, Contract } from "ethers";

const CnStaking_ABI = new Interface([
  "function acceptRewardAddress(address _rewardAddress) external",
  "function VERSION() external view returns (uint256)",
]);

async function main() {
  if (PENDING_REWARD_ADDRESS == null || CN_TARGET_ADDRESS == null) {
    console.error("environment variable PENDING_REWARD_ADDRESS or CN_TARGET_ADDRESS not set");
    return;
  }
  const ab = new Contract(ADDRESS_BOOK_ADDRESS, ABook_ABI, provider);
  const rewardAddr = PENDING_REWARD_ADDRESS;
  const to = CN_TARGET_ADDRESS;
  const cns = new Contract(to, CnStaking_ABI, provider);
  let version: number;
  try {
    version = await cns.VERSION();
  } catch (err) {
    console.error(err);
    console.error("error from VERSION");
    return;
  }
  const [adminList] = await ab.getState();

  for (const admin of adminList) {
    const sender = new VoidSigner(admin);
    console.log(`Generating to:${to} rewardAddr:${rewardAddr} from:${admin}`);

    try {
      const unsignedTx: any = await cns.acceptRewardAddress.populateTransaction(rewardAddr);
      unsignedTx.from = sender.address;

      const gasLimit = await cns.acceptRewardAddress.estimateGas(rewardAddr, { from: sender.address });
      const gasPrice = (await provider.getFeeData()).gasPrice?.toString();

      unsignedTx.chainId = Number((await provider.getNetwork()).chainId);
      unsignedTx.gasLimit = toBeHex(gasLimit * 2n);
      unsignedTx.gasPrice = gasPrice?.toString();
      unsignedTx.nonce = await provider.getTransactionCount(sender.address);
      unsignedTx.value = "0x"; // TODO: parse value

      const wrap = {
        description: "ACCEPT-REWARD",
        txComment: `acceptReward를 위한 트랜잭션`,
        from: sender.address,
        type: "acceptReward",
        txAction: `CnStakingV${version}-AcceptReward`,
        txTarget: `CnStakingV${version}`,
        rawTx: unsignedTx,
      };
      const ret = JSON.stringify(wrap);
      const output = `RawTx-${new Date().toJSON()}-AcceptReward-to-${to.substring(
        0,
        6,
      )}-from-${sender.address.substring(0, 6)}.json`;
      fs.writeFileSync(output, ret);
    } catch (err) {
      console.error(err);
      console.error(`error from ${sender.address}; continuing`);
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
