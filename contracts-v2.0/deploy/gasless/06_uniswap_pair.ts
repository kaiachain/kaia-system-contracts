import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import routerArtifact from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import { ZeroAddress } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { save } = deployments;
  const { deployer } = await getNamedAccounts();

  const factoryDep = await deployments.get("UniswapV2Factory");
  const wkaia = await deployments.get("WKAIA");
  const testToken = await deployments.get("TestToken");

  const signer = await hre.ethers.getSigner(deployer);
  const factory = await hre.ethers.getContractAt(factoryDep.abi, factoryDep.address, signer);
  let pair = await factory.getPair(testToken.address, wkaia.address);
  if (pair === ZeroAddress) {
    const tx = await factory.createPair(testToken.address, wkaia.address);
    await tx.wait();
    pair = await factory.getPair(testToken.address, wkaia.address);
    save("UniswapV2Pair", {
      address: pair,
      ...routerArtifact,
    });
    console.log(`WKAIA-TestToken Pair deployed at ${pair}`);
  } else {
    console.log(`reusing WKAIA-TestToken Pair at ${pair}`);
  }
};

func.tags = ["Pair", "Gasless"];
func.dependencies = ["UniswapV2Factory", "UniswapV2Router02", "WKAIA"];
export default func;
