import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const name = "GovParam";

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  const res = await deployments.deploy(name, {
    from: deployer,
    args: [],
    log: true,
  });

  console.log(`${name} deployed at ${res.address}`);
};

func.tags = [name];
export default func;
