import { ethers } from "hardhat";
import { getContractFromDeployment, REGISTRY_ADDRESS } from "../../../helpers/utils";
import { checkAndTransferOwnership, waitForTargetBlock } from "./utils";
import setupLiquidity from "./setup-liquidity";
import hre from "hardhat";
import { Registry, Registry__factory } from "../../../typechain-types";

async function main() {
  if (hre.network.name != "homi") {
    throw new Error("This only works on the network homi");
  }

  const [deployer] = await hre.ethers.getSigners();
  console.log("\n1. Register GaslessSwapRouter address to Registry...");
  const currentBlock = await ethers.provider.getBlockNumber();
  const targetBlock = currentBlock + 20;
  const gsr = await getContractFromDeployment(hre, "GaslessSwapRouter");
  const registry = new Registry__factory(deployer).attach(REGISTRY_ADDRESS) as Registry;
  await registry.register("GaslessSwapRouter", await gsr.getAddress(), targetBlock, {
    gasLimit: 300000,
  });

  // Wait for the target block to be reached before adding the token
  console.log(`Waiting for target block ${targetBlock}...`);
  await waitForTargetBlock(targetBlock);

  console.log("\n2. Setting up initial liquidity...");
  const wkaia = await getContractFromDeployment(hre, "WKAIA");
  const testToken = await getContractFromDeployment(hre, "TestToken");
  const uniRouter = await getContractFromDeployment(hre, "UniswapV2Router02");
  const factory = await getContractFromDeployment(hre, "UniswapV2Factory");
  await setupLiquidity(
    await testToken.getAddress(),
    await wkaia.getAddress(),
    await uniRouter.getAddress(),
    await factory.getAddress(),
    deployer,
  );

  console.log("\n3. Adding token to router...");
  await gsr.addToken(await testToken.getAddress(), await factory.getAddress(), await uniRouter.getAddress(), {
    gasLimit: 300000,
  });
  await checkAndTransferOwnership(await gsr.getAddress(), deployer);
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
