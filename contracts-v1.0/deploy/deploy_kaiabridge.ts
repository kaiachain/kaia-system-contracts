import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const name = "KAIABridge";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { ethers, upgrades, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();
  const signer = await ethers.getSigner(deployer);

  console.log(`Deploying KAIABridge contracts with account:`, deployer);

  // Configuration - minimal setup
  const minOperatorRequiredConfirm = 1;
  const minGuardianRequiredConfirm = 1;
  const minJudgeRequiredConfirm = 1;
  const maxTryTransfer = 3;

  // Deploy Guardian
  const guardianFactory = await ethers.getContractFactory("Guardian", signer);
  const guardian = await upgrades.deployProxy(guardianFactory, [[deployer], minGuardianRequiredConfirm]);
  await guardian.waitForDeployment();
  console.log("Guardian deployed at:", guardian.target);

  // Deploy Operator
  const operatorFactory = await ethers.getContractFactory("Operator", signer);
  const operator = await upgrades.deployProxy(operatorFactory, [
    [deployer],
    guardian.target,
    minOperatorRequiredConfirm,
  ]);
  await operator.waitForDeployment();
  console.log("Operator deployed at:", operator.target);

  // Deploy Judge
  const judgeFactory = await ethers.getContractFactory("Judge", signer);
  const judge = await upgrades.deployProxy(judgeFactory, [[deployer], guardian.target, minJudgeRequiredConfirm]);
  await judge.waitForDeployment();
  console.log("Judge deployed at:", judge.target);

  // Deploy KAIABridge
  const bridgeFactory = await ethers.getContractFactory("KAIABridge", signer);
  const bridge = await upgrades.deployProxy(bridgeFactory, [
    operator.target,
    guardian.target,
    judge.target,
    maxTryTransfer,
  ]);
  await bridge.waitForDeployment();
  console.log(`Bridge deployed at:`, bridge.target);

  // Initialize: Set bridge address in operator
  const rawTxData = (await operator.changeBridge.populateTransaction(bridge.target)).data;
  let tx = await guardian.submitTransaction(operator.target, rawTxData, 0);
  await tx.wait();

  // Set transfer timelock to 0
  const timelockData = (await bridge.changeTransferTimeLock.populateTransaction(0)).data;
  tx = await guardian.submitTransaction(bridge.target, timelockData, 0);
  await tx.wait();

  console.log("KAIABridge initialization complete");
};

func.tags = [name];

export default func;
