import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { env } from "../hardhat.config";

const name = "TreasuryRebalance";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;

  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const bn = env?.["KIP103_REBALANCE_BLOCKNUMBER"];
  if (!bn) {
    throw new Error(`Block number for ${name} is not set`);
  }

  const res = await deploy(name, {
    from: deployer,
    args: [bn],
    //deterministicDeployment: true,
    log: true,
  });

  console.log(`${name} deployed at ${res.address}`);

  // Use below constructor arguments for verification on block explorer
  console.log(`Constructor arguments of ${name}`);
  console.log([bn]);
};

func.tags = [name];
export default func;
