import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { env } from "../hardhat.config";

const name = "HolderVerifier";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const operatorAddr = env?.["HOLDER_VERIFIER_OPERATOR_ADDRESS"];
  if (!operatorAddr) {
    throw new Error(`Operator address for ${name} is not set`);
  }

  console.log(`Deploying HolderVerifier with operator: ${operatorAddr}`);

  const holderVerifier = await deploy("HolderVerifier", {
    from: deployer,
    args: [operatorAddr],
    log: true,
  });

  console.log(`HolderVerifier deployed at: ${holderVerifier.address}`);
};

func.tags = [name];
export default func;
