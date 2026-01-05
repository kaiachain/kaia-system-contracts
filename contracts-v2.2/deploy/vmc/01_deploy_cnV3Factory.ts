import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const name = "CnStakingV3MultiSigFactory";

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  // 1. deploy chunk1, chunk2
  const chunk1 = await deployments.deploy("CnStakingV3MultiSigChunk1", {
    from: deployer,
    args: [],
    log: true,
  });
  const chunk2 = await deployments.deploy("CnStakingV3MultiSigChunk2", {
    from: deployer,
    args: [],
    log: true,
  });

  // 2. deploy factory
  const factory = await deployments.deploy(name, {
    from: deployer,
    args: [chunk1.address, chunk2.address],
    log: true,
  });
  console.log(`${name} deployed at ${factory.address}`);
};

func.tags = [name];
export default func;
