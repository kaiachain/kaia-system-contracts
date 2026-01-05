import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { upgrades } from "hardhat";

const name = "SimpleBlsRegistry";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments } = hre;
  const { save, getExtendedArtifact } = deployments;

  const SimpleBlsRegistry = await hre.ethers.getContractFactory(name);

  // Before deploying system contract, validate the contract.
  try {
    await upgrades.validateImplementation(SimpleBlsRegistry, { kind: "uups" });
  } catch (e) {
    throw new Error("Invalid SBR implementation contract");
  }

  const proxy = await upgrades.deployProxy(SimpleBlsRegistry, [], {
    initializer: "initialize",
    kind: "uups",
  });

  const artifacts = await getExtendedArtifact(name);
  save(name, {
    address: await proxy.getAddress(),
    ...artifacts,
  });

  console.log(`${name} deployed at ${proxy.target}`);
};

func.tags = [name];
export default func;
