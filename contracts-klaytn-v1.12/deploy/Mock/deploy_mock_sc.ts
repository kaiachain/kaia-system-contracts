import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { upgrades } from "hardhat";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const MockUpgradeableSystemContract = await hre.ethers.getContractFactory("MockUpgradeableSystemContract");

  // Before deploying system contract, validate the contract.
  try {
    await upgrades.validateImplementation(MockUpgradeableSystemContract, { kind: "uups" });
  } catch (e) {
    throw new Error("Invalid implementation contract");
  }

  const proxy = await upgrades.deployProxy(MockUpgradeableSystemContract, [3], {
    initializer: "initialize",
    kind: "uups",
  });

  console.log("System contract has been successfully deployed to:", proxy.target);
};

func.tags = ["MockUpgradeableSystemContract"];
export default func;
