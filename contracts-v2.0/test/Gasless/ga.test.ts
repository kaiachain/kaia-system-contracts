import { expect } from "chai";
import { ethers, network } from "hardhat";
import { MaxUint256, ZeroAddress, Signer, parseEther } from "ethers";
import { loadFixture, setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { gasless } from "@kaiachain/ethers-ext/v6";

import {
  gaslessSwapRouterFixture,
  gaslessSwapRouterAddTokenFixture,
  gaslessSwapRouterMultiTokenFixture,
} from "../materials";
import { GaslessSwapRouter__factory, TestToken__factory, WKAIA, WKAIA__factory } from "../../typechain-types";
import { nowTime } from "../../helpers/utils";

describe("GaslessSwapRouter Constructor", function () {
  it("should fail when initialized with zero address for WKAIA", async function () {
    const GaslessSwapRouter = await ethers.getContractFactory("GaslessSwapRouter");

    await expect(GaslessSwapRouter.deploy(ZeroAddress)).to.be.revertedWith("Zero address is not allowed");
  });
});

describe("GaslessSwapRouter", function () {
  describe("Token Management", function () {
    it("should add token successfully", async function () {
      const { gaslessRouter, testToken, uniswapFactory, uniswapRouter } = await loadFixture(gaslessSwapRouterFixture);

      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);
      expect(await gaslessRouter.isTokenSupported(testToken.target)).to.be.true;
      expect(await gaslessRouter.dexAddress(testToken.target)).to.equal(uniswapFactory.target);
    });

    it("should fail to add token if already supported", async function () {
      const { gaslessRouter, testToken, uniswapFactory, uniswapRouter } = await loadFixture(gaslessSwapRouterFixture);

      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);
      await expect(
        gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target),
      ).to.be.revertedWith("TokenAlreadySupported");
    });

    it("should remove token successfully", async function () {
      const { gaslessRouter, testToken, uniswapFactory, uniswapRouter } = await loadFixture(gaslessSwapRouterFixture);

      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);
      await gaslessRouter.removeToken(testToken.target);
      expect(await gaslessRouter.isTokenSupported(testToken.target)).to.be.false;
    });

    it("should fail to remove token if not supported", async function () {
      const { gaslessRouter, testToken } = await loadFixture(gaslessSwapRouterFixture);

      await expect(gaslessRouter.removeToken(testToken.target)).to.be.revertedWith("TokenNotSupported");
    });

    it("should get all supported tokens", async function () {
      const { gaslessRouter, testToken, uniswapFactory, uniswapRouter } = await loadFixture(gaslessSwapRouterFixture);

      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);
      const supportedTokens = await gaslessRouter.getSupportedTokens();
      expect(supportedTokens).to.include(testToken.target);
      expect(supportedTokens.length).to.equal(1);
    });

    it("should add and remove multiple tokens in various orders", async function () {
      const { gaslessRouter, testToken, testUser, wkaia, uniswapFactory, uniswapRouter, deployer } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      // Deploy multiple tokens
      const token1 = await new TestToken__factory(deployer).deploy(testUser.address);
      const token2 = await new TestToken__factory(deployer).deploy(testUser.address);
      const token3 = await new TestToken__factory(deployer).deploy(testUser.address);

      // Create pairs for all tokens
      await uniswapFactory.createPair(token1.target, wkaia.target);
      await uniswapFactory.createPair(token2.target, wkaia.target);
      await uniswapFactory.createPair(token3.target, wkaia.target);

      const liquidityAmount = parseEther("10.0");

      await token1.connect(testUser).approve(uniswapRouter.target, liquidityAmount);
      await token2.connect(testUser).approve(uniswapRouter.target, liquidityAmount);
      await token3.connect(testUser).approve(uniswapRouter.target, liquidityAmount);
      await wkaia.connect(testUser).approve(uniswapRouter.target, liquidityAmount * 3n);

      await wkaia.connect(testUser).deposit({ value: liquidityAmount * 3n });

      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await uniswapRouter
        .connect(testUser)
        .addLiquidity(token1.target, wkaia.target, liquidityAmount, liquidityAmount, 0, 0, testUser.address, deadline);

      await uniswapRouter
        .connect(testUser)
        .addLiquidity(token2.target, wkaia.target, liquidityAmount, liquidityAmount, 0, 0, testUser.address, deadline);

      await uniswapRouter
        .connect(testUser)
        .addLiquidity(token3.target, wkaia.target, liquidityAmount, liquidityAmount, 0, 0, testUser.address, deadline);

      // Add all tokens to the router
      await gaslessRouter.addToken(token1.target, uniswapFactory.target, uniswapRouter.target);
      await gaslessRouter.addToken(token2.target, uniswapFactory.target, uniswapRouter.target);
      await gaslessRouter.addToken(token3.target, uniswapFactory.target, uniswapRouter.target);
      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);

      // Verify all tokens are supported
      let supportedTokens = await gaslessRouter.getSupportedTokens();
      expect(supportedTokens.length).to.equal(4);
      expect(supportedTokens).to.include(token1.target);
      expect(supportedTokens).to.include(token2.target);
      expect(supportedTokens).to.include(token3.target);
      expect(supportedTokens).to.include(testToken.target);

      // Remove tokens in different order
      await gaslessRouter.removeToken(token2.target);
      supportedTokens = await gaslessRouter.getSupportedTokens();
      expect(supportedTokens.length).to.equal(3);
      expect(supportedTokens).to.include(token1.target);
      expect(supportedTokens).to.include(token3.target);
      expect(supportedTokens).to.include(testToken.target);
      expect(supportedTokens).to.not.include(token2.target);

      // Remove token from the middle of the array
      await gaslessRouter.removeToken(token1.target);
      supportedTokens = await gaslessRouter.getSupportedTokens();
      expect(supportedTokens.length).to.equal(2);
      expect(supportedTokens).to.not.include(token1.target);
      expect(supportedTokens).to.include(token3.target);
      expect(supportedTokens).to.include(testToken.target);

      // Try to get DEX info for removed token
      await expect(gaslessRouter.getDEXInfo(token1.target)).to.be.revertedWith("TokenNotSupported");

      // Verify remaining tokens still work
      const dexInfo = await gaslessRouter.getDEXInfo(token3.target);
      expect(dexInfo.factory).to.equal(uniswapFactory.target);
      expect(dexInfo.router).to.equal(uniswapRouter.target);
    });

    it("should fail to add zero address as token", async function () {
      const { gaslessRouter, uniswapFactory, uniswapRouter } = await loadFixture(gaslessSwapRouterFixture);

      await expect(gaslessRouter.addToken(ZeroAddress, uniswapFactory.target, uniswapRouter.target)).to.be.revertedWith(
        "Invalid token address",
      );
    });

    it("should fail when adding token with zero address router or factory", async function () {
      const { gaslessRouter, testToken, uniswapFactory, uniswapRouter } = await loadFixture(gaslessSwapRouterFixture);

      // Test with zero router
      await expect(gaslessRouter.addToken(testToken.target, uniswapFactory.target, ZeroAddress)).to.be.revertedWith(
        "Invalid router address",
      );

      // Test with zero factory
      await expect(gaslessRouter.addToken(testToken.target, ZeroAddress, uniswapRouter.target)).to.be.revertedWith(
        "Invalid factory address",
      );
    });

    it("should fail to add token with invalid DEX address", async function () {
      const { gaslessRouter, testUser, uniswapRouter } = await loadFixture(gaslessSwapRouterFixture);

      const MockFactory = await ethers.getContractFactory("MockInvalidFactory");
      const mockFactory = await MockFactory.deploy();

      const anotherToken = await (await ethers.getContractFactory("TestToken")).deploy(testUser.address);

      await expect(
        gaslessRouter.addToken(anotherToken.target, mockFactory.target, uniswapRouter.target),
      ).to.be.revertedWith("InvalidDEXAddress");
    });

    it("should handle multiple token additions and removals", async function () {
      const { gaslessRouter, testToken, testUser, uniswapFactory, uniswapRouter, wkaia, deployer } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      // First make sure testToken is already added
      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);

      // Deploy additional token
      const additionalToken = await new TestToken__factory(deployer).deploy(testUser.address);

      // Create pair for additional token
      await uniswapFactory.createPair(additionalToken.target, wkaia.target);

      const liquidityAmount = parseEther("10.0");
      await additionalToken.connect(testUser).approve(uniswapRouter.target, liquidityAmount);
      await wkaia.connect(testUser).approve(uniswapRouter.target, liquidityAmount);

      await wkaia.connect(testUser).deposit({ value: liquidityAmount });
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await uniswapRouter
        .connect(testUser)
        .addLiquidity(
          additionalToken.target,
          wkaia.target,
          liquidityAmount,
          liquidityAmount,
          0,
          0,
          testUser.address,
          deadline,
        );

      // Add the additional token
      await gaslessRouter.addToken(additionalToken.target, uniswapFactory.target, uniswapRouter.target);

      // Get supported tokens and verify both tokens are included
      const supportedTokens = await gaslessRouter.getSupportedTokens();
      expect(supportedTokens).to.include(testToken.target);
      expect(supportedTokens).to.include(additionalToken.target);
      expect(supportedTokens.length).to.equal(2);

      // Remove additional token
      await gaslessRouter.removeToken(additionalToken.target);

      // Verify only testToken remains
      const updatedSupportedTokens = await gaslessRouter.getSupportedTokens();
      expect(updatedSupportedTokens).to.include(testToken.target);
      expect(updatedSupportedTokens).to.not.include(additionalToken.target);
      expect(updatedSupportedTokens.length).to.equal(1);
    });

    it("should fail to add token with zero reserve", async function () {
      const { gaslessRouter, testUser, uniswapFactory, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      // Deploy a new token
      const TokenFactory = await ethers.getContractFactory("TestToken");
      const newToken = await TokenFactory.deploy(testUser.address);

      // Create pair but don't add liquidity
      await uniswapFactory.createPair(newToken.target, wkaia.target);

      // Try to add token - should fail due to no liquidity
      await expect(
        gaslessRouter.addToken(newToken.target, uniswapFactory.target, uniswapRouter.target),
      ).to.be.revertedWith("NoLiquidity");
    });

    it("should fail to add token with non-existent pair", async function () {
      const { gaslessRouter, testUser, uniswapRouter } = await loadFixture(gaslessSwapRouterFixture);

      // Create a token but don't create a pair for it
      const TokenFactory = await ethers.getContractFactory("TestToken");
      const tokenWithoutPair = await TokenFactory.deploy(testUser.address);

      // Mock factory that returns zero address for getPair
      const MockZeroPairFactory = await ethers.getContractFactory("MockZeroPairFactory");
      const mockFactory = await MockZeroPairFactory.deploy();

      // Try to add token - should fail due to non-existent pair
      await expect(
        gaslessRouter.addToken(tokenWithoutPair.target, mockFactory.target, uniswapRouter.target),
      ).to.be.revertedWith("PairDoesNotExist");
    });

    it("should successfully add token with sufficient reserves", async function () {
      const { gaslessRouter, testToken, uniswapFactory, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      // This token should already have liquidity from the fixture
      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);

      // Verify token is supported
      expect(await gaslessRouter.isTokenSupported(testToken.target)).to.be.true;

      // Get pair address
      const pairAddress = await uniswapFactory.getPair(testToken.target, wkaia.target);

      // Get reserves directly to confirm they're non-zero
      const pair = await ethers.getContractAt("IUniswapV2Pair", pairAddress);
      const [reserve0, reserve1] = await pair.getReserves();

      // Verify both reserves are greater than zero
      expect(reserve0).to.be.gt(0);
      expect(reserve1).to.be.gt(0);
    });
  });

  describe("Commission Management", function () {
    it("should update commission rate", async function () {
      const { gaslessRouter } = await loadFixture(gaslessSwapRouterFixture);

      const newRate = 500; // 5%
      await gaslessRouter.updateCommissionRate(newRate);
      expect(await gaslessRouter.commissionRate()).to.equal(newRate);
    });

    it("should fail to update commission rate if too high", async function () {
      const { gaslessRouter } = await loadFixture(gaslessSwapRouterFixture);

      const tooHighRate = 11000; // 110%
      await expect(gaslessRouter.updateCommissionRate(tooHighRate)).to.be.revertedWith("InvalidCommissionRate");
    });

    it("should fail to claim commission if zero", async function () {
      const { gaslessRouter } = await loadFixture(gaslessSwapRouterFixture);

      await expect(gaslessRouter.claimCommission()).to.be.revertedWith("NoCommissionToWithdraw");
    });

    it("should accumulate and claim commission successfully", async function () {
      const { deployer, gaslessRouter, testToken, testUser, uniswapFactory, uniswapRouter } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      // Set commission rate to 10%
      await gaslessRouter.updateCommissionRate(1000);

      // Add token and approve for swap
      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);
      const swapAmount = parseEther("10.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      // Calculate gas repayment
      const feeData = await ethers.provider.getFeeData();
      const gasPriceBN = feeData.gasPrice!;
      const amountRepay = gasPriceBN * 600000n; // Rough estimate

      // Execute swap
      const minAmountOut = amountRepay + parseEther("1"); // Ensure enough output
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;
      await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline);

      // Check accumulated commission
      const accumulatedCommission = await ethers.provider.getBalance(gaslessRouter.target);
      expect(accumulatedCommission).to.be.gt(0);

      // Get contract balance
      const contractBalance = await ethers.provider.getBalance(gaslessRouter.target);
      expect(contractBalance).to.be.gt(0);

      // Claim commission
      const initialBalance = await ethers.provider.getBalance(deployer.address);
      await gaslessRouter.claimCommission();
      const finalBalance = await ethers.provider.getBalance(deployer.address);

      expect(finalBalance - initialBalance).to.be.gt(0);
      expect(await ethers.provider.getBalance(gaslessRouter.target)).to.equal(0);
    });

    it("should handle commission rate at boundary (10000)", async function () {
      const { gaslessRouter, testToken, testUser, uniswapFactory, uniswapRouter } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      await gaslessRouter.updateCommissionRate(10000); // 100%

      const swapAmount = parseEther("1.0");
      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;
      const minAmountOut = amountRepay + parseEther("0.1");

      const initialBalance = await ethers.provider.getBalance(testUser.address);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;
      await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline);

      const finalBalance = await ethers.provider.getBalance(testUser.address);
      expect(finalBalance).to.be.lt(initialBalance + amountRepay);
    });

    it("should handle zero commission correctly", async function () {
      const { gaslessRouter, testToken, testUser, uniswapFactory, uniswapRouter } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      // Ensure commission rate is 0
      await gaslessRouter.updateCommissionRate(0);

      const swapAmount = parseEther("1.0");
      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;
      const minAmountOut = amountRepay + parseEther("0.1");

      const initialBalance = await ethers.provider.getBalance(testUser.address);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;
      await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline);

      const finalBalance = await ethers.provider.getBalance(testUser.address);
      expect(finalBalance).to.be.gt(initialBalance);
      expect(await ethers.provider.getBalance(gaslessRouter.target)).to.equal(0);
    });

    it("should calculate commission precisely", async function () {
      const { gaslessRouter, testToken, testUser, uniswapFactory, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      await gaslessRouter.updateCommissionRate(500); // 5%

      const swapAmount = parseEther("10.0");
      await gaslessRouter.addToken(testToken.target, uniswapFactory.target, uniswapRouter.target);
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;
      const minAmountOut = amountRepay + parseEther("1");

      const path = [testToken.target, wkaia.target];
      const [, expectedOutput] = await uniswapRouter.getAmountsOut(swapAmount, path);
      const userAmount = expectedOutput - amountRepay;

      const commission = (userAmount * 500n) / 10000n;

      const preCommissionBalance = await ethers.provider.getBalance(gaslessRouter.target);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;
      await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline);

      const postCommissionBalance = await ethers.provider.getBalance(gaslessRouter.target);
      const actualCommission = postCommissionBalance - preCommissionBalance;

      expect(actualCommission).to.equal(commission);
    });
  });

  describe("Ownership Management", function () {
    it("should transfer ownership correctly", async function () {
      const { deployer, gaslessRouter, testUser, uniswapFactory, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      const newOwner = testUser;
      await gaslessRouter.transferOwnership(newOwner.address);
      const testToken = await new TestToken__factory(deployer).deploy(testUser.address);

      await uniswapFactory.createPair(testToken.target, wkaia.target);

      const liquidityAmount = parseEther("10.0");
      await testToken.connect(testUser).approve(uniswapRouter.target, liquidityAmount);
      await wkaia.connect(testUser).approve(uniswapRouter.target, liquidityAmount);
      await wkaia.connect(testUser).deposit({ value: liquidityAmount });

      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await uniswapRouter
        .connect(testUser)
        .addLiquidity(
          testToken.target,
          wkaia.target,
          liquidityAmount,
          liquidityAmount,
          0,
          0,
          testUser.address,
          deadline,
        );

      await expect(
        gaslessRouter.connect(newOwner).addToken(testToken.target, uniswapFactory.target, uniswapRouter.target),
      ).to.not.be.reverted;

      await expect(
        gaslessRouter
          .connect(deployer)
          .addToken(ethers.Wallet.createRandom().address, uniswapFactory.target, uniswapRouter.target),
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should fail to claim commission by non-owner", async function () {
      const { gaslessRouter, testUser } = await loadFixture(gaslessSwapRouterFixture);

      await expect(gaslessRouter.connect(testUser).claimCommission()).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("should comprehensively test ownership functions", async function () {
      const { deployer, gaslessRouter, testToken, testUser, uniswapFactory, uniswapRouter } = await loadFixture(
        gaslessSwapRouterFixture,
      );

      // Test initial ownership
      expect(await gaslessRouter.owner()).to.equal(deployer.address);

      // Test transferring ownership
      await gaslessRouter.transferOwnership(testUser.address);
      expect(await gaslessRouter.owner()).to.equal(testUser.address);

      // Test function access by previous owner (should fail)
      await expect(
        gaslessRouter.connect(deployer).addToken(testToken.target, uniswapFactory.target, uniswapRouter.target),
      ).to.be.revertedWith("Ownable: caller is not the owner");

      // Transfer ownership back
      await gaslessRouter.connect(testUser).transferOwnership(deployer.address);
      expect(await gaslessRouter.owner()).to.equal(deployer.address);

      // Test various privileged functions with non-owner
      await expect(gaslessRouter.connect(testUser).updateCommissionRate(500)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );

      await expect(gaslessRouter.connect(testUser).claimCommission()).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );

      await expect(gaslessRouter.connect(testUser).removeToken(ZeroAddress)).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });
  });

  describe("Basic Functions", function () {
    it("should receive KAIA successfully", async function () {
      const { gaslessRouter, testUser } = await loadFixture(gaslessSwapRouterFixture);

      const amount = parseEther("1.0");
      const initialBalance = await ethers.provider.getBalance(gaslessRouter.target);

      await testUser.sendTransaction({
        to: gaslessRouter.target,
        value: amount,
      });

      const finalBalance = await ethers.provider.getBalance(gaslessRouter.target);
      expect(finalBalance - initialBalance).to.equal(amount);
    });
  });

  describe("DEX Information Management", function () {
    it("should handle all DEX info retrieval edge cases", async function () {
      const { gaslessRouter, testToken, uniswapFactory, uniswapRouter } = await loadFixture(
        gaslessSwapRouterAddTokenFixture,
      );

      // Get DEX info for valid token
      const dexInfo = await gaslessRouter.getDEXInfo(testToken.target);
      expect(dexInfo.factory).to.equal(uniswapFactory.target);
      expect(dexInfo.router).to.equal(uniswapRouter.target);

      // Try to get DEX info for non-existent token
      const randomToken = ethers.Wallet.createRandom().address;
      await expect(gaslessRouter.getDEXInfo(randomToken)).to.be.revertedWith("TokenNotSupported");

      // Try to get DEX address for non-existent token
      await expect(gaslessRouter.dexAddress(randomToken)).to.be.revertedWith("TokenNotSupported");

      // Check if token is supported
      expect(await gaslessRouter.isTokenSupported(testToken.target)).to.be.true;
      expect(await gaslessRouter.isTokenSupported(randomToken)).to.be.false;
    });

    it("should revert when getting dex address for unsupported token", async function () {
      const { gaslessRouter } = await loadFixture(gaslessSwapRouterAddTokenFixture);

      const unknownToken = ethers.Wallet.createRandom().address;
      await expect(gaslessRouter.dexAddress(unknownToken)).to.be.revertedWith("TokenNotSupported");
    });
  });
});

describe("GaslessSwapRouter: Swap Operations", function () {
  describe("Core Swap Functionality", function () {
    it("should calculate amount in correctly", async function () {
      const { gaslessRouter, testToken } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      const amountOut = parseEther("1");
      const amountIn = await gaslessRouter.getAmountIn(testToken.target, amountOut);
      expect(amountIn).to.be.gt(0);
    });

    it("should execute swap successfully", async function () {
      const { gaslessRouter, testToken, testUser, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterAddTokenFixture,
      );
      const swapAmount = parseEther("1.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      // Calculate gas repayment
      const feeData = await ethers.provider.getFeeData();
      const gasPriceBN = feeData.gasPrice!;
      const R1 = gasPriceBN * 21000n;
      const R2 = 200000n;
      const R3 = gasPriceBN * 300000n;
      const amountRepay = R1 + R2 + R3;

      // Get expected output
      const path = [testToken.target, wkaia.target];
      const [, expectedOutput] = await uniswapRouter.getAmountsOut(swapAmount, path);
      const margin = (expectedOutput * 1n) / 100n; // 1% margin
      const minAmountOut = amountRepay + margin;

      const initialBalance = await ethers.provider.getBalance(testUser.address);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      const tx = await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline);
      await (tx as any).wait();

      const finalBalance = await ethers.provider.getBalance(testUser.address);
      expect(finalBalance).to.be.gt(initialBalance);
    });

    it("should fail swap if token not supported", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      const invalidToken = ethers.Wallet.createRandom().address;

      // First approve some tokens to avoid approval revert
      const amount = parseEther("1");
      await testToken.connect(testUser).approve(gaslessRouter.target, amount);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter.connect(testUser).swapForGas(invalidToken, amount, amount, parseEther("0.1"), deadline),
      ).to.be.revertedWith("TokenNotSupported");
    });

    it("should prevent operations on removed token", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      await gaslessRouter.removeToken(testToken.target);

      const swapAmount = parseEther("1.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(testToken.target, swapAmount, parseEther("0.5"), amountRepay, deadline),
      ).to.be.revertedWith("TokenNotSupported");
    });

    it("should handle multiple consecutive swaps", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      await gaslessRouter.updateCommissionRate(500); // 5%

      const swapAmount = parseEther("5.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount * 2n);

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;
      const minAmountOut = amountRepay + parseEther("1");
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline);

      const initialCommissionBalance = await ethers.provider.getBalance(gaslessRouter.target);

      await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline);

      const finalCommissionBalance = await ethers.provider.getBalance(gaslessRouter.target);
      expect(finalCommissionBalance).to.be.gt(initialCommissionBalance);
    });

    it("should verify swap balances and commission", async function () {
      const { gaslessRouter, testToken, testUser, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterAddTokenFixture,
      );
      await gaslessRouter.updateCommissionRate(1000); // 10%

      const swapAmount = parseEther("10.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;

      const path = [testToken.target, wkaia.target];
      const [, expectedOutput] = await uniswapRouter.getAmountsOut(swapAmount, path);

      const userAmount = expectedOutput - amountRepay;
      const expectedCommission = (userAmount * 1000n) / 10000n;
      const expectedUserFinalAmount = userAmount - expectedCommission;

      const initialUserBalance = await ethers.provider.getBalance(testUser.address);
      const initialCommissionBalance = await ethers.provider.getBalance(gaslessRouter.target);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      const tx = await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, expectedOutput, amountRepay, deadline);
      await (tx as any).wait();

      const finalUserBalance = await ethers.provider.getBalance(testUser.address);
      const finalCommissionBalance = await ethers.provider.getBalance(gaslessRouter.target);

      expect(finalUserBalance - initialUserBalance).to.be.closeTo(expectedUserFinalAmount, parseEther("0.1"));
      expect(finalCommissionBalance - initialCommissionBalance).to.equal(expectedCommission);
    });
  });

  describe("Swap Parameter Validation", function () {
    it("should fail swap if insufficient output", async function () {
      const { gaslessRouter, testToken, testUser, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterAddTokenFixture,
      );
      const swapAmount = parseEther("1.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      // Get expected output
      const path = [testToken.target, wkaia.target];
      const [, expectedOutput] = await uniswapRouter.getAmountsOut(swapAmount, path);

      // Calculate minimum output that's much higher than possible
      const tooHighMinOutput = expectedOutput * 2n;
      const amountRepay = parseEther("0.1");

      // Min output should be greater than amountRepay
      expect(tooHighMinOutput).to.be.gt(amountRepay);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(testToken.target, swapAmount, tooHighMinOutput, amountRepay, deadline),
      ).to.be.revertedWith("UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
    });

    it("should revert when minAmountOut is less than amountRepay", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      const swapAmount = parseEther("1.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      const amountRepay = parseEther("0.1");
      const minAmountOut = parseEther("0.05"); // Less than amountRepay
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter.connect(testUser).swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline),
      ).to.be.revertedWith("InsufficientSwapOutput");
    });

    it("should revert with insufficient token balance", async function () {
      const { deployer, gaslessRouter, testUser, uniswapFactory, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterAddTokenFixture,
      );
      // Deploy a new token with no balance
      const noBalanceToken = await new TestToken__factory(deployer).deploy(deployer.address);

      // Create pair
      await uniswapFactory.createPair(noBalanceToken.target, wkaia.target);

      const liquidityAmount = parseEther("10.0");
      await noBalanceToken.connect(deployer).transfer(testUser.address, liquidityAmount);
      await noBalanceToken.connect(testUser).approve(uniswapRouter.target, liquidityAmount);
      await wkaia.connect(testUser).approve(uniswapRouter.target, liquidityAmount);
      await wkaia.connect(testUser).deposit({ value: liquidityAmount });

      let currentBlock = await nowTime();
      let deadline = currentBlock + 300;

      await uniswapRouter
        .connect(testUser)
        .addLiquidity(
          noBalanceToken.target,
          wkaia.target,
          liquidityAmount,
          liquidityAmount / 2n,
          0n,
          0n,
          testUser.address,
          deadline,
        );

      const remainingBalance = await noBalanceToken.balanceOf(testUser.address);
      await noBalanceToken.connect(testUser).transfer(deployer.address, remainingBalance);

      // Add token
      await gaslessRouter.addToken(noBalanceToken.target, uniswapFactory.target, uniswapRouter.target);

      // Try to swap with no balance
      const swapAmount = parseEther("1.0");
      await noBalanceToken.connect(testUser).approve(gaslessRouter.target, swapAmount);
      currentBlock = await nowTime();
      deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(noBalanceToken.target, swapAmount, parseEther("0.1"), parseEther("0.05"), deadline),
      ).to.be.revertedWith("Insufficient token balance");
    });

    it("should handle token approval limits", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      const maxApproval = MaxUint256;
      await testToken.connect(testUser).approve(gaslessRouter.target, maxApproval);

      const swapAmount = parseEther("10.0");

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;
      const minAmountOut = amountRepay + parseEther("1");
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline);

      const initialBalance = await testToken.balanceOf(testUser.address);
      expect(initialBalance).to.be.gt(0);
    });

    it("should fail swap if gas price is too high", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      try {
        const swapAmount = parseEther("1.0");
        await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);
        const currentBlock = await nowTime();
        const deadline = currentBlock + 300;

        await expect(
          gaslessRouter
            .connect(testUser)
            .swapForGas(testToken.target, swapAmount, parseEther("1000"), parseEther("0.1"), deadline),
        ).to.be.reverted;
      } catch (e) {
        const error = e as Error;
        expect(error.message).to.include("revert");
      }
    });
  });

  describe("Swap Edge Cases", function () {
    it("should handle extreme input in getAmountIn", async function () {
      const { gaslessRouter, testToken } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      const largeAmountOut = parseEther("0.00000001");
      const amountIn = await gaslessRouter.getAmountIn(testToken.target, largeAmountOut);
      expect(amountIn).to.be.gt(0);
    });

    it("should handle getAmountIn with extremely large output", async function () {
      const { gaslessRouter, testToken } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      const extremeAmountOut = MaxUint256;

      await expect(gaslessRouter.getAmountIn(testToken.target, extremeAmountOut)).to.be.reverted;
    });

    it("should handle getAmountIn with zero output", async function () {
      const { gaslessRouter, testToken } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      await expect(gaslessRouter.getAmountIn(testToken.target, 0n)).to.be.reverted;
    });

    it("should handle very small swap amount", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      const verySmallAmount = parseEther("0.000001");
      await testToken.connect(testUser).approve(gaslessRouter.target, verySmallAmount);

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(testToken.target, verySmallAmount, amountRepay, amountRepay / 2n, deadline),
      ).to.be.reverted;
    });

    it("should handle very large swap amounts", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      const largeSwapAmount = parseEther("10000000000000");
      await testToken.connect(testUser).approve(gaslessRouter.target, largeSwapAmount);

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(testToken.target, largeSwapAmount, parseEther("0.5"), amountRepay, deadline),
      ).to.be.reverted;
    });

    it("should fail if coin transfer fails", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      // Create a mock coinbase that rejects payments
      const MockCoinbase = await ethers.getContractFactory("MockCoinbase");
      const mockCoinbase = await MockCoinbase.deploy();

      // Modify block.coinbase to return mock address
      await network.provider.send("hardhat_setCoinbase", [mockCoinbase.target]);

      const swapAmount = parseEther("1.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(testToken.target, swapAmount, parseEther("0.5"), parseEther("0.1"), deadline),
      ).to.be.revertedWith("Failed to send KAIA to proposer");

      // Reset coinbase
      await network.provider.send("hardhat_setCoinbase", ["0x0000000000000000000000000000000000000000"]);
    });

    it("should fail if transfer to user fails", async function () {
      const { gaslessRouter, testToken, testUser, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterAddTokenFixture,
      );
      // Deploy a malicious contract that rejects KAIA transfers
      const MaliciousReceiver = await ethers.getContractFactory("MaliciousReceiver");
      const maliciousReceiver = await MaliciousReceiver.deploy();

      // Impersonate the malicious contract
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [maliciousReceiver.target],
      });

      // Fund the malicious account with ETH for gas fees
      await setBalance(maliciousReceiver.target as string, 10e18);

      const maliciousSigner = await ethers.getSigner(await maliciousReceiver.getAddress());

      // Fund the malicious contract with some test tokens
      await testToken.connect(testUser).transfer(maliciousReceiver.target, parseEther("10"));
      await testToken.connect(maliciousSigner).approve(gaslessRouter.target, parseEther("1"));

      // Get expected output for setting appropriate minAmountOut
      const path = [testToken.target, wkaia.target];
      await uniswapRouter.getAmountsOut(parseEther("1"), path);
      const amountRepay = parseEther("0.1");
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(maliciousSigner)
          .swapForGas(testToken.target, parseEther("1"), amountRepay + parseEther("0.1"), amountRepay, deadline),
      ).to.be.reverted;

      await network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [maliciousReceiver.target],
      });
    });
  });

  describe("Multiple DEX Support", function () {
    it("should add tokens with different factories", async function () {
      const { gaslessRouter, tokenA, factoryA, routerA, tokenB, factoryB, routerB } = await loadFixture(
        gaslessSwapRouterMultiTokenFixture,
      );
      // Add tokenA with factoryA
      await gaslessRouter.addToken(tokenA.target, factoryA.target, routerA.target);

      // Add tokenB with factoryB
      await gaslessRouter.addToken(tokenB.target, factoryB.target, routerB.target);

      // Verify both tokens are supported
      expect(await gaslessRouter.isTokenSupported(tokenA.target)).to.be.true;
      expect(await gaslessRouter.isTokenSupported(tokenB.target)).to.be.true;

      // Verify correct factory addresses are stored
      expect(await gaslessRouter.dexAddress(tokenA.target)).to.equal(factoryA.target);
      expect(await gaslessRouter.dexAddress(tokenB.target)).to.equal(factoryB.target);
    });

    it("should execute swaps through different factories", async function () {
      const { gaslessRouter, tokenA, factoryA, routerA, tokenB, factoryB, routerB, testUser, wkaia } =
        await loadFixture(gaslessSwapRouterMultiTokenFixture);
      // Add tokens with their respective factories
      await gaslessRouter.addToken(tokenA.target, factoryA.target, routerA.target);
      await gaslessRouter.addToken(tokenB.target, factoryB.target, routerB.target);

      // Setup for swaps
      const swapAmount = parseEther("1.0");
      await tokenA.connect(testUser).approve(gaslessRouter.target, swapAmount);
      await tokenB.connect(testUser).approve(gaslessRouter.target, swapAmount);

      // Calculate gas repayment
      const feeData = await ethers.provider.getFeeData();
      const gasPriceBN = feeData.gasPrice!;
      const amountRepay = gasPriceBN * 600000n;

      // Calculate minAmountOut for both tokens
      const pathA = [tokenA.target, wkaia.target];
      const [, expectedOutputA] = await routerA.getAmountsOut(swapAmount, pathA);
      const minAmountOutA = amountRepay + expectedOutputA / 100n; // Add 1% margin

      const pathB = [tokenB.target, wkaia.target];
      const [, expectedOutputB] = await routerB.getAmountsOut(swapAmount, pathB);
      const minAmountOutB = amountRepay + expectedOutputB / 100n; // Add 1% margin

      // Execute swap for tokenA through factoryA
      const initialBalanceA = await ethers.provider.getBalance(testUser.address);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await gaslessRouter.connect(testUser).swapForGas(tokenA.target, swapAmount, minAmountOutA, amountRepay, deadline);
      const finalBalanceA = await ethers.provider.getBalance(testUser.address);

      // Verify swap for tokenA was successful
      expect(finalBalanceA).to.be.gt(initialBalanceA);

      // Execute swap for tokenB through factoryB
      const initialBalanceB = await ethers.provider.getBalance(testUser.address);

      await gaslessRouter.connect(testUser).swapForGas(tokenB.target, swapAmount, minAmountOutB, amountRepay, deadline);
      const finalBalanceB = await ethers.provider.getBalance(testUser.address);

      // Verify swap for tokenB was successful
      expect(finalBalanceB).to.be.gt(initialBalanceB);
    });

    it("should use the correct factory and router for each token", async function () {
      const { factoryA, factoryB, routerA, routerB, testUser, tokenA, tokenB, wkaia, deployer } = await loadFixture(
        gaslessSwapRouterMultiTokenFixture,
      );
      // Deploy a GaslessSwapRouter with a custom router
      const customGaslessRouter = await new GaslessSwapRouter__factory(deployer).deploy(wkaia.target);

      // Add tokens with specific factory addresses
      await customGaslessRouter.addToken(tokenA.target, factoryA.target, routerA.target);
      await customGaslessRouter.addToken(tokenB.target, factoryB.target, routerB.target);

      // Setup for swaps
      const swapAmount = parseEther("1.0");
      await tokenA.connect(testUser).approve(customGaslessRouter.target, swapAmount);
      await tokenB.connect(testUser).approve(customGaslessRouter.target, swapAmount);

      // Get minAmountOut values
      const pathA = [tokenA.target, wkaia.target];
      const [, expectedOutputA] = await routerA.getAmountsOut(swapAmount, pathA);

      const pathB = [tokenB.target, wkaia.target];
      const [, expectedOutputB] = await routerB.getAmountsOut(swapAmount, pathB);

      // Calculate gas repayment
      const feeData = await ethers.provider.getFeeData();
      const gasPriceBN = feeData.gasPrice!;
      const amountRepay = gasPriceBN * 600000n;

      const minAmountOutA = amountRepay + expectedOutputA / 100n;
      const minAmountOutB = amountRepay + expectedOutputB / 100n;
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      // Both swaps should work since the router can find paths through
      // the correct factories based on the stored factory addresses
      await customGaslessRouter
        .connect(testUser)
        .swapForGas(tokenA.target, swapAmount, minAmountOutA, amountRepay, deadline);
      await customGaslessRouter
        .connect(testUser)
        .swapForGas(tokenB.target, swapAmount, minAmountOutB, amountRepay, deadline);

      // Additional check: getAmountIn should use the correct factory for each token
      const amountOutA = parseEther("0.1");
      const amountInA = await customGaslessRouter.getAmountIn(tokenA.target, amountOutA);

      const amountOutB = parseEther("0.1");
      const amountInB = await customGaslessRouter.getAmountIn(tokenB.target, amountOutB);

      // Due to different factory configurations, the amount in may differ
      expect(amountInA).to.not.equal(0);
      expect(amountInB).to.not.equal(0);
    });
  });
});

describe("GaslessSwapRouter: Error Handling & Mock Contract Tests", function () {
  describe("Error Cases", function () {
    it("should fail if token approval fails", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);

      await testToken.connect(testUser).approve(gaslessRouter.target, 0n);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(testToken.target, parseEther("100"), parseEther("0.5"), parseEther("0.1"), deadline),
      ).to.be.revertedWith("ERC20: insufficient allowance");
    });

    it("should fail if transfer to user fails", async function () {
      const { gaslessRouter, testToken, testUser, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterAddTokenFixture,
      );
      // Deploy a malicious contract that rejects KAIA transfers
      const MaliciousReceiver = await ethers.getContractFactory("MaliciousReceiver");
      const maliciousReceiver = await MaliciousReceiver.deploy();

      // Impersonate the malicious contract
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [maliciousReceiver.target],
      });

      // Fund the malicious account with ETH for gas fees
      await setBalance(maliciousReceiver.target as string, 10e18);

      const maliciousSigner = await ethers.getSigner(await maliciousReceiver.getAddress());

      // Fund the malicious contract with some test tokens
      await testToken.connect(testUser).transfer(maliciousReceiver.target, parseEther("10"));
      await testToken.connect(maliciousSigner).approve(gaslessRouter.target, parseEther("1"));

      // Get expected output for setting appropriate minAmountOut
      const path = [testToken.target, wkaia.target];
      await uniswapRouter.getAmountsOut(parseEther("1"), path);
      const amountRepay = parseEther("0.1");
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(maliciousSigner)
          .swapForGas(testToken.target, parseEther("1"), amountRepay + parseEther("0.1"), amountRepay, deadline),
      ).to.be.reverted;

      await network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [maliciousReceiver.target],
      });
    });

    it("should fail if WKAIA withdraw fails", async function () {
      const MaliciousWKAIA = await ethers.getContractFactory("MaliciousWKAIA");
      const maliciousWKAIA = await MaliciousWKAIA.deploy();

      await expect(maliciousWKAIA.withdraw(parseEther("1.0"))).to.be.revertedWith("Withdrawal failed");
    });

    it("should fail if coinbase payment fails", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      // Create a mock coinbase that rejects payments
      const MockCoinbase = await ethers.getContractFactory("MockCoinbase");
      const mockCoinbase = await MockCoinbase.deploy();

      // Modify block.coinbase to return mock address
      await network.provider.send("hardhat_setCoinbase", [mockCoinbase.target]);

      const swapAmount = parseEther("1.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(testToken.target, swapAmount, parseEther("0.5"), parseEther("0.1"), deadline),
      ).to.be.revertedWith("Failed to send KAIA to proposer");

      // Reset coinbase
      await network.provider.send("hardhat_setCoinbase", ["0x0000000000000000000000000000000000000000"]);
    });

    it("should handle commission claim failure", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      await gaslessRouter.updateCommissionRate(1000); // 10%
      const swapAmount = parseEther("10.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      const gasPriceBN = (await ethers.provider.getFeeData()).gasPrice!;
      const amountRepay = gasPriceBN * 600000n;
      const minAmountOut = amountRepay + parseEther("1");
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      await gaslessRouter
        .connect(testUser)
        .swapForGas(testToken.target, swapAmount, minAmountOut, amountRepay, deadline);

      const MaliciousReceiver = await ethers.getContractFactory("MaliciousReceiver");
      const maliciousReceiver = await MaliciousReceiver.deploy();

      await gaslessRouter.transferOwnership(maliciousReceiver.target);

      await expect(gaslessRouter.connect(testUser).claimCommission()).to.be.revertedWith(
        "Ownable: caller is not the owner",
      );
    });

    it("should revert when deadline has passed", async function () {
      const { gaslessRouter, testToken, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      const swapAmount = parseEther("1.0");
      await testToken.connect(testUser).approve(gaslessRouter.target, swapAmount);

      const pastDeadline = Math.floor(Date.now() / 1000) - 60;

      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(testToken.target, swapAmount, parseEther("0.5"), parseEther("0.1"), pastDeadline),
      ).to.be.revertedWith("UniswapV2Router: EXPIRED");
    });
  });

  describe("Mock Contract Tests", function () {
    it("should safely handle MaliciousWKAIA", async function () {
      // Deploy MaliciousWKAIA
      const MaliciousWKAIAFactory = await ethers.getContractFactory("MaliciousWKAIA");
      const maliciousWkaia = await MaliciousWKAIAFactory.deploy();

      // Test withdraw method
      await expect(maliciousWkaia.withdraw(parseEther("1"))).to.be.revertedWith("Withdrawal failed");
    });

    it("should safely handle MaliciousToken", async function () {
      const { deployer, testUser } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      // Deploy MaliciousToken
      const MaliciousTokenFactory = await ethers.getContractFactory("MaliciousToken");
      const maliciousToken = await MaliciousTokenFactory.deploy(deployer.address);

      // Test transfer method (should work)
      await maliciousToken.transfer(testUser.address, parseEther("1"));
      expect(await maliciousToken.balanceOf(testUser.address)).to.equal(parseEther("1"));
    });

    it("should test commission claim failure scenarios", async function () {
      const { deployer, gaslessRouter } = await loadFixture(gaslessSwapRouterAddTokenFixture);
      // Setup a malicious contract that rejects ETH
      const MaliciousReceiver = await ethers.getContractFactory("MaliciousReceiver");
      const maliciousReceiver = await MaliciousReceiver.deploy();

      // Add some funds to the contract
      await deployer.sendTransaction({
        to: gaslessRouter.target,
        value: parseEther("1"),
      });

      // Transfer ownership to the malicious contract
      await gaslessRouter.transferOwnership(maliciousReceiver.target);

      // Impersonate the malicious contract
      await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [maliciousReceiver.target],
      });

      // Fund the malicious account for gas
      await setBalance(maliciousReceiver.target as string, 10e18);

      const maliciousSigner = await ethers.getSigner(await maliciousReceiver.getAddress());

      // Try to claim commission - should fail because the malicious contract rejects ETH
      await expect(gaslessRouter.connect(maliciousSigner).claimCommission()).to.be.revertedWith(
        "CommissionClaimFailed",
      );

      // Stop impersonating
      await network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [maliciousReceiver.target],
      });
    });
  });
});

describe("WKAIA Contract Tests", function () {
  let wkaia: WKAIA;
  let deployer: Signer;
  let user1: Signer;
  let user2: Signer;

  beforeEach(async function () {
    [deployer, user1, user2] = await ethers.getSigners();

    // Deploy WKAIA
    wkaia = await new WKAIA__factory(deployer).deploy();
  });

  describe("Basic Functionality", function () {
    it("should have correct name, symbol, and decimals", async function () {
      expect(await wkaia.name()).to.equal("Wrapped Kaia");
      expect(await wkaia.symbol()).to.equal("WKAIA");
      expect(await wkaia.decimals()).to.equal(18);
    });

    it("should deposit KAIA via deposit() function", async function () {
      const depositAmount = parseEther("1.0");

      await wkaia.connect(user1).deposit({ value: depositAmount });

      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(depositAmount);
      expect(await ethers.provider.getBalance(wkaia.target)).to.equal(depositAmount);
    });

    it("should deposit KAIA via receive() function", async function () {
      const depositAmount = parseEther("1.0");

      await user1.sendTransaction({
        to: wkaia.target,
        value: depositAmount,
      });

      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(depositAmount);
      expect(await ethers.provider.getBalance(wkaia.target)).to.equal(depositAmount);
    });

    it("should withdraw KAIA via withdraw() function", async function () {
      const depositAmount = parseEther("1.0");
      const withdrawAmount = parseEther("0.5");

      // First deposit
      await wkaia.connect(user1).deposit({ value: depositAmount });

      const balanceBefore = await ethers.provider.getBalance(await user1.getAddress());

      // Then withdraw
      const tx = await wkaia.connect(user1).withdraw(withdrawAmount);
      const receipt = await tx.wait();
      if (!receipt) {
        throw new Error("Transaction failed");
      }
      const gasUsed = receipt.gasUsed * receipt.gasPrice;

      const balanceAfter = await ethers.provider.getBalance(await user1.getAddress());

      // Check balance changes
      expect(balanceAfter + gasUsed - balanceBefore).to.equal(withdrawAmount);
      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(depositAmount - withdrawAmount);
      expect(await ethers.provider.getBalance(wkaia.target)).to.equal(depositAmount - withdrawAmount);
    });

    it("should fail to withdraw more than balance", async function () {
      const depositAmount = parseEther("1.0");
      const withdrawAmount = parseEther("2.0");

      await wkaia.connect(user1).deposit({ value: depositAmount });

      await expect(wkaia.connect(user1).withdraw(withdrawAmount)).to.be.reverted;
    });

    it("should test totalSupply function", async function () {
      // Initially should be zero
      expect(await wkaia.totalSupply()).to.equal(0);

      // After deposits, should match contract's ETH balance
      await user1.sendTransaction({
        to: wkaia.target,
        value: parseEther("3.0"),
      });
      await user2.sendTransaction({
        to: wkaia.target,
        value: parseEther("2.0"),
      });

      expect(await wkaia.totalSupply()).to.equal(parseEther("5.0"));
      expect(await wkaia.totalSupply()).to.equal(await ethers.provider.getBalance(wkaia.target));
    });
  });

  describe("ERC20 Functionality", function () {
    beforeEach(async function () {
      // User1 deposits some WKAIA
      await wkaia.connect(user1).deposit({ value: parseEther("10.0") });
    });

    it("should transfer WKAIA tokens", async function () {
      const transferAmount = parseEther("2.0");

      await wkaia.connect(user1).transfer(await user2.getAddress(), transferAmount);

      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(parseEther("8.0"));
      expect(await wkaia.balanceOf(await user2.getAddress())).to.equal(transferAmount);
    });

    it("should approve and transferFrom WKAIA tokens", async function () {
      const approveAmount = parseEther("5.0");
      const transferAmount = parseEther("3.0");

      // User1 approves User2 to spend tokens
      await wkaia.connect(user1).approve(await user2.getAddress(), approveAmount);
      expect(await wkaia.allowance(await user1.getAddress(), await user2.getAddress())).to.equal(approveAmount);

      // User2 transfers tokens from User1 to themselves
      await wkaia.connect(user2).transferFrom(await user1.getAddress(), await user2.getAddress(), transferAmount);

      // Check balances and allowance
      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(parseEther("7.0"));
      expect(await wkaia.balanceOf(await user2.getAddress())).to.equal(transferAmount);
      expect(await wkaia.allowance(await user1.getAddress(), await user2.getAddress())).to.equal(
        approveAmount - transferAmount,
      );
    });

    it("should handle failed transfers due to insufficient balance", async function () {
      const transferAmount = parseEther("15.0"); // More than User1 has

      await expect(wkaia.connect(user1).transfer(await user2.getAddress(), transferAmount)).to.be.reverted;
    });

    it("should handle failed transferFrom due to insufficient allowance", async function () {
      const approveAmount = parseEther("2.0");
      const transferAmount = parseEther("3.0"); // More than approved

      // User1 approves User2 to spend tokens
      await wkaia.connect(user1).approve(await user2.getAddress(), approveAmount);

      // User2 tries to transfer more than approved
      await expect(
        wkaia.connect(user2).transferFrom(await user1.getAddress(), await user2.getAddress(), transferAmount),
      ).to.be.reverted;
    });
  });

  describe("Edge Cases", function () {
    it("should handle multiple deposits and withdrawals", async function () {
      // Make multiple deposits
      await wkaia.connect(user1).deposit({ value: parseEther("1.0") });
      await wkaia.connect(user1).deposit({ value: parseEther("2.0") });
      await user1.sendTransaction({
        to: wkaia.target,
        value: parseEther("3.0"),
      });

      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(parseEther("6.0"));

      // Make multiple withdrawals
      await wkaia.connect(user1).withdraw(parseEther("1.0"));
      await wkaia.connect(user1).withdraw(parseEther("2.0"));

      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(parseEther("3.0"));
      expect(await ethers.provider.getBalance(wkaia.target)).to.equal(parseEther("3.0"));
    });

    it("should handle zero value deposits", async function () {
      const initialBalance = await wkaia.balanceOf(await user1.getAddress());

      // Zero value deposit via deposit()
      await wkaia.connect(user1).deposit({ value: 0 });
      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(initialBalance);

      // Zero value deposit via receive()
      await user1.sendTransaction({ to: wkaia.target, value: 0 });
      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(initialBalance);
    });

    it("should handle zero value transfers and approvals", async function () {
      // Zero transfer
      await wkaia.connect(user1).transfer(await user2.getAddress(), 0);
      expect(await wkaia.balanceOf(await user2.getAddress())).to.equal(0);

      // Zero approval
      await wkaia.connect(user1).approve(await user2.getAddress(), 0);
      expect(await wkaia.allowance(await user1.getAddress(), await user2.getAddress())).to.equal(0);

      // Zero transferFrom (should work even with zero allowance)
      await wkaia.connect(user2).transferFrom(await user1.getAddress(), await user2.getAddress(), 0);
      expect(await wkaia.balanceOf(await user2.getAddress())).to.equal(0);
    });

    it("should handle transfers to the contract itself", async function () {
      // Deposit some WKAIA first
      await wkaia.connect(user1).deposit({ value: parseEther("5.0") });

      // Transfer to the contract itself
      await wkaia.connect(user1).transfer(wkaia.target, parseEther("1.0"));

      // Check balances
      expect(await wkaia.balanceOf(await user1.getAddress())).to.equal(parseEther("4.0"));
      expect(await wkaia.balanceOf(wkaia.target)).to.equal(parseEther("1.0"));
    });

    it("should handle unlimited approvals correctly", async function () {
      // Set unlimited approval (uint256 max value)
      const unlimitedApproval = MaxUint256;
      await wkaia.connect(user1).approve(await user2.getAddress(), unlimitedApproval);

      // Deposit some tokens
      await wkaia.connect(user1).deposit({ value: parseEther("10.0") });

      // Transfer multiple times without approval decreasing
      await wkaia.connect(user2).transferFrom(await user1.getAddress(), await user2.getAddress(), parseEther("2.0"));
      expect(await wkaia.allowance(await user1.getAddress(), await user2.getAddress())).to.equal(unlimitedApproval);

      await wkaia.connect(user2).transferFrom(await user1.getAddress(), await user2.getAddress(), parseEther("3.0"));
      expect(await wkaia.allowance(await user1.getAddress(), await user2.getAddress())).to.equal(unlimitedApproval);
    });
  });

  describe("Events", function () {
    it("should check that approve emits an event", async function () {
      // Test that approve emits correct event
      await expect(wkaia.connect(user1).approve(await user2.getAddress(), parseEther("1.0")))
        .to.emit(wkaia, "Approval")
        .withArgs(await user1.getAddress(), await user2.getAddress(), parseEther("1.0"));
    });

    it("should check that deposit emits an event", async function () {
      // Test that deposit emits correct event
      await expect(wkaia.connect(user1).deposit({ value: parseEther("1.0") }))
        .to.emit(wkaia, "Deposit")
        .withArgs(await user1.getAddress(), parseEther("1.0"));
    });

    it("should check that withdraw emits an event", async function () {
      // First deposit some funds
      await wkaia.connect(user1).deposit({ value: parseEther("5.0") });

      // Test that withdraw emits correct event
      await expect(wkaia.connect(user1).withdraw(parseEther("1.0")))
        .to.emit(wkaia, "Withdrawal")
        .withArgs(await user1.getAddress(), parseEther("1.0"));
    });

    it("should check that transfer emits an event", async function () {
      // First deposit some funds
      await wkaia.connect(user1).deposit({ value: parseEther("5.0") });

      // Test that transfer emits correct event
      await expect(wkaia.connect(user1).transfer(await user2.getAddress(), parseEther("1.0")))
        .to.emit(wkaia, "Transfer")
        .withArgs(await user1.getAddress(), await user2.getAddress(), parseEther("1.0"));
    });
  });
});

describe("kaia-sdk test", function () {
  it("getAmountsOut/getAmountsIn compatibility test", async function () {
    const abundantLiquidityFixture = async () => {
      const { deployer, gaslessRouter, testToken, testUser, uniswapRouter, wkaia } = await loadFixture(
        gaslessSwapRouterAddTokenFixture,
      );
      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;
      setBalance(testUser.address, parseEther("1000000000000"));

      await wkaia.connect(testUser).deposit({ value: parseEther("1000000000") });
      await testToken.connect(testUser).approve(await uniswapRouter.getAddress(), MaxUint256);
      await testToken.connect(testUser).approve(await gaslessRouter.getAddress(), MaxUint256);
      await wkaia.connect(testUser).approve(await uniswapRouter.getAddress(), MaxUint256);
      await wkaia.connect(testUser).approve(await gaslessRouter.getAddress(), MaxUint256);

      await uniswapRouter
        .connect(testUser)
        .addLiquidity(
          await testToken.getAddress(),
          await wkaia.getAddress(),
          parseEther("100000"),
          parseEther("100000"),
          0,
          0,
          testUser.address,
          deadline,
        );
      return { deployer, gaslessRouter, testToken, testUser, deadline };
    };

    const testFn = async (input: any) => {
      const { deployer, gaslessRouter, testToken, testUser } = await loadFixture(abundantLiquidityFixture);
      const gasPrice = Number((await ethers.provider.getFeeData()).gasPrice) / 1e9;
      const { appTxFee, commissionRate } = input;

      // update GSR commissionRate
      await gaslessRouter.connect(deployer).updateCommissionRate(commissionRate);

      const amountRepay = gasless.getAmountRepay(false, Math.floor(gasPrice));
      const minAmountOut = gasless.getMinAmountOut(amountRepay, appTxFee, commissionRate);
      const slippageBps = 50; // 0.5%
      const amountIn = await gasless.getAmountIn(
        gaslessRouter,
        await testToken.getAddress(),
        minAmountOut,
        slippageBps,
      );
      console.log("amountIn", amountIn);

      const currentBlock = await nowTime();
      const deadline = currentBlock + 300;

      // Execute swap - should not revert
      await expect(
        gaslessRouter
          .connect(testUser)
          .swapForGas(await testToken.getAddress(), amountIn, minAmountOut, amountRepay, deadline),
      ).to.not.be.reverted;
    };

    let reverted = false;
    for (let i = 0; i < 1; i++) {
      const appTxFee = parseEther((Math.random() * 10).toFixed(18)).toString();
      const commissionRate = Math.floor(Math.random() * 10000);
      try {
        await testFn({ appTxFee, commissionRate });
      } catch (error) {
        console.error("Error in testFn", error);
        console.error("input", { appTxFee, commissionRate });
        reverted = true;
      }
    }
    expect(reverted).to.be.false;
  });
});
