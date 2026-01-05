import { Contract, formatEther } from "ethers";
import { getTreasuryRebalanceV2, provider } from "../utils";

enum RebalanceStatus {
  Initialized,
  Registered,
  Approved,
  Finalized,
}

// npx ts-node script/commander.ts trV2 info
export async function trInfo() {
  const tr = getTreasuryRebalanceV2();
  const zeroedCount = Number(await tr.getZeroedCount());
  const allocatedCount = Number(await tr.getAllocatedCount());
  const status = await tr.status();
  console.log("ContractAddress:", tr.target);
  console.log("Reserves: total ", zeroedCount, "zeroeds, and total ", allocatedCount, "allocateds");
  for (let i = 0; i < zeroedCount; i++) {
    const zeroed = await tr.zeroeds(i);
    const balance = formatEther(await provider.getBalance(zeroed.toString())).toString() + " KLAY";
    console.log(`* Zeroed[${i}]: ${zeroed}, current balance: ${balance}`);
  }
  for (let i = 0; i < allocatedCount; i++) {
    const allocated = await tr.allocateds(i);
    const balance = formatEther(await provider.getBalance(allocated[0].toString())).toString() + " KLAY";
    const allocatedAmount = formatEther(allocated[1]).toString() + " KLAY";
    console.log(
      `* Allocated[${i}]: ${allocated[0]}, current balance: ${balance}, allocated amount: ${allocatedAmount}`,
    );
  }

  console.log("rebalance blocknumber:", Number(await tr.rebalanceBlockNumber()));
  console.log("current blockchain number:", await provider.getBlockNumber());
  console.log("status:", RebalanceStatus[Number(status)]);
  try {
    console.log(`pendingMemo: "${await tr.pendingMemo()}"`);
  } catch (error: any) {
    console.log(`pendingMemo: Doesn't support pendingMemo method.`);
  }
  if (Number(status) === RebalanceStatus.Finalized) {
    console.log(`memo: "${await tr.memo()}"`);
  }
}

// npx ts-node script/commander.ts trV2 register zeroed "0xAddress"
// npx ts-node script/commander.ts trV2 register allocated "0xAddress" --amount amountInPeb
export async function trRegister(type: string, address: string, opts: { amount?: number }) {
  const tr = getTreasuryRebalanceV2();
  let tx: any;
  try {
    if (type === "zeroed") {
      tx = await tr.registerZeroed(address);
    } else if (type === "allocated") {
      if (opts.amount === undefined) {
        throw new Error("Amount is required for registerAllocated");
      }
      tx = await tr.registerAllocated(address, opts.amount);
    } else {
      throw new Error(`wrong type ${type}`);
    }
  } catch (error: any) {
    if (error.reason === undefined) {
      throw new Error(`${error}`);
    }
    throw new Error(`${error.reason}`);
  }
  const receipt = await tx.wait();
  receipt.events?.forEach((event: any) => {
    console.log(`successfully registered ${type} ${address}.`);
    console.log(`Txhash is ${tx.hash}. Event:`, event.event, event.args[0]);
  });
}

// npx ts-node script/commander.ts trV2 remove zeroed "0xAddress"
// npx ts-node script/commander.ts trV2 remove allocated "0xAddress"
export async function trRemove(type: string, address: string) {
  const tr = getTreasuryRebalanceV2();
  let tx: any;
  try {
    if (type === "zeroed") {
      tx = await tr.removeZeroed(address);
    } else if (type === "allocated") {
      tx = await tr.removeAllocated(address);
    }
  } catch (error: any) {
    if (error.reason === undefined) {
      throw new Error(`${error}`);
    }
    throw new Error(`${error.reason}`);
  }
  const receipt = await tx.wait();
  receipt.events?.forEach((event: any) => {
    console.log(`successfully removed ${type} ${address}.`);
    console.log(`Txhash is ${tx.hash}. Event:`, event.event, event.args[0]);
  });
}

// npx ts-node script/commander.ts trV2 approve "0xAddress"
export async function trApprove(address: string) {
  const tr = getTreasuryRebalanceV2();
  let tx: any;
  try {
    tx = await tr.approve(address);
  } catch (error: any) {
    if (error.reason === undefined) {
      throw new Error(`${error}`);
    }
    throw new Error(`${error.reason}`);
  }
  const receipt = await tx.wait();
  receipt.events?.forEach((event: any) => {
    console.log(`successfully approved ${address}.`);
    console.log(`Txhash is ${tx.hash}. Event:`, event.event, event.args[0]);
  });
}

// npx ts-node script/commander.ts trV2 finalize registration
// npx ts-node script/commander.ts trV2 finalize approval
// npx ts-node script/commander.ts trV2 finalize contract
export async function trFinalize(finalize: string) {
  const tr = getTreasuryRebalanceV2();
  let tx: any;
  try {
    if (finalize === "registration") {
      tx = await tr.finalizeRegistration();
    } else if (finalize === "approval") {
      tx = await tr.finalizeApproval();
    } else if (finalize === "contract") {
      if ((await provider.getNetwork()).chainId.toString() === "1001") {
        throw new Error(`This command doesn't support TRv2 deployed on Baobab.`);
      }
      tx = await tr.finalizeContract();
    } else {
      throw new Error(`wrong status ${finalize}`);
    }
  } catch (error: any) {
    if (error.reason === undefined) {
      throw new Error(`${error}`);
    }
    throw new Error(`${error.reason}`);
  }
  const receipt = await tx.wait();
  receipt.events?.forEach((event: any) => {
    console.log(`successfully finalize ${finalize}.`);
    if (finalize === "contract") {
      console.log(`Txhash is ${tx.hash}. Event: ${RebalanceStatus[event.args[1]]}, memo - "${event.args[0]}"`);
    } else {
      console.log(`Txhash is ${tx.hash}. Event: ${event.event} ${RebalanceStatus[event.args[0]]}`);
    }
  });
}

async function isMemoCorrect(tr: Contract, pendingMemo: string): Promise<Error | null> {
  // convert bigint into string
  pendingMemo = pendingMemo.replace(/:\s*(-?\d+(\.\d+)?(e[+-]?\d+)?)/g, ': "$1"');

  // parse pendingMemo into jsonPendingMemo
  const jsonPendingMemo = JSON.parse(pendingMemo);
  const { before, after, burnt, success } = jsonPendingMemo;

  if (before === undefined || after === undefined || burnt === undefined || success === undefined) {
    return new Error(`missing fields in pendingMemo`);
  }
  let burntAmount = BigInt(0);
  async function processEntries(type: "zeroed" | "allocated"): Promise<Error | null> {
    let count, getter;
    if (type === "zeroed") {
      count = Number(await tr.getZeroedCount());
      getter = async (index: number): Promise<string> => (await tr.zeroeds(index)).toLowerCase();
    } else {
      // type ==='allocated'
      count = Number(await tr.getAllocatedCount());
      getter = async (index: number): Promise<string> => (await tr.allocateds(index))[0].toLowerCase();
    }
    for (let i = 0; i < count; i++) {
      const address = await getter(i);
      const beforeValue = before[type][address];
      const afterValue = after[type][address];
      if (beforeValue === undefined) {
        return new Error(`missing ${type} before value for address ${address}`);
      }
      if (afterValue === undefined) {
        return new Error(`missing ${type} after value for address ${address}`);
      }
      burntAmount += BigInt(beforeValue) - BigInt(afterValue);
    }
    return null;
  }

  let error: Error | null;
  error = await processEntries("zeroed");
  if (error) return error;
  error = await processEntries("allocated");
  if (error) return error;

  if (burntAmount.toString() !== burnt.toString()) {
    return new Error(`wrong burnt amount, calculated: ${burntAmount.toString()}, memo[burnt]: ${burnt.toString()}`);
  }
  console.log(`correct burnt amount, calculated: ${burntAmount.toString()}, memo[burnt]: ${burnt.toString()}`);
  return null;
}

// npx ts-node script/commander.ts trV2 setPendingMemo "memo"
export async function trSetPendingMemo(pendingMemo: string) {
  if ((await provider.getNetwork()).chainId.toString() === "1001") {
    throw new Error(`This command doesn't support TRv2 deployed on Baobab.`);
  }
  // (1) check the memo is correctly formatted
  const tr = getTreasuryRebalanceV2();
  const error = await isMemoCorrect(tr, pendingMemo);
  if (error !== null) {
    throw error;
  }

  // (2) send setPendingMemo transaction
  let tx: any;
  try {
    tx = await tr.setPendingMemo(pendingMemo);
  } catch (error: any) {
    if (error.reason === undefined) {
      throw new Error(`${error}`);
    }
    throw new Error(`${error.reason}`);
  }
  const receipt = await tx.wait();
  if (receipt.status == 1) {
    console.log(`successfully setPendingMemo "${pendingMemo}".`);
    console.log(`Txhash is ${tx.hash}`);
    console.log(`get pendingMemo: "${await tr.pendingMemo()}"`);
  } else {
    console.log(`Tx Failed. Check the receipt.`);
  }
}

// npx ts-node script/commander.ts trV2 updateRebalanceBN "newBN"
export async function trUpdateRebalanceBN(newBN: number) {
  const tr = getTreasuryRebalanceV2();
  let tx: any;
  try {
    tx = await tr.updateRebalanceBlocknumber(newBN);
  } catch (error: any) {
    if (error.reason === undefined) {
      throw new Error(`${error}`);
    }
    throw new Error(`${error.reason}`);
  }
  const receipt = await tx.wait();
  if (receipt.status == 1) {
    console.log(`successfully updated rebalance blocknumber to ${newBN}.`);
    console.log(`Txhash is ${tx.hash}`);
    console.log(`get updated rebalance blocknumber: `, Number(await tr.rebalanceBlockNumber()));
  } else {
    console.log(`Tx Failed. Check the receipt.`);
  }
}

// npx ts-node script/commander.ts trV2 reset
export async function trReset() {
  const tr = getTreasuryRebalanceV2();
  let tx: any;
  try {
    tx = await tr.reset();
  } catch (error: any) {
    if (error.reason === undefined) {
      throw new Error(`${error}`);
    }
    throw new Error(`${error.reason}`);
  }
  const receipt = await tx.wait();
  if (receipt.status == 1) {
    console.log(`successfully reset the rebalance contract.`);
    console.log(`Txhash is ${tx.hash}`);
    console.log(`---Print trV2 info---`);
    await trInfo();
  } else {
    console.log(`Tx Failed. Check the receipt.`);
  }
}

export async function trTransferOwnership(address: string) {
  const tr = getTreasuryRebalanceV2();
  const tx = await tr.transferOwnership(address);
  await tx.wait();
  console.log(`Transferred ownership to ${address}`);
}
