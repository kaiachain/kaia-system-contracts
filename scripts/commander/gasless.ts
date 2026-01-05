// commander/gasless.ts
import { formatEther, isAddress } from "ethers";
import { getGSR, provider } from "../utils";

function getErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

export async function gaShowInfo(): Promise<void> {
  try {
    const router = await getGSR();

    try {
      console.log("\nGaslessSwapRouter Configuration:");
      try {
        const [owner, wkaia, commissionRate, supportedTokens] = await Promise.all([
          router.owner().catch(() => "Error fetching owner"),
          router.WKAIA().catch(() => "Error fetching WKAIA"),
          router.commissionRate().catch(() => "Error fetching commissionRate"),
          router.getSupportedTokens().catch(() => "Error fetching supported tokens"),
        ]);

        console.log("- Owner:", owner);
        console.log("- WKAIA:", wkaia);
        console.log("- Commission Rate:", commissionRate.toString());
        console.log("- Supported Tokens:", supportedTokens);

        // Display DEX information for each supported token if any exist
        if (supportedTokens && supportedTokens.length > 0) {
          console.log("\nDEX Information for Supported Tokens:");
          for (const token of supportedTokens) {
            try {
              const dexInfo = await router.getDEXInfo(token);
              console.log(`- Token ${token}:`);
              console.log(`  Factory: ${dexInfo.factory}`);
              console.log(`  Router: ${dexInfo.router}`);
            } catch (error) {
              console.log(`- Token ${token}: Error fetching DEX info`);
            }
          }
        }

        // Try to get contract balance instead of accumulated commission
        try {
          const balance = await provider.getBalance(router.target);
          console.log("- Contract Balance:", formatEther(balance), "KAIA");
        } catch (error) {
          console.log("- Error fetching contract balance");
        }
      } catch (error) {
        console.log("Error fetching GaslessSwapRouter configuration:", getErrorMessage(error));
      }
    } catch (error) {
      console.log("Error creating contract instance:", getErrorMessage(error));
    }
  } catch (error) {
    console.error("Error fetching deployment info:", getErrorMessage(error));
  }
}

export async function gaAddToken(tokenAddress: string, factoryAddress: string, routerAddress: string): Promise<void> {
  try {
    // Add input validation
    if (!isAddress(factoryAddress)) {
      throw new Error(`Invalid factory address: ${factoryAddress}`);
    }
    if (!isAddress(tokenAddress)) {
      throw new Error(`Invalid token address: ${tokenAddress}`);
    }
    if (!isAddress(routerAddress)) {
      throw new Error(`Invalid router address: ${routerAddress}`);
    }

    const router = await getGSR();
    const owner = await router.owner();
    console.log(`GaslessSwapRouter Owner: ${owner}`);

    console.log(
      `Adding token ${tokenAddress} with factory ${factoryAddress} and router ${routerAddress} to GaslessSwapRouter...`,
    );

    const tx = await router.addToken(tokenAddress, factoryAddress, routerAddress, {
      gasLimit: 300000,
    });

    console.log("Transaction sent, waiting for confirmation...");
    const receipt = await tx.wait();

    console.log(`Token added successfully! Gas used: ${receipt.gasUsed.toString()}`);

    // Verify the token was added
    const isSupported = await router.isTokenSupported(tokenAddress);
    const dexInfo = await router.getDEXInfo(tokenAddress);

    console.log("\nVerification:");
    console.log(`- Token supported: ${isSupported}`);
    console.log(`- Registered Factory: ${dexInfo.factory}`);
    console.log(`- Registered Router: ${dexInfo.router}`);
  } catch (error) {
    console.error("Failed to add token:", getErrorMessage(error));
    throw error;
  }
}

export async function gaRemoveToken(tokenAddress: string): Promise<void> {
  try {
    const router = await getGSR();
    console.log(`Removing token ${tokenAddress} from GaslessSwapRouter...`);

    const tx = await router.removeToken(tokenAddress, {
      gasLimit: 300000,
    });

    console.log("Transaction sent, waiting for confirmation...");
    const receipt = await tx.wait();

    console.log(`Token removed successfully! Gas used: ${receipt.gasUsed.toString()}`);

    // Verify the token was removed
    const isSupported = await router.isTokenSupported(tokenAddress);
    console.log("\nVerification:");
    console.log(`- Token supported: ${isSupported}`);
  } catch (error) {
    console.error("Failed to remove token:", getErrorMessage(error));
    throw error;
  }
}

export async function gaClaimCommission(): Promise<void> {
  try {
    const router = await getGSR();
    console.log("Claiming commission...");

    const tx = await router.claimCommission({
      gasLimit: 300000,
    });

    console.log("Transaction sent, waiting for confirmation...");
    const receipt = await tx.wait();

    console.log(`Commission claimed successfully! Gas used: ${receipt.gasUsed.toString()}`);
  } catch (error) {
    console.error("Failed to claim commission:", getErrorMessage(error));
    throw error;
  }
}

export async function gaUpdateCommissionRate(newRate: string): Promise<void> {
  try {
    const router = await getGSR();
    const rate = BigInt(newRate);
    console.log(`Updating commission rate to ${rate.toString()}...`);

    const tx = await router.updateCommissionRate(rate, {
      gasLimit: 300000,
    });

    console.log("Transaction sent, waiting for confirmation...");
    const receipt = await tx.wait();

    console.log(`Commission rate updated successfully! Gas used: ${receipt.gasUsed.toString()}`);
  } catch (error) {
    console.error("Failed to update commission rate:", getErrorMessage(error));
    throw error;
  }
}

export async function gaTransferOwnership(address: string) {
  const router = await getGSR();
  const tx = await router.transferOwnership(address);
  await tx.wait();
  console.log(`Transferred ownership to ${address}`);
}
