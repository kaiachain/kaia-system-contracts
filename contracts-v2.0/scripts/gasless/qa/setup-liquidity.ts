import { ethers, deployments } from "hardhat";
import { parseEther, formatEther } from "@ethersproject/units";
import routerArtifact from "@uniswap/v2-periphery/build/UniswapV2Router02.json";
import pairArtifact from "@uniswap/v2-core/build/IUniswapV2Pair.json";
import fs from "fs";
import path from "path";
import { ZeroAddress } from "ethers";
import { TestToken, WKAIA, UniswapV2Router02, UniswapV2Factory } from "../../../typechain-types";

async function setupLiquidity(
  testTokenAddress?: string,
  wkaiaAddress?: string,
  routerAddress?: string,
  factoryAddress?: string,
  testUser?: any,
) {
  const [_, defaultTestUser] = await ethers.getSigners();

  if (!testTokenAddress || !wkaiaAddress || !routerAddress || !factoryAddress) {
    try {
      const testToken = (await deployments.get("TestToken")) as unknown as TestToken;
      const wkaia = (await deployments.get("WKAIA")) as unknown as WKAIA;
      const router = (await deployments.get("UniswapV2Router02")) as unknown as UniswapV2Router02;
      const factory = (await deployments.get("UniswapV2Factory")) as unknown as UniswapV2Factory;

      testTokenAddress = await testToken.getAddress();
      wkaiaAddress = await wkaia.getAddress();
      routerAddress = await router.getAddress();
      factoryAddress = await factory.getAddress();
    } catch (error) {
      const tempDir = path.join(__dirname, "temp");
      const deploymentPath = path.join(tempDir, "deployment-addresses.json");

      if (fs.existsSync(deploymentPath)) {
        const deploymentsRaw = fs.readFileSync(deploymentPath, "utf-8");
        const deployments = JSON.parse(deploymentsRaw);

        testTokenAddress = deployments.testToken;
        wkaiaAddress = deployments.wkaia;
        routerAddress = deployments.router;
        factoryAddress = deployments.factory;
      } else {
        throw new Error("Could not find deployment addresses");
      }
    }
  }

  testTokenAddress = testTokenAddress!;
  wkaiaAddress = wkaiaAddress!;
  routerAddress = routerAddress!;
  factoryAddress = factoryAddress!;

  testUser = testUser || defaultTestUser;

  console.log(`Executing setupLiquidity with address: ${testUser.address}`);

  const INITIAL_LIQUIDITY = parseEther("1000").toBigInt();

  // Get contract instances
  const testToken = await ethers.getContractAt("TestToken", testTokenAddress);
  const wkaia = await ethers.getContractAt("WKAIA", wkaiaAddress);
  const factory = await ethers.getContractAt("IUniswapV2Factory", factoryAddress);
  const router = new ethers.Contract(routerAddress, routerArtifact.abi, testUser);

  // Check test user balance
  const balance = await ethers.provider.getBalance(testUser.address);
  console.log(`\n🔍 Test User KAIA balance: ${formatEther(balance)} KAIA`);

  const testTokenBalance = await testToken.balanceOf(testUser.address);
  console.log(`🔍 Test User TestToken balance: ${formatEther(testTokenBalance)} TT`);

  let pairAddress = await factory.getPair(testTokenAddress, wkaiaAddress);
  console.log(`🔍 Pair address: ${pairAddress}`);

  if (pairAddress === ZeroAddress) {
    console.log("\n🌉 Creating Uniswap pair...");
    const createPairTx = await factory.createPair(testTokenAddress, wkaiaAddress);
    await createPairTx.wait();
  }
  // Create Uniswap pair

  pairAddress = await factory.getPair(testTokenAddress, wkaiaAddress);
  console.log(`🔍 Pair address: ${pairAddress}`);

  if (pairAddress === ZeroAddress) {
    throw new Error("Failed to create Uniswap pair");
  }

  const wkaiaWithTestUser = wkaia.connect(testUser) as WKAIA;
  const wkaiaDepositTx = await wkaiaWithTestUser.deposit({
    value: INITIAL_LIQUIDITY,
    gasLimit: 300000n,
  });
  await wkaiaDepositTx.wait();

  const testTokenWithTestUser = testToken.connect(testUser) as TestToken;
  const testTokenApproveTx = await testTokenWithTestUser.approve(routerAddress, INITIAL_LIQUIDITY);
  await testTokenApproveTx.wait();

  const wkaiaApproveTx = await wkaiaWithTestUser.approve(routerAddress, INITIAL_LIQUIDITY);
  await wkaiaApproveTx.wait();

  // Check token allowances
  const testTokenAllowance = await testToken.allowance(testUser.address, routerAddress);
  const wkaiaAllowance = await wkaia.allowance(testUser.address, routerAddress);
  console.log(`TestToken allowance: ${formatEther(testTokenAllowance)}`);
  console.log(`WKAIA allowance: ${formatEther(wkaiaAllowance)}`);

  // Add liquidity
  console.log("\n💧 Adding initial liquidity...");
  const deadline = Math.floor(Date.now() / 1000) + 60 * 20;
  const addLiquidityTx = await router.addLiquidity(
    testTokenAddress,
    wkaiaAddress,
    INITIAL_LIQUIDITY,
    INITIAL_LIQUIDITY,
    0, // min amount of TestToken
    0, // min amount of WKAIA
    testUser.address,
    deadline,
    { gasLimit: 3000000 },
  );
  const receipt = await addLiquidityTx.wait();

  // Verify liquidity
  const pair = await ethers.getContractAt(pairArtifact.abi, pairAddress);
  const reserves = await pair.getReserves();
  console.log("\n📊 Liquidity Pool Reserves:");
  console.log(`Reserve0: ${formatEther(reserves[0])}`);
  console.log(`Reserve1: ${formatEther(reserves[1])}`);

  console.log(`Liquidity added. Gas used: ${receipt.gasUsed.toString()}`);

  return {
    testTokenAddress,
    wkaiaAddress,
    routerAddress,
    factoryAddress,
    pairAddress,
  };
}

if (require.main === module) {
  setupLiquidity()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

export default setupLiquidity;
