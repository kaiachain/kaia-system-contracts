import * as fs from "fs";
import { Contract, toBeHex, VoidSigner } from "ethers";
import { provider, TREASURY_REBALANCE_V2_ADDRESS, TreasuryRebalanceV2_ABI } from "../utils";

async function main() {
  if (TREASURY_REBALANCE_V2_ADDRESS == null) {
    console.error("environment variable TREASURY_REBALANCE_V2_ADDRESS not set");
    return;
  }
  const tr = new Contract(TREASURY_REBALANCE_V2_ADDRESS!, TreasuryRebalanceV2_ABI, provider);

  const admins: { name: string; zeroed: string; signer: string }[] = [
    /* Testnet: 2024/6/11
    {
      name: "KFF",
      zeroed: "0x8B537f5BC7d176a94D7bF63BeFB81586EB3D1c0E",
      signer: "0x6f20cce7083Ab502851E43845793E6C60bDD5812",
    }, // KFF
    {
      name: "KFF",
      zeroed: "0x8B537f5BC7d176a94D7bF63BeFB81586EB3D1c0E",
      signer: "0x35fF0d3F2bc9dE537D64D3d41111868B279e7624",
    },
    {
      name: "KCF",
      zeroed: "0x47E3DbB8c1602BdB0DAeeE89Ce59452c4746CA1C",
      signer: "0x2E9161D7373343aB227C7CA77a067b34245E71ac",
    }, // KCF
    {
      name: "KCF",
      zeroed: "0x47E3DbB8c1602BdB0DAeeE89Ce59452c4746CA1C",
      signer: "0x11FB41d070F415718BF91Dbe27Fb4eF5cE931b5a",
    },
    {
      name: "KVCF",
      zeroed: "0xaa8d19a5e17e9e1bA693f13aB0E079d274a7e51E",
      signer: "0x61F6C160ee6A039e7554E6276c8F27304cB82004",
    }, // KVCF
    {
      name: "KVCF",
      zeroed: "0xaa8d19a5e17e9e1bA693f13aB0E079d274a7e51E",
      signer: "0xD56068aa0ac28e02D89DC87bD35E6B615b3F824E",
    },
     */
    /* Mainnet: 2024/8/28 */
    {
      name: "KFF",
      zeroed: "0x85D82D811743b4B8F3c48F3e48A1664d1FfC2C10",
      signer: "0xD006c060AE9A2a2627cbEa015685Fbd3133dB5D6",
    },
    {
      name: "KFF",
      zeroed: "0x85D82D811743b4B8F3c48F3e48A1664d1FfC2C10",
      signer: "0x36EF18fd422965b0b847a865f528A7033ca6394e",
    },
    {
      name: "KFF",
      zeroed: "0x85D82D811743b4B8F3c48F3e48A1664d1FfC2C10",
      signer: "0x3A08E8b3746DE021BD63693D5BC9c3545597b1b5",
    },
    {
      name: "KCF",
      zeroed: "0xdd4C8d805fC110369D3B148a6692F283ffBDCcd3",
      signer: "0x4acD67215532DF133672302f169217E648f21AEA",
    },
    {
      name: "KCF",
      zeroed: "0xdd4C8d805fC110369D3B148a6692F283ffBDCcd3",
      signer: "0xbF51Fd90a625bDf372E64d1b0A6Af2068c42EF04",
    },
    {
      name: "KCF",
      zeroed: "0xdd4C8d805fC110369D3B148a6692F283ffBDCcd3",
      signer: "0x072eb910C3586a4D22DF3fd289F8ea0EE26a28B8",
    },
    {
      name: "KVCF",
      zeroed: "0x4f04251064274252D27D4af55BC85b68B3adD992",
      signer: "0x477ba0279A99cd9837216fddad13B07a40C79884",
    },
    {
      name: "KVCF",
      zeroed: "0x4f04251064274252D27D4af55BC85b68B3adD992",
      signer: "0xd8D9f144fFBD6A3c35c8f8952DcaD90BD78E9BA7",
    },
    {
      name: "KVCF",
      zeroed: "0x4f04251064274252D27D4af55BC85b68B3adD992",
      signer: "0x40e9b66F4a10f97d01902ea3b6642D3917191Ce7",
    },
  ];

  const nonceMap: { [key: string]: number } = {};

  for (const [i, target] of admins.entries()) {
    console.log(`Generating from:${target.signer}`);
    const sender = new VoidSigner(target.signer);
    try {
      const unsignedTx: any = await tr.approve.populateTransaction(target.zeroed, { from: sender.address });

      unsignedTx.from = sender.address;
      const gasLimit = await tr.approve.estimateGas(target.zeroed, { from: sender.address });
      const gasPrice = (await provider.getFeeData()).gasPrice?.toString();
      unsignedTx.chainId = Number((await provider.getNetwork()).chainId);
      unsignedTx.gasLimit = toBeHex(gasLimit * 2n);
      unsignedTx.gasPrice = gasPrice?.toString();
      if (nonceMap[sender.address] == null) {
        const nonce = await provider.getTransactionCount(sender.address);
        nonceMap[sender.address] = nonce;
      }
      unsignedTx.nonce = nonceMap[sender.address];
      nonceMap[sender.address] += 1;
      unsignedTx.value = "0x"; // TODO: parse value

      const wrap = {
        description: `Approve for ${target.zeroed}`,
        txComment: `TreasuryRebalanceV2에 ${target.name} Approve를 위한 트랜잭션`,
        from: sender.address,
        type: "approve",
        txAction: `TreasuryRebalanceV2-${target.name}-Approve`,
        txTarget: "TreasuryRebalanceV2",
        rawTx: unsignedTx,
      };
      const ret = JSON.stringify(wrap);
      const output = `${(i + 1).toString().padStart(2, "0")}-RawTx-${new Date().toJSON()}-TreasuryRebalanceV2-${
        target.name
      }-Approve-${target.zeroed.substring(0, 6)}-from-${sender.address.substring(0, 6)}.json`;
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
