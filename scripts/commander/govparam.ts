import { getGovParam } from "../utils/govParam";
import { provider } from "../utils/config";
import _ from "lodash";

const DefaultParams = {
  "governance.governancemode": "0x6e6f6e65", // "none"
  "governance.governingnode": "0x0000000000000000000000000000000000000000",
  "governance.unitprice": 25000000000,
  "istanbul.committeesize": 21,
  "istanbul.epoch": 10,
  "istanbul.policy": 0,
  "reward.deferredtxfee": "0x00", // false
  "reward.minimumstake": "0x32303030303030", // "2000000"
  "reward.mintingamount": "0x39363030303030303030303030303030303030", // "9600000000000000000"
  "reward.proposerupdateinterval": 3600,
  "reward.ratio": "0x3130302f302f30", // "100/0/0"
  "reward.stakingupdateinterval": 86400,
  "reward.useginicoeff": "0x00", // false
};

export async function getOwner() {
  const govParam = await getGovParam();
  const owner = await govParam.owner();
  console.log(`Owner: ${owner}`);
}

export async function gpTransferOwnership(newOwner: string) {
  const govParam = await getGovParam();
  const tx = await govParam.transferOwnership(newOwner);
  await tx.wait();
  console.log(`Transferred ownership to ${newOwner}`);
}

export async function getAllParamNames() {
  const govParam = await getGovParam();
  const names = await govParam.getAllParamNames();
  console.log(`All param names: ${names}`);
}

export async function getParamAt(name: string, blockNumber: number | string) {
  const govParam = await getGovParam();
  if (blockNumber == "latest") {
    blockNumber = await provider.getBlockNumber();
  }
  const param = await govParam.getParamAt(name, blockNumber);
  console.log(`Param ${name} at block ${blockNumber}: ${param[1]}`);
}

export async function getAllParamsAt(blockNumber: number | string) {
  const govParam = await getGovParam();
  if (blockNumber == "latest") {
    blockNumber = await provider.getBlockNumber();
  }
  const [names, values] = await govParam.getAllParamsAt(blockNumber);
  for (let i = 0; i < names.length; i++) {
    console.log(`${names[i]}: ${values[i]}`);
  }
}

export async function getCheckpoint(name: string) {
  const govParam = await getGovParam();
  const ckpts = await govParam.checkpoints(name);
  if (ckpts.length == 0) {
    console.log(`no checkpoint for ${name}`);
    return;
  }

  console.log(`${name} checkpoints`);
  const padlen = ckpts[ckpts.length - 1][0].toString().length;
  for (const ckpt of ckpts) {
    const [activation, exists, val] = ckpt;
    let valmsg = "";
    if (exists) {
      valmsg = `val=${val}`;
    }
    console.log(`  #${activation.toString().padEnd(padlen)}: exists=${exists} ${valmsg}`);
  }
}

export async function getAllCheckpoints() {
  const govParam = await getGovParam();
  const [names, ckptss] = await govParam.getAllCheckpoints();
  if (ckptss.length == 0) {
    console.log("there are no parameters in GovParam");
    return;
  }

  for (const [name, ckpts] of _.zip(names, ckptss)) {
    if (ckpts == undefined || (ckpts as any[]).length == 0) {
      console.log(`no checkpoint for ${name}`);
      continue;
    }
    const ckptsArray = ckpts as any[];

    console.log(`${name} checkpoints`);
    const padlen = ckptsArray[ckptsArray.length - 1][0].toString().length;
    for (const ckpt of ckptsArray) {
      const [activation, exists, val] = ckpt;
      let valmsg = "";
      if (exists) {
        valmsg = `val=${val}`;
      }
      console.log(`  #${activation.toString().padEnd(padlen)}: exists=${exists} ${valmsg}`);
    }
  }
}

export async function setParam(name: string, exists: boolean, value: any, block: string) {
  const govParam = await getGovParam();

  if (value.length == 0 && name in DefaultParams) {
    value = DefaultParams[name as keyof typeof DefaultParams];
  }
  if (typeof value == "string" && !value.startsWith("0x")) {
    value = parseInt(value);
  }
  if (block == undefined) {
    block = "+10";
  }

  if (block.startsWith("+")) {
    await govParam.setParamIn(name, exists, value, parseInt(block));
    console.log(`Set ${name} to ${value} in ${block} blocks`);
  } else {
    await govParam.setParam(name, exists, value, parseInt(block));
  }
}
