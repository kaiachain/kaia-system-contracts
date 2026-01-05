import hre, { ethers } from "hardhat";
import { getContractFromDeployment, getFromEnvOrGenerate } from "../../../helpers/utils";
import { parseEther, formatEther } from "@ethersproject/units";
import { TestToken } from "../../../typechain-types";

async function main() {
  console.log("\n1. Sending test tokens to test user...");
  const [deployer] = await ethers.getSigners();
  let testToken = (await getContractFromDeployment(hre, "TestToken")) as unknown as TestToken;
  const tester = getFromEnvOrGenerate(hre, "TESTER");

  // Check deployer's test token balance
  const deployerTokenBalance = await testToken.balanceOf(deployer.address);
  console.log(`Deployer's test token balance before transfer: ${formatEther(deployerTokenBalance)} TT`);

  const transferAmount = parseEther("100").toBigInt();
  testToken = testToken.connect(deployer);
  const transferTx = await testToken.transfer(tester.address, transferAmount);
  await transferTx.wait();

  // Check test user's test token balance
  const testUserTokenBalance = await testToken.balanceOf(tester.address);
  console.log(`Test user's test token balance: ${formatEther(testUserTokenBalance)} TT`);

  // Verify test user has test tokens but zero KAIA
  const testUserKaiaBalance = await ethers.provider.getBalance(tester.address);
  console.log(`Test user's KAIA balance: ${formatEther(testUserKaiaBalance)} KAIA`);

  if (testUserTokenBalance > 0n) {
    console.log("✅ Test user has test tokens");
  } else {
    console.log("⚠️ Test user setup issue: Missing test tokens");
  }
}

// Execute the script
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
