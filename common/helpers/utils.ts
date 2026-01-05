import { setCode } from "@nomicfoundation/hardhat-network-helpers";
import { expect, Assertion } from "chai";
import { ethers } from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { parseEther, formatEther, hexlify, zeroPadValue, toBeHex } from "ethers";
import { Contract, BytesLike, Addressable } from "ethers";
import { Signer } from "ethers";
import _ from "lodash";
import hre from "hardhat";

export const DIRTY = parseEther("0.001");
export const ABOOK_ADDRESS = "0x0000000000000000000000000000000000000400";
export const REGISTRY_ADDRESS = "0x0000000000000000000000000000000000000401";

export const DAY = 24 * 60 * 60;
export const WEEK = 7 * DAY;

// Generic type for CnStaking contracts (CnStakingContract, CnStakingV2, CnStakingV3, etc.)
// Each package can use their specific typechain types when calling these functions
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type CnStaking = Contract & { connect: (signer: Signer) => any };

const million = (num: number) => parseEther((num * 1_000_000).toString());
export const MILLIONS = {
  TWO: million(2),
  THREE: million(3),
  FOUR: million(4),
  FIVE: million(5),
  SIX: million(6),
  EIGHT: million(8),
  NINE: million(9),
  TEN: million(10),
  ELEVEN: million(11),
} as const;

export const FuncID = {
  Unknown: 0,
  AddAdmin: 1,
  DeleteAdmin: 2,
  UpdateRequirement: 3,
  ClearRequest: 4,
  WithdrawLockupStaking: 5,
  ApproveStakingWithdrawal: 6,
  CancelApprovedStakingWithdrawal: 7,
  UpdateRewardAddress: 8,
  UpdateStakingTracker: 9,
  UpdateVoterAddress: 10,
};
export const FuncIDV3 = { ...FuncID, ToggleRedelegation: 11 };

export const RequestState = {
  Unknown: 0,
  NotConfirmed: 1,
  Executed: 2,
  ExecutionFailed: 3,
  Canceled: 4,
};
export const WithdrawalState = {
  Unknown: 0,
  Transferred: 1,
  Canceled: 2,
};

export type CnStakingFixture = {
  contractValidator: Signer;
  nodeId: Signer;
  rewardAddr: Signer;
  adminList: Signer[];
  requirement: number;
  unLockTimes: number[];
  unLockAmounts: string[];
  stakingTrackerAddr?: string;
  gcId?: number;
};

export const VoteChoice = {
  No: 0,
  Yes: 1,
  Abstain: 2,
};

export type tx = {
  target: string;
  value: string;
  calldata: BytesLike;
};

export enum Actions {
  txSimpleTransfer100KLAY,
  txSimpleTransfer200KLAY,
  txUpdateStakingTracker,
  txUpdateSecretary,
  txUpdateAccessRule,
  txUpdateTimingRule,
  txUpdateAccessRuleWrong,
  txUpdateTimingRuleWrong,
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function submitRequest(cnStaking: CnStaking, funcId: number, proposer: Signer, args: any[]) {
  switch (funcId) {
    case FuncID.AddAdmin:
      return await cnStaking.connect(proposer).submitAddAdmin(args[0]);
    case FuncID.DeleteAdmin:
      return await cnStaking.connect(proposer).submitDeleteAdmin(args[0]);
    case FuncID.UpdateRequirement:
      return await cnStaking.connect(proposer).submitUpdateRequirement(args[0]);
    case FuncID.ClearRequest:
      return await cnStaking.connect(proposer).submitClearRequest();
    case FuncID.WithdrawLockupStaking:
      return await cnStaking.connect(proposer).submitWithdrawLockupStaking(args[0], args[1]);
    case FuncID.ApproveStakingWithdrawal:
      return await cnStaking.connect(proposer).submitApproveStakingWithdrawal(args[0], args[1]);
    case FuncID.CancelApprovedStakingWithdrawal:
      return await cnStaking.connect(proposer).submitCancelApprovedStakingWithdrawal(args[0]);
    case FuncID.UpdateRewardAddress:
      return await cnStaking.connect(proposer).submitUpdateRewardAddress(args[0]);
    case FuncID.UpdateStakingTracker:
      return await cnStaking.connect(proposer).submitUpdateStakingTracker(args[0]);
    case FuncID.UpdateVoterAddress:
      return await cnStaking.connect(proposer).submitUpdateVoterAddress(args[0]);
    default:
      throw new Error("Invalid funcId");
  }
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function confirmRequests(cnStaking: CnStaking, confirmers: Signer[], args: any[]) {
  for (let i = 0; i < confirmers.length; i++) {
    await cnStaking
      .connect(confirmers[i])
      .confirmRequest(args[0], args[1], toBytes32(args[2]), toBytes32(args[3]), toBytes32(args[4]));
  }
}

export async function registerVoter(cnStakingV2: CnStaking, admin: Signer, voter: Signer) {
  await submitAndExecuteRequest(cnStakingV2, [admin], 1, FuncID.UpdateVoterAddress, admin, [
    0,
    FuncID.UpdateVoterAddress,
    await voter.getAddress(),
    0,
    0,
  ]);
}

export async function submitAndExecuteRequest(
  cnStaking: CnStaking,
  adminList: Signer[],
  requirement: number,
  funcId: number,
  proposer: Signer,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  args: any[],
) {
  await submitRequest(cnStaking, funcId, proposer, args.slice(2, 5));
  if (requirement === 1) {
    return;
  }

  let cnt = 0;
  let i = 0;
  const confirmers = [] as Signer[];
  while (cnt < requirement - 1) {
    if (adminList[i] !== proposer) {
      confirmers.push(adminList[i]);
      cnt++;
    }
    i++;
  }
  await confirmRequests(cnStaking, confirmers, args);
}

export const gcId = [1, 2];
export const unlockTime = [100000000000, 200000000000];
export const unlockAmount = [100, 200];

export async function addressBookFixture() {
  const addressBook = await deployAddressBook();
  return {
    addressBook,
  };
}

export async function deployAddressBook(kind = "AddressBookMock") {
  const kinds = ["AddressBookMock", "AddressBookMockThreeCN", "AddressBookMockOneCN"];
  for (const k of kinds) {
    if (k === kind) {
      await setCodeAt(k, ABOOK_ADDRESS);
      return await ethers.getContractAt(k, ABOOK_ADDRESS);
    }
  }
  await setCodeAt(kinds[0], ABOOK_ADDRESS);
  return await ethers.getContractAt(kinds[0], ABOOK_ADDRESS);
}

export async function deployRegistry() {
  await setCodeAt("Registry", REGISTRY_ADDRESS);
  return await ethers.getContractAt("Registry", REGISTRY_ADDRESS);
}

export async function specialContractsFixture() {
  const addressBook = await deployAddressBook();
  const registry = await deployRegistry();
  return { addressBook, registry };
}

export async function setRegistryOwner(owner: string) {
  await hre.network.provider.request({
    method: "hardhat_setStorageAt",
    params: [REGISTRY_ADDRESS, "0x" + Number(2).toString(16), padUtils(owner, 32)],
  });
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function registerContract(registry: any, name: string, address: string | Addressable) {
  const now = await nowBlock();
  await registry.register(name, address, now + 2);
}

export async function deployAndInitStakingContract(version: number, args: CnStakingFixture): Promise<Contract> {
  let stakingContract: Contract;

  if (version === 1) {
    const cnStakingV1 = await ethers.deployContract("CnStakingContract", [
      await args.contractValidator.getAddress(),
      await args.nodeId.getAddress(),
      await args.rewardAddr.getAddress(),
      await Promise.all(args.adminList.map((admin) => admin.getAddress())),
      args.requirement,
      args.unLockTimes,
      args.unLockAmounts,
    ]);
    stakingContract = cnStakingV1;
  } else if (version === 2) {
    if (!args.stakingTrackerAddr || !args.gcId) {
      throw new Error("stakingTrackerAddr and gcId are required for CnStakingV2");
    }

    const cnStakingV2 = await ethers.deployContract("CnStakingV2", [
      await args.contractValidator.getAddress(),
      await args.nodeId.getAddress(),
      await args.rewardAddr.getAddress(),
      await Promise.all(args.adminList.map((admin) => admin.getAddress())),
      args.requirement,
      args.unLockTimes,
      args.unLockAmounts,
    ]);
    stakingContract = cnStakingV2;

    await (cnStakingV2 as Contract & { connect: (s: Signer) => { setStakingTracker: (addr: string) => Promise<void> } })
      .connect(args.adminList[0])
      .setStakingTracker(args.stakingTrackerAddr);

    await (cnStakingV2 as Contract & { connect: (s: Signer) => { setGCId: (id: number) => Promise<void> } })
      .connect(args.adminList[0])
      .setGCId(args.gcId);
  } else {
    throw new Error("Invalid version");
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (stakingContract as any).connect(args.contractValidator).reviewInitialConditions();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (stakingContract as any).connect(args.adminList[0]).reviewInitialConditions();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  await (stakingContract as any).connect(args.adminList[0]).depositLockupStakingAndInit({ value: toPeb(6_000_000n) });

  return stakingContract;
}

export async function getRuntimecode(name: string): Promise<string> {
  const Factory = await ethers.getContractFactory(name);
  const contract = await Factory.deploy();
  return await ethers.provider.getCode(contract.getAddress());
}

export async function setCodeAt(name: string, addr: string) {
  const runtimeCode = await getRuntimecode(name);
  await setCode(addr, runtimeCode);
}

export async function getMiner() {
  const block = await hre.network.provider.send("eth_getBlockByNumber", ["latest", false]);
  return ethers.getAddress(block.miner);
}

// Time related
export async function nowBlock() {
  return parseInt(await hre.network.provider.send("eth_blockNumber"));
}

export async function nowTime() {
  // hardhat simulated node has separate timer that increases every time
  // a new block is mined (which is basically every transaction).
  // Therefore nowTime() != Date.now().
  const block = await hre.network.provider.send("eth_getBlockByNumber", ["latest", false]);
  return parseInt(block.timestamp);
}

export async function setBlock(num: number) {
  const now = await nowBlock();
  if (now < num) {
    const blocksToMine = "0x" + (num - now).toString(16);
    await hre.network.provider.send("hardhat_mine", [blocksToMine]);
  }
}

export async function setTime(timestamp: number) {
  // https://ethereum.stackexchange.com/questions/86633/time-dependent-tests-with-hardhat
  await hre.network.provider.send("evm_mine", [timestamp]);
}

export async function addTime(time: number) {
  await hre.network.provider.send("evm_increaseTime", [time]);
  await hre.network.provider.send("evm_mine", []);
}

// Query chain
export async function getBalance(address: string) {
  const hex = await hre.network.provider.send("eth_getBalance", [address]);
  return BigInt(hex).toString();
}

// Data conversion
export function toPeb(klay: bigint | number) {
  return parseEther(klay.toString()).toString();
}

export function toKlay(peb: bigint) {
  return formatEther(peb);
}

export function toShares(klay: bigint) {
  return BigInt(toPeb(klay)) * 10n ** 18n;
}

export function toBytes32(x: unknown) {
  if (typeof x === "number" || typeof x === "bigint") {
    x = toBeHex(x);
  }

  try {
    return zeroPadValue(x as string, 32).toLowerCase();
    // eslint-disable-next-line no-empty
  } catch {}

  return x;
}

export function padUtils(value: string | BytesLike, length: number) {
  return hexlify(zeroPadValue(hexlify(value), length));
}

export function numericAddr(n: number, m: number) {
  // Return a human-friendly address to be used as placeholders.
  // ex. CN #42, second node ID is:
  // numericAddr(42, 2) => 0x4202000000000000000000000000000000000001
  const a = n < 10 ? "0" + n : "" + n;
  const b = m < 10 ? "0" + m : "" + m;
  return "0x" + a + b + "00".repeat(17) + "01";
}

export async function jumpTime(time: number, mine = true) {
  await ethers.provider.send("evm_increaseTime", [time]);
  if (mine) {
    await ethers.provider.send("evm_mine", []);
  }
}

export async function jumpBlock(num: number) {
  if (num > 0) {
    const blocksToMine = "0x" + num.toString(16);
    await hre.network.provider.send("hardhat_mine", [blocksToMine]);
  }
}

/* ========== TESTING HELPERS ========== */
// declare global to add custom properties in typescript
declare global {
  export namespace Chai {
    interface Assertion {
      equalAddrList(arr: string[]): void;
      equalStrList(arr: string[]): void;
      equalNumberList(arr: bigint[] | string[] | number[]): void;
      equalBooleanList(arr: boolean[]): void;
    }
  }
}

// Augment chai expect(..) assertion
// - .to.equal(..) with more generous type check
// - .to.emit(..) for CnStaking specific events
export function augmentChai() {
  Assertion.addMethod("equalAddrList", function (arr) {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    arr = _.map(arr, (elem: any) => elem.address || elem);
    const expected = _.map(arr, (elem) => elem.toLowerCase());
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const actual = _.map(this._obj as any[], (elem) => elem.toLowerCase());
    return this.assert(
      _.isEqual(expected, actual),
      "expected #{this} to be equal to #{arr}",
      "expected #{this} to not equal to #{arr}",
      expected,
      actual,
    );
  });
  Assertion.addMethod("equalStrList", function (arr) {
    const expected = _.map(arr, (elem) => elem.toLowerCase());
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const actual = _.map(this._obj as any[], (elem) => elem.toLowerCase());
    return this.assert(
      _.isEqual(expected, actual),
      "expected #{this} to be equal to #{arr}",
      "expected #{this} to not equal to #{arr}",
      expected,
      actual,
    );
  });
  Assertion.addMethod("equalNumberList", function (arr) {
    const expected = _.map(arr, (elem) => elem.toString());
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const actual = _.map(this._obj as any[], (elem) => elem.toString());
    return this.assert(
      _.isEqual(expected, actual),
      "expected #{this} to be equal to #{arr}",
      "expected #{this} to not equal to #{arr}",
      expected,
      actual,
    );
  });
  Assertion.addMethod("equalBooleanList", function (arr) {
    const expected = arr;
    const actual = this._obj;
    return this.assert(
      _.isEqual(expected, actual),
      "expected #{this} to be equal to #{arr}",
      "expected #{this} to not equal to #{arr}",
      expected,
      actual,
    );
  });
}

export async function getContractFromDeployment(hre: HardhatRuntimeEnvironment, name: string) {
  const Dep = await hre.deployments.get(name);
  const code = await hre.ethers.provider.send("eth_getCode", [Dep.address, "latest"]);
  if (code === "0x") {
    // when local network is reset
    throw new Error("deployment found but code is empty");
  }
  return await hre.ethers.getContractAt(Dep.abi, Dep.address);
}

// Modifier failure messages
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function onlyAdminFail(tx: any) {
  await expectRevert(tx, "Address is not admin.");
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function onlyAccessControlFail(tx: any, contract: any) {
  await expectCustomRevert(tx, contract, "AccessControlUnauthorizedAccount");
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function notNullFail(tx: any) {
  await expectRevert(tx, "Address is null");
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function notNullFailWithPoint(tx: any) {
  await expectRevert(tx, "Address is null.");
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function notConfirmedRequestFail(tx: any) {
  await expectRevert(tx, "Must be at not-confirmed state.");
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function beforeInitFail(tx: any) {
  await expectRevert(tx, "Contract has been initialized.");
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function afterInitFail(tx: any) {
  await expectRevert(tx, "Contract is not initialized.");
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function expectRevert(expr: any, message: string | RegExp) {
  return expect(expr).to.be.rejectedWith(message);
}
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function expectCustomRevert(expr: any, contract: Contract, message: string) {
  return expect(expr).to.be.rejectedWith(message);
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function checkRequestInfo(expected: any, returned: any) {
  expect(returned[0]).to.equal(expected[0]);
  expect(returned[1]).to.equal(expected[1]);
  expect(returned[2]).to.equal(expected[2]);
  expect(returned[3]).to.equal(expected[3]);
  expect(returned[4]).to.equal(expected[4]);
  expect(returned[5]).to.equalAddrList(expected[5]);
  expect(returned[6]).to.equal(expected[6]);
}

export type typeDataArgs = {
  chainId: bigint;
  dao: string;
  proposalId: bigint;
  choice: bigint;
  nonce: bigint;
};
