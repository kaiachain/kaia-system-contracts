import * as fs from "fs";
import { toBeHex } from "ethers";
import { Contract } from "ethers";
import { provider, ABook_ABI, ADDRESS_BOOK_ADDRESS } from "../utils";

async function main() {
  const ab = new Contract(ADDRESS_BOOK_ADDRESS, ABook_ABI, provider);
  console.log((await provider.getBlockNumber()) + 1);

  const unregisterTargets: { nodeId: string; signer: string }[] = [
    /* 4/25
      { nodeId: "0xe3d92072d8b9a59a0427485a1b5f459271df457c", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
      { nodeId: "0xe3d92072d8b9a59a0427485a1b5f459271df457c", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
      { nodeId: "0xc032c34cB9FE064Fe435199e1078dD8756a166b5", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
      { nodeId: "0xc032c34cB9FE064Fe435199e1078dD8756a166b5", signer: "0xEa617Ac3F4661351A16fd27d945009544e036336" },
      { nodeId: "0x27cbaf98ddfb5c09c787cd6d99a77c5774152b43", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
      { nodeId: "0x27cbaf98ddfb5c09c787cd6d99a77c5774152b43", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
      { nodeId: "0x74f64cb6c2db9e0b270df1d4e563920381aec034", signer: "0xEa617Ac3F4661351A16fd27d945009544e036336" },
      { nodeId: "0x74f64cb6c2db9e0b270df1d4e563920381aec034", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
      { nodeId: "0x6873352021fe9226884616dc6f189f289aeb0cc5", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
      { nodeId: "0x6873352021fe9226884616dc6f189f289aeb0cc5", signer: "0xEa617Ac3F4661351A16fd27d945009544e036336" },
     */
    /* 4/26
    { nodeId: "0x52d41ca72af615a1ac3301b0a93efa222ecc7541", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
    { nodeId: "0x52d41ca72af615a1ac3301b0a93efa222ecc7541", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0x03497F51c31fE8b402DF0bDE90Fd5A85f87aA943", signer: "0xEa617Ac3F4661351A16fd27d945009544e036336" },
    { nodeId: "0x03497F51c31fE8b402DF0bDE90Fd5A85f87aA943", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
    { nodeId: "0xaf7e157d2d7b571abe7161bf193bb697706e2172", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0xaf7e157d2d7b571abe7161bf193bb697706e2172", signer: "0xEa617Ac3F4661351A16fd27d945009544e036336" },
    { nodeId: "0x52c0f3654e9ac47ba5e64ffcb398be485718a74b", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
    { nodeId: "0x52c0f3654e9ac47ba5e64ffcb398be485718a74b", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
     */
    /* 4/27
    { nodeId: "0xED6Ee8a1877f9582858dBE2509aBB0aC33E5f24E", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
    { nodeId: "0xED6Ee8a1877f9582858dBE2509aBB0aC33E5f24E", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0x5c66443b9D6Ea82039D0ea3E04e8287688DcD4E0", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
    { nodeId: "0x5c66443b9D6Ea82039D0ea3E04e8287688DcD4E0", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    */
    /* 5/3
    { nodeId: "0x36ff2aa21d5c6828ee12cd2bc3de0e987bc0d4e7", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
    { nodeId: "0x36ff2aa21d5c6828ee12cd2bc3de0e987bc0d4e7", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0x0654070bc091446d9ef8735d280e0a251c45cf4c", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
    { nodeId: "0x0654070bc091446d9ef8735d280e0a251c45cf4c", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
     */
    /* 5/4
    { nodeId: "0xe36ea146c05757a38ec1493eea8c878677a9c19a", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
    { nodeId: "0xe36ea146c05757a38ec1493eea8c878677a9c19a", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
     */
    /* 5/17
    { nodeId: "0x1fb27697b0d52e460c84c47d13d95f7daec94d1a", signer: "0xd5ae00D1e6D2CF737A8aEC7D46Bd95ECA3F89008" },
    { nodeId: "0x1fb27697b0d52e460c84c47d13d95f7daec94d1a", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0x1fb27697b0d52e460c84c47d13d95f7daec94d1a", signer: "0x5e8cD1c5DB6d11c4fb15B3573730D349Ca1C7353" },
    { nodeId: "0x1fb27697b0d52e460c84c47d13d95f7daec94d1a", signer: "0x47e8733092C401bc61bDA8046e5903079708d107" },
    { nodeId: "0x1fb27697b0d52e460c84c47d13d95f7daec94d1a", signer: "0xEa617Ac3F4661351A16fd27d945009544e036336" },
     */
    /* 2024/4/9
    { nodeId: "0x7B065fBb3A9B6e97F2ba788d63700bD4B8B408Bc", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0x7B065fBb3A9B6e97F2ba788d63700bD4B8B408Bc", signer: "0xf4c9f79683e67c33150500a2ac06163c38c517b6" },
    { nodeId: "0xC0094bf2fb2FAD63261afa39a75b3883D91A4c57", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0xC0094bf2fb2FAD63261afa39a75b3883D91A4c57", signer: "0xf4c9f79683e67c33150500a2ac06163c38c517b6" },
    { nodeId: "0x0b59caE1F03534209FdB9dDF5eA65b310Cd7060c", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0x0b59caE1F03534209FdB9dDF5eA65b310Cd7060c", signer: "0xf4c9f79683e67c33150500a2ac06163c38c517b6" },
    { nodeId: "0xa3b387b7B0dC914a4F106Ad645A0Ad079d70EBdC", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0xa3b387b7B0dC914a4F106Ad645A0Ad079d70EBdC", signer: "0xf4c9f79683e67c33150500a2ac06163c38c517b6" },
    { nodeId: "0x140FfDF900768f1B6883f4035A6B650c4a3789aa", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0x140FfDF900768f1B6883f4035A6B650c4a3789aa", signer: "0xf4c9f79683e67c33150500a2ac06163c38c517b6" },
     */
    /* 2024/9/25
    { nodeId: "0x993efc86499ff9a47e5770040a02f37ed9469911", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0x993efc86499ff9a47e5770040a02f37ed9469911", signer: "0xf4c9f79683e67c33150500a2ac06163c38c517b6" },
     */
    /* 2024/10/22
    { nodeId: "0xa3b387b7b0dc914a4f106ad645a0ad079d70ebdc", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    { nodeId: "0xa3b387b7b0dc914a4f106ad645a0ad079d70ebdc", signer: "0xF4C9F79683e67c33150500a2ac06163c38c517b6" },
     */
    /* 2024/12/02 */
    { nodeId: "0xe3d92072d8b9a59a0427485a1b5f459271df457c", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    // { nodeId: "0xe3d92072d8b9a59a0427485a1b5f459271df457c", signer: "0xc2364927759d2731836387ebf45b95c70708ee55" },
    // { nodeId: "0x7880fe25dd0669fffbd82cf6e78c16d69af82a11", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    // { nodeId: "0x7880fe25dd0669fffbd82cf6e78c16d69af82a11", signer: "0xc2364927759d2731836387ebf45b95c70708ee55" },
    // { nodeId: "0x1390eab3ad2e674646a8f92460098886409fd57b", signer: "0x22b9E2ed59DB03Bc557441EbdFD29B81D17A12AC" },
    // { nodeId: "0x1390eab3ad2e674646a8f92460098886409fd57b", signer: "0xc2364927759d2731836387ebf45b95c70708ee55" },
  ];

  const nonceMap: { [key: string]: number } = {};

  for (const [i, target] of unregisterTargets.entries()) {
    console.log(`Generating target:${target.nodeId} from:${target.signer}`);
    const sender = target.signer;
    try {
      const unsignedTx: any = await ab.submitUnregisterCnStakingContract.populateTransaction(target.nodeId);
      unsignedTx.from = sender;

      const gasLimit = await ab.submitUnregisterCnStakingContract.estimateGas(target.nodeId, { from: sender });
      const gasPrice = (await provider.getFeeData()).gasPrice?.toString();

      unsignedTx.chainId = Number((await provider.getNetwork()).chainId);
      unsignedTx.gasLimit = toBeHex(gasLimit * 2n);
      unsignedTx.gasPrice = gasPrice?.toString();
      if (nonceMap[sender] == null) {
        const nonce = await provider.getTransactionCount(sender);
        nonceMap[sender] = nonce;
      }
      unsignedTx.nonce = nonceMap[sender];
      nonceMap[sender] += 1;
      unsignedTx.value = "0x"; // TODO: parse value

      const wrap = {
        description: `Unregister ${target.nodeId}`,
        txComment: "AddressBookUnRegister를 위한 트랜잭션",
        from: sender,
        type: "unregister",
        txAction: "AddressBook-Unregister",
        txTarget: "AddressBook",
        rawTx: unsignedTx,
      };
      const ret = JSON.stringify(wrap);
      const output = `${(i + 1)
        .toString()
        .padStart(2, "0")}-RawTx-${new Date().toJSON()}-AddressBook-Unregister-${target.nodeId.substring(
        0,
        6,
      )}-from-${sender.substring(0, 6)}.json`;
      fs.writeFileSync(output, ret);
    } catch (err) {
      console.error(err);
      console.error(`error from ${sender}; continuing`);
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
