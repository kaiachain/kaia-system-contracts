import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getChainId, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();
  let wkaia: string;
  if (chainId == "8217") {
    wkaia = "0x19Aac5f612f524B754CA7e7c41cbFa2E981A4432";
  } else if (chainId == "1001") {
    wkaia = "0x043c471bEe060e00A56CcD02c0Ca286808a5A436";
  } else {
    wkaia = (await deployments.get("WKAIA")).address;
  }

  await deploy("GaslessSwapRouter", {
    from: deployer,
    args: [wkaia],
    log: true,
  });
};
func.tags = ["GaslessSwapRouter", "Gasless"];
func.dependencies = ["WKAIA"];
export default func;
