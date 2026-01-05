import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { env } from "../hardhat.config";

const name = "CLRegistry";

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  let owner = "";
  if (process.env.OWNER) {
    owner = process.env.OWNER;
  } else if (env?.["OWNER"]) {
    owner = env?.["OWNER"];
  } else {
    throw new Error("No owner address provided. Set `OWNER=address` in environment variables");
  }

  const res = await deployments.deploy(name, {
    from: deployer,
    args: [owner],
    deterministicDeployment: true,
    log: true,
  });

  console.log(`${name} deployed at ${res.address}`);
};

func.tags = [name];
export default func;
