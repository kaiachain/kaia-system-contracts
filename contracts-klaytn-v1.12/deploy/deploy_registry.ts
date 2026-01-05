import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { deployRegistry, padUtils } from "../helpers/utils";
const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getChainId } = hre;

  if ((await getChainId()) != "31337") {
    console.log("Skipping Registry deployment because it's not a localhost network");
    return;
  }
  const registry = await deployRegistry();

  // Set the owner of the registry to the deployer
  await hre.network.provider.request({
    method: "hardhat_setStorageAt",
    params: [
      await registry.getAddress(),
      "0x" + Number(2).toString(16),
      padUtils((await hre.getNamedAccounts()).deployer, 32),
    ],
  });

  console.log(`Registry deployed at ${await registry.getAddress()}`);
};

func.tags = ["Registry"];
export default func;
