import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { env } from "../hardhat.config";

const name = "StakingTrackerV2";

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  const admin = env?.["STV2_ADMIN_ADDRESS"];

  const res = await deployments.deploy(name, {
    from: deployer,
    args: [admin],
    log: true,
  });

  console.log(`${name} deployed at ${res.address}`);
};

func.tags = [name];
export default func;
