import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { env } from "../hardhat.config";

const name = "Lockup";

const func: DeployFunction = async ({ deployments, getNamedAccounts }: HardhatRuntimeEnvironment) => {
  const { deployer } = await getNamedAccounts();

  const adminAddr = env?.["LOCKUP_ADMIN_ADDRESS"];
  const secretaryAddr = env?.["LOCKUP_SECRETARY_ADDRESS"];

  const res = await deployments.deploy(name, {
    from: deployer,
    args: [adminAddr, secretaryAddr],
    log: true,
  });

  console.log(`${name} deployed at ${res.address}`);

  // Use below constructor arguments for verification on block explorer
  console.log(`Constructor arguments of ${name}`);
  console.log([adminAddr, secretaryAddr]);
};

func.tags = [name];
export default func;
