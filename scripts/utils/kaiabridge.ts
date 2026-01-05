import { Contract, Interface } from "ethers";
import { config } from "dotenv";
import * as path from "path";
import { provider, signer } from "./config";

config({ path: path.resolve(__dirname, "../.env") });

export const HolderVerifier_ABI = new Interface([
  "function getRecord(string calldata fnsaAddr) external view returns (uint256 conyBalance, uint64 seq)",
  "function getRecords(uint256 startIdx, uint256 maxCount) external view returns (string[] memory fnsaAddrsResult, uint256[] memory conyBalancesResult, uint64[] memory seqs)",
  "function getRecordCount() external view returns (uint256)",
  "function allConyBalances() external view returns (uint256)",
  "function provisionedConyBalances() external view returns (uint256)",
  "function provisionedAccounts() external view returns (uint256)",
  "function addRecord(string calldata fnsaAddr, uint256 conyBalance) external",
  "function addRecords(string[] calldata fnsaAddrs, uint256[] calldata conyBalances) external",
  "function owner() external view returns (address)",
]);

export const Operator_ABI = new Interface(["function addOperator(address operator) external"]);
export const Guardian_ABI = new Interface([
  "function submitTransaction(address to, bytes calldata data, uint256 uniqUserTxIndex) external returns (uint64)",
]);

export const HOLDER_VERIFIER_ADDRESS = process.env.HOLDER_VERIFIER_ADDRESS;
export function getHolderVerifier(): Contract {
  if (HOLDER_VERIFIER_ADDRESS == null) {
    throw new Error("HOLDER_VERIFIER_ADDRESS is not set");
  }
  return new Contract(HOLDER_VERIFIER_ADDRESS, HolderVerifier_ABI, signer);
}

export function getOperator(address: string): Contract {
  return new Contract(address, Operator_ABI, signer);
}

export function getGuardian(address: string): Contract {
  return new Contract(address, Guardian_ABI, signer);
}

export async function getNetworkName(): Promise<string> {
  const network = await provider.getNetwork();
  if (Number(network.chainId) == 8217) {
    return "mainnet";
  } else if (Number(network.chainId) == 1001) {
    return "kairos";
  } else {
    throw new Error("Unknown network");
  }
}
