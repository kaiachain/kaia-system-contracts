import { loadFixture, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import {
  MockCnStakingOverV2__factory,
  MockCnStakingV1__factory,
  MockERC20,
  MockERC20__factory,
} from "../../typechain-types";
import { jumpBlock, nowBlock, toPeb, registerContract } from "../../helpers/utils";
import { multiCallTestFixture, clRegistryTestFixture } from "../materials";
import { Addressable, parseEther, ZeroAddress } from "ethers";

type UnPromisify<T> = T extends Promise<infer U> ? U : T;

describe("Multicall", function () {
  let multiCallFixture: UnPromisify<ReturnType<typeof multiCallTestFixture>>;
  let fakeWKaia: MockERC20;

  const expectedStakingAmounts = [
    toPeb(3000n),
    toPeb(3000n),
    toPeb(6000n),
    toPeb(9000n),
    toPeb(5000n),
    toPeb(10000n),
    toPeb(15000n),
  ];
  // Test params for CL staking
  const gcId1 = 1;
  const nodeId1 = "0x0000000000000000000000000000000000000001";
  const clPool1 = "0x0000000000000000000000000000000000000002";
  const gcId2 = 2;
  const nodeId2 = "0x0000000000000000000000000000000000000004";
  const clPool2 = "0x0000000000000000000000000000000000000005";

  beforeEach(async function () {
    multiCallFixture = await loadFixture(multiCallTestFixture);

    // Assume that initialization has been done
    const { addressBook, deployer } = multiCallFixture;

    const cn = [];
    const nodeIds = [];
    const rewardAddresses = [];

    // Prepare following CNStaking contracts
    // Note that unstaking amount will be ignored
    // V1: 1 - 3000 KAIA
    // V2: 3 - 3000 KAIA, 6000 KAIA, 9000 KAIA
    //            0 KAIA,  500 KAIA, 1000 KAIA
    // V3: 3 - 5000 KAIA, 10000 KAIA, 15000 KAIA
    //          500 KAIA,  1000 KAIA,  1500 KAIA

    const setupFunction = (contract: any, version: number, address: string | Addressable) => {
      if (version > 1) {
        contract.mockSetVersion(version);
      }
      contract.mockSetNodeId(address);
      contract.mockSetRewardAddress(address);
    };

    const cnV1 = await new MockCnStakingV1__factory(deployer).deploy();
    setupFunction(cnV1, 1, cnV1.target);
    await setBalance(await cnV1.getAddress(), parseEther(3000n.toString()));
    cn.push(cnV1.target);
    nodeIds.push(cnV1.target);
    rewardAddresses.push(cnV1.target);

    for (let i = 0; i < 3; i++) {
      const cnV2 = await new MockCnStakingOverV2__factory(deployer).deploy();
      setupFunction(cnV2, 2, cnV2.target);
      await setBalance(await cnV2.getAddress(), parseEther((3000n * (BigInt(i) + 1n)).toString()));
      cnV2.mockSetStaking(toPeb(3000n * (BigInt(i) + 1n)));
      cnV2.mockSetUnstaking(toPeb(500n * BigInt(i)));
      cn.push(cnV2.target);
      nodeIds.push(cnV2.target);
      rewardAddresses.push(cnV2.target);
    }

    for (let i = 0; i < 3; i++) {
      const cnV3 = await new MockCnStakingOverV2__factory(deployer).deploy();
      setupFunction(cnV3, 3, cnV3.target);
      await setBalance(await cnV3.getAddress(), parseEther((5000n * (BigInt(i) + 1n)).toString()));
      cnV3.mockSetStaking(toPeb(5000n * (BigInt(i) + 1n)));
      cnV3.mockSetUnstaking(toPeb(500n * (BigInt(i) + 1n)));
      cn.push(cnV3.target);
      nodeIds.push(cnV3.target);
      rewardAddresses.push(cnV3.target);
    }

    await addressBook.mockRegisterCnStakingContracts(nodeIds, cn, rewardAddresses);
    await addressBook.submitUpdatePocContract(deployer.address, 1);
    await addressBook.submitUpdateKirContract(deployer.address, 1);

    fakeWKaia = await new MockERC20__factory(deployer).deploy();
  });
  it("Multicall returns staking info", async function () {
    const { addressBook, multiCall } = multiCallFixture;

    await addressBook.activateAddressBook();

    const stakingInfo = await multiCall.multiCallStakingInfo();

    const stakingAmounts = stakingInfo[2];

    for (let i = 0; i < 7; i++) {
      expect(stakingAmounts[i]).to.equal(expectedStakingAmounts[i]);
    }
  });
  it("Mutlcall returns early if AB not activated", async function () {
    const { multiCall } = multiCallFixture;

    const stakingInfo = await multiCall.multiCallStakingInfo();

    const stakingAmounts = stakingInfo[2];

    expect(stakingAmounts).to.have.lengthOf(0);
  });
  it("Multicall returns DP staking info", async function () {
    const { multiCall, registry } = multiCallFixture;
    const { clRegistry } = await clRegistryTestFixture();

    const curBlock = await nowBlock();
    // Enroll a CLRegistry and WrappedKaia contract address
    await registerContract(registry, "CLRegistry", clRegistry.target);
    await registerContract(registry, "WrappedKaia", fakeWKaia.target);

    fakeWKaia.mockSetBalance(clPool1, toPeb(3000n));
    fakeWKaia.mockSetBalance(clPool2, toPeb(10000n));

    // Add a CL pair1
    await expect(clRegistry.addCLPair([{ nodeId: nodeId1, gcId: gcId1, clPool: clPool1 }])).to.emit(
      clRegistry,
      "RegisterPair",
    );
    // Add a CL pair2
    await expect(clRegistry.addCLPair([{ nodeId: nodeId2, gcId: gcId2, clPool: clPool2 }])).to.emit(
      clRegistry,
      "RegisterPair",
    );

    await jumpBlock(curBlock + 100);

    expect(await registry.getActiveAddr("CLRegistry")).to.equal(clRegistry.target);
    expect(await multiCall.multiCallDPStakingInfo()).to.deep.equal([
      [nodeId1, nodeId2],
      [clPool1, clPool2],
      [toPeb(3000n), toPeb(10000n)],
    ]);
  });
  it("Multicall returns DP staking info (no WKaia)", async function () {
    const { multiCall, registry } = multiCallFixture;
    const { clRegistry } = await clRegistryTestFixture();

    const curBlock = await nowBlock();
    // Enroll a CLRegistry contract address but no WrappedKaia
    await registerContract(registry, "CLRegistry", clRegistry.target);

    fakeWKaia.mockSetBalance(clPool1, toPeb(3000n));
    fakeWKaia.mockSetBalance(clPool2, toPeb(10000n));

    // Add a CL pair1
    await expect(clRegistry.addCLPair([{ nodeId: nodeId1, gcId: gcId1, clPool: clPool1 }])).to.emit(
      clRegistry,
      "RegisterPair",
    );
    // Add a CL pair2
    await expect(clRegistry.addCLPair([{ nodeId: nodeId2, gcId: gcId2, clPool: clPool2 }])).to.emit(
      clRegistry,
      "RegisterPair",
    );

    await jumpBlock(curBlock + 100);

    expect(await registry.getActiveAddr("CLRegistry")).to.equal(clRegistry.target);
    expect(await registry.getActiveAddr("WrappedKaia")).to.equal(ZeroAddress);
    expect(await multiCall.multiCallDPStakingInfo()).to.deep.equal([
      [nodeId1, nodeId2],
      [clPool1, clPool2],
      [toPeb(0n), toPeb(0n)], // No WKaia registered in Registry
    ]);
  });
  it("Multicall returns DP staking info (not activated)", async function () {
    const { multiCall, registry } = multiCallFixture;

    expect(await registry.getActiveAddr("CLRegistry")).to.equal(ZeroAddress);
    expect(await multiCall.multiCallDPStakingInfo()).to.deep.equal([[], [], []]);
  });
});
