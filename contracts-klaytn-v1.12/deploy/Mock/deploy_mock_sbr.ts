import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { upgrades } from "hardhat";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const SimpleBlsRegistryMock = await hre.ethers.getContractFactory("SimpleBlsRegistryMock");

  // Before deploying system contract, validate the contract.
  try {
    await upgrades.validateImplementation(SimpleBlsRegistryMock, { kind: "uups" });
  } catch (e) {
    throw new Error("Invalid SBR implementation contract");
  }

  const proxy = await upgrades.deployProxy(SimpleBlsRegistryMock, [], {
    initializer: "initialize",
    kind: "uups",
  });

  console.log("MockSBR contract has been successfully deployed to:", proxy.target);
};

func.tags = ["SimpleBlsRegistryMock"];
export default func;
