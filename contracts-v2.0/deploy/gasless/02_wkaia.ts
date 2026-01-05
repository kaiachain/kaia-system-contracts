import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { importDeployment } from "../../helpers/utils";

const name = "WKAIA";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getChainId, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();
  if (chainId == "8217") {
    await importDeployment(hre, name, "0x19Aac5f612f524B754CA7e7c41cbFa2E981A4432");
    return;
  } else if (chainId == "1001") {
    await importDeployment(hre, name, "0x043c471bEe060e00A56CcD02c0Ca286808a5A436");
    return;
  }

  await deploy(name, {
    from: deployer,
    args: [],
    log: true,
    deterministicDeployment: true,
  });
};
func.tags = [name, "Gasless"];
export default func;
