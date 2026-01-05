import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { upgrades } from "hardhat";
import { env } from "../../hardhat.config";

const name = "ValidatorManager";

interface NodeIds {
  maanger: string;
  consensusNodeId: string;
  nodeIds: string[];
}

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments } = hre;
  const { save, getExtendedArtifact } = deployments;

  const owner = env?.["VALIDATOR_MANAGER_OWNER"];
  if (!owner) {
    throw new Error("Missing environment variables");
  }

  const ValidatorManager = await hre.ethers.getContractFactory(name);

  // Before deploying system contract, validate the contract.
  try {
    await upgrades.validateImplementation(ValidatorManager, { kind: "uups" });
  } catch (e) {
    throw new Error(`Invalid ValidatorManager implementation contract: ${e}`);
  }

  /// @note: set correct initial manager and node ids when deployment
  const nodeIds: NodeIds[] = [];
  const proxy = await upgrades.deployProxy(ValidatorManager, [owner, nodeIds], {
    initializer: "initialize",
    kind: "uups",
  });

  console.log(`${name} deployed at ${proxy.target}`);

  const artifacts = await getExtendedArtifact(name);
  save(name, {
    address: await proxy.getAddress(),
    ...artifacts,
  });
};

func.tags = [name];
export default func;
