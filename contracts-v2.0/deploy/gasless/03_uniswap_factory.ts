import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { importDeployment } from "../../helpers/utils";
import factoryArtifact from "@uniswap/v2-core/build/UniswapV2Factory.json";

const name = "UniswapV2Factory";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getChainId, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();
  if (chainId == "8217") {
    console.error("not yet supported");
    return;
  } else if (chainId == "1001") {
    await importDeployment(hre, name, "0x537D58BdBC98c690bE5d3e3F638d4B93754B15Fd", {
      abi: factoryArtifact.abi,
      bytecode: factoryArtifact.bytecode,
    });
    return;
  }

  await deploy(name, {
    from: deployer,
    args: [deployer],
    log: true,
    deterministicDeployment: true,
    contract: {
      abi: factoryArtifact.abi,
      bytecode: factoryArtifact.bytecode,
    },
  });
};
func.tags = [name, "Gasless"];
export default func;
