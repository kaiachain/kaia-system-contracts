import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const name = "PublicDelegationFactoryV2";

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  // 1. deploy factory
  const factory = await deployments.deploy(name, {
    from: deployer,
    args: [],
    log: true,
  });
  console.log(`${name} deployed at ${factory.address}`);
};

func.tags = [name];
export default func;
