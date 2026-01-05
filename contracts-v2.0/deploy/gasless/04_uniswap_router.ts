import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { importDeployment } from "../../helpers/utils";
import routerArtifact from "@uniswap/v2-periphery/build/UniswapV2Router02.json";

const name = "UniswapV2Router02";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getChainId, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const factory = await deployments.get("UniswapV2Factory");
  const wkaia = await deployments.get("WKAIA");

  const chainId = await getChainId();
  if (chainId == "8217") {
    console.error("not yet supported");
    return;
  } else if (chainId == "1001") {
    await importDeployment(hre, name, "0x28F63927593438F66Db70A91e013F405df47feEA", {
      abi: routerArtifact.abi,
      bytecode: routerArtifact.bytecode,
    });
    return;
  }

  await deploy(name, {
    from: deployer,
    args: [factory.address, wkaia.address],
    log: true,
    deterministicDeployment: true,
    contract: {
      abi: routerArtifact.abi,
      bytecode: routerArtifact.bytecode,
    },
  });
};
func.tags = [name];
func.dependencies = ["UniswapV2Factory", "WKAIA"];
export default func;
