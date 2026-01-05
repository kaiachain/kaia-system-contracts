import { BlsPublicInfoFile, validatePop, getSBR } from "../utils";
import * as fs from "fs";

export async function sbrInfo() {
  const sbr = await getSBR();
  const ret = await sbr.getAllBlsInfo();
  if (ret.nodeIdList.length == 0) {
    console.log("Empty record");
    return;
  }

  for (let i = 0; i < ret.nodeIdList.length; i++) {
    console.log(`* Entry #${i}`);
    console.log("  * nodeId", ret.nodeIdList[i]);
    console.log("  * publicKey", ret.pubkeyList[i].publicKey);
    console.log("  * pop", ret.pubkeyList[i][1]);
  }
}

export async function sbrVerify(nodeId: string, pubkey: string, pop: string, opts: { file: string }) {
  if (!opts.file && pop == "") {
    throw new Error("Either file or all arguments must be specified");
  }

  if (opts.file) {
    const keyInfo: BlsPublicInfoFile = JSON.parse(fs.readFileSync(opts.file, "utf-8"));
    ({ pop, publicKey: pubkey } = keyInfo.blsPublicKeyInfo);
    ({ address: nodeId } = keyInfo);
    pubkey = "0x" + pubkey;
    pop = "0x" + pop;
  } else {
    if (!pubkey.startsWith("0x") || !pop.startsWith("0x")) {
      throw new Error("pubkey and pop must start with 0x");
    }
  }

  if (Buffer.from(pubkey.substring(2), "hex").length != 48) {
    throw new Error("pubkey must be 48 bytes");
  }

  if (Buffer.from(pop.substring(2), "hex").length != 96) {
    throw new Error("pop must be 96 bytes");
  }

  if (!(await validatePop(pubkey, pop))) {
    throw new Error("pop validation failed");
  }

  console.log("Verification pass");
}

export async function sbrRegister(nodeId: string, pubkey: string, pop: string, opts: { file: string }) {
  await sbrVerify(nodeId, pubkey, pop, opts);

  const sbr = await getSBR();
  const tx = await sbr.register(nodeId, pubkey, pop);
  await tx.wait();
  console.log(`Registered: ${nodeId}, ${pubkey}, ${pop}`);
}

export async function sbrUnregister(nodeId: string) {
  const sbr = await getSBR();
  const tx = await sbr.unregister(nodeId);
  await tx.wait();
  console.log(`Unregistered: ${nodeId}`);
}
