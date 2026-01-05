import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ExtendedArtifact } from "hardhat-deploy/types";
import { ethers, Wallet } from "ethers";
import path from "path";
import fs from "fs";

// Re-export everything from common
export * from "@kaiachain/system-contracts-common/helpers/utils";

// v2.0-specific: hardhat-deploy integration
export async function importDeployment(
  hre: HardhatRuntimeEnvironment,
  name: string,
  address: string,
  artifacts?: ExtendedArtifact,
) {
  const { deployments } = hre;
  const { save, getExtendedArtifact } = deployments;

  try {
    await deployments.get(name);
    console.log(`reusing ${name} at ${address}`);
  } catch {
    if (artifacts == null) {
      artifacts = await getExtendedArtifact(name);
    }
    save(name, {
      address: address,
      ...artifacts,
    });
    console.log(`saving ${name} at ${address}`);
  }
}

export function getFromEnvOrGenerate(hre: HardhatRuntimeEnvironment, envName: string) {
  if (!process.env[envName]) {
    const eoa = ethers.Wallet.createRandom().connect(hre.ethers.provider);
    const envPath = path.resolve(__dirname, "../.env");
    fs.appendFileSync(envPath, `\n${envName}=${eoa.privateKey}`);
    return eoa as unknown as Wallet;
  } else {
    return new Wallet(process.env[envName]!, hre.ethers.provider);
  }
}
