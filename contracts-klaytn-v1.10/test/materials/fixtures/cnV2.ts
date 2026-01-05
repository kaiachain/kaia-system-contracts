import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { nowTime, toPeb } from "../../../helpers/utils";
import { addressBookFixture } from "../../../helpers/utils";
import { CnStakingV2__factory } from "../../../typechain-types";

export async function cnV2UnitTestFixture() {
  // Load fixture for address book contract
  const { addressBook } = await loadFixture(addressBookFixture);

  // Prepare parameters for deploying contracts
  const now = await nowTime();
  const accounts = await ethers.getSigners();
  const [contractValidator, admin1, admin2, admin3, other1, other2, nodeId, rewardAddr] = accounts.slice(0, 8);
  const adminList = [admin1, admin2, admin3];
  const unLockTimes = [now + 1000, now + 2000];
  const unLockAmounts = [200n, 400n].map((x) => toPeb(x));
  const requirement = 2;
  const gcId = 700;

  // Deploy contracts
  const cnStakingV2 = await new CnStakingV2__factory(contractValidator).deploy(
    contractValidator.address,
    nodeId.address,
    rewardAddr.address,
    adminList.map((x) => x.address),
    requirement,
    unLockTimes,
    unLockAmounts,
  );

  await addressBook.constructContract([contractValidator.address], 1);

  // Register CnStakingV2 contract to AddressBook to use reviseRewardAddress
  await addressBook.registerCnStakingContract(nodeId.address, cnStakingV2.target, rewardAddr.address);

  const stakingTrackerMockReceiver = await ethers.deployContract("StakingTrackerMockReceiver");
  const stakingTrackerMockWrong = await ethers.deployContract("StakingTrackerMockWrong");
  const stakingTrackerMockActive = await ethers.deployContract("StakingTrackerMockActive");

  return {
    contractValidator,
    adminList,
    nodeId,
    rewardAddr,
    other1,
    other2,
    unLockTimes,
    unLockAmounts,
    requirement,
    cnStakingV2,
    addressBook,
    stakingTrackerMockReceiver,
    stakingTrackerMockWrong,
    stakingTrackerMockActive,
    gcId,
  };
}

export async function cnV2ScenarioTestFixture() {
  // Load fixture for address book contract
  const { addressBook } = await loadFixture(addressBookFixture);

  // Prepare parameters for deploying contracts
  const now = await nowTime();
  const accounts = await ethers.getSigners();
  const [contractValidator, admin1, admin2, admin3, admin4, other1, nodeId, rewardAddr] = accounts.slice(0, 9);
  const adminList = [admin1, admin2, admin3, admin4];
  const unLockTimes = [now + 1000, now + 2000];
  const unLockAmounts = [200n, 400n].map((x) => toPeb(x));
  const requirement = 3;
  const gcId = 700;

  // Deploy contracts
  const cnStakingV2 = await new CnStakingV2__factory(contractValidator).deploy(
    contractValidator.address,
    nodeId.address,
    rewardAddr.address,
    adminList.map((x) => x.address),
    requirement,
    unLockTimes,
    unLockAmounts,
  );

  await addressBook.constructContract([contractValidator.address], 1);

  // Register CnStakingV2 contract to AddressBook to use reviseRewardAddress
  await addressBook.registerCnStakingContract(nodeId.address, cnStakingV2.target, rewardAddr.address);

  const stakingTrackerMockReceiver = await ethers.deployContract("StakingTrackerMockReceiver");
  const stakingTrackerMockWrong = await ethers.deployContract("StakingTrackerMockWrong");
  const stakingTrackerMockActive = await ethers.deployContract("StakingTrackerMockActive");

  return {
    contractValidator,
    adminList,
    nodeId,
    rewardAddr,
    other1,
    unLockTimes,
    unLockAmounts,
    requirement,
    cnStakingV2,
    addressBook,
    stakingTrackerMockReceiver,
    stakingTrackerMockWrong,
    stakingTrackerMockActive,
    gcId,
  };
}
