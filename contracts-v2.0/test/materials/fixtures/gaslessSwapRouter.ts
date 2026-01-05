import { ethers } from "hardhat";
import { parseEther } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import factoryArtifact from "@uniswap/v2-core/build/UniswapV2Factory.json";
import {
  GaslessSwapRouter__factory,
  TestToken__factory,
  UniswapV2Factory,
  UniswapV2Factory__factory,
  UniswapV2Router02__factory,
  WKAIA__factory,
} from "../../../typechain-types";
import { nowTime } from "../../../helpers/utils";

export async function gaslessSwapRouterFixture() {
  const [deployer, testUser, thirdUser] = await ethers.getSigners();
  const INITIAL_LIQUIDITY = parseEther("1000");

  // Deploy TestToken
  const testToken = await new TestToken__factory(deployer).deploy(testUser.address);

  // Deploy WKAIA
  const wkaia = await new WKAIA__factory(deployer).deploy();

  // Deploy UniswapV2Factory
  const Factory = new ethers.ContractFactory(factoryArtifact.abi, factoryArtifact.bytecode, deployer);
  const deployment = await Factory.deploy(deployer.address);
  const uniswapFactory = new UniswapV2Factory__factory(deployer).attach(
    await deployment.getAddress(),
  ) as UniswapV2Factory;

  // Deploy UniswapV2Router02
  const uniswapRouter = await new UniswapV2Router02__factory(deployer).deploy(uniswapFactory.target, wkaia.target);

  // Deploy GaslessSwapRouter
  const gaslessRouter = await new GaslessSwapRouter__factory(deployer).deploy(wkaia.target);

  // Create Uniswap pair and add liquidity
  await uniswapFactory.createPair(testToken.target, wkaia.target);

  // Setup liquidity for testing
  await wkaia.connect(testUser).deposit({ value: INITIAL_LIQUIDITY });
  await testToken.connect(testUser).approve(uniswapRouter.target, INITIAL_LIQUIDITY);
  await wkaia.connect(testUser).approve(uniswapRouter.target, INITIAL_LIQUIDITY);
  const currentBlock = await nowTime();
  const deadline = currentBlock + 3600;
  await uniswapRouter
    .connect(testUser)
    .addLiquidity(
      testToken.target,
      wkaia.target,
      INITIAL_LIQUIDITY,
      INITIAL_LIQUIDITY,
      0,
      0,
      testUser.address,
      deadline,
    );

  return {
    INITIAL_LIQUIDITY,
    deployer,
    gaslessRouter,
    testToken,
    testUser,
    thirdUser,
    uniswapFactory,
    uniswapRouter,
    wkaia,
  };
}

export async function gaslessSwapRouterAddTokenFixture() {
  const {
    INITIAL_LIQUIDITY,
    deployer,
    gaslessRouter,
    testToken,
    testUser,
    thirdUser,
    uniswapFactory,
    uniswapRouter,
    wkaia,
  } = await loadFixture(gaslessSwapRouterFixture);

  await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);

  return {
    INITIAL_LIQUIDITY,
    deployer,
    gaslessRouter,
    testToken,
    testUser,
    thirdUser,
    uniswapFactory,
    uniswapRouter,
    wkaia,
  };
}

export async function gaslessSwapRouterMultiTokenFixture() {
  const liquidityAmount = parseEther("1000");
  const [deployer, testUser] = await ethers.getSigners();

  // Deploy WKAIA
  const wkaia = await new WKAIA__factory(deployer).deploy();

  // Deploy two separate factories
  const FactoryA = new ethers.ContractFactory(factoryArtifact.abi, factoryArtifact.bytecode, deployer);
  const FactoryB = new ethers.ContractFactory(factoryArtifact.abi, factoryArtifact.bytecode, deployer);
  const deploymentA = await FactoryA.deploy(deployer.address);
  const deploymentB = await FactoryB.deploy(deployer.address);
  const factoryA = new UniswapV2Factory__factory(deployer).attach(await deploymentA.getAddress()) as UniswapV2Factory;
  const factoryB = new UniswapV2Factory__factory(deployer).attach(await deploymentB.getAddress()) as UniswapV2Factory;

  // Deploy two separate routers
  const routerA = await new UniswapV2Router02__factory(deployer).deploy(factoryA.target, wkaia.target);
  const routerB = await new UniswapV2Router02__factory(deployer).deploy(factoryB.target, wkaia.target);

  // Deploy two test tokens
  const tokenA = await new TestToken__factory(deployer).deploy(testUser.address);
  const tokenB = await new TestToken__factory(deployer).deploy(testUser.address);

  // Create pairs in both factories
  await factoryA.createPair(tokenA.target, wkaia.target);
  await factoryB.createPair(tokenB.target, wkaia.target);

  // Setup liquidity for both pairs
  await wkaia.connect(testUser).deposit({ value: liquidityAmount * 2n });
  await tokenA.connect(testUser).approve(routerA.target, liquidityAmount);
  await tokenB.connect(testUser).approve(routerB.target, liquidityAmount);
  await wkaia.connect(testUser).approve(routerA.target, liquidityAmount);
  await wkaia.connect(testUser).approve(routerB.target, liquidityAmount);

  const currentBlock = await nowTime();
  const deadline = currentBlock + 3600;

  // Add liquidity to pair in Factory A
  await routerA
    .connect(testUser)
    .addLiquidity(tokenA.target, wkaia.target, liquidityAmount, liquidityAmount, 0, 0, testUser.address, deadline);

  // Add liquidity to pair in Factory B
  await routerB
    .connect(testUser)
    .addLiquidity(tokenB.target, wkaia.target, liquidityAmount, liquidityAmount, 0, 0, testUser.address, deadline);

  // Deploy GaslessSwapRouter
  const gaslessRouter = await new GaslessSwapRouter__factory(deployer).deploy(wkaia.target);

  return {
    deployer,
    factoryA,
    factoryB,
    gaslessRouter,
    liquidityAmount,
    routerA,
    routerB,
    testUser,
    tokenA,
    tokenB,
    wkaia,
  };
}
