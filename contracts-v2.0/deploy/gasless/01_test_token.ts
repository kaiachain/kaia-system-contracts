import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { importDeployment } from "../../helpers/utils";

const name = "TestToken";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getChainId, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();
  if (chainId == "1001") {
    await importDeployment(hre, name, "0xcB00BA2cAb67A3771f9ca1Fa48FDa8881B457750");
    return;
  }

  await deploy(name, {
    from: deployer,
    args: [deployer],
    log: true,
    deterministicDeployment: true,
  });
};
func.tags = [name, "Gasless"];
export default func;
