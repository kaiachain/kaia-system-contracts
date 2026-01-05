import { Contract, Interface } from "ethers";
import { signer } from "./config";

export const REGISTRY_ADDRESS = "0x0000000000000000000000000000000000000401";
export const Registry_ABI = new Interface([
  "function getActiveAddr(string memory name) external view returns (address)",
  "function owner() external view returns (address)",
  "function getAllNames() external view returns (string[] memory)",
  "function getAllRecords(string memory name) external view returns (tuple(address addr, uint256 activation)[] memory)",
  "function register(string memory name, address addr, uint256 activation) external",
]);

export function getRegistry(): Contract {
  return new Contract(REGISTRY_ADDRESS, Registry_ABI, signer);
}

export async function getActiveContractAddress(contractName: string): Promise<string> {
  const registry = getRegistry();
  const address = await registry.getActiveAddr(contractName);
  if (address === "0x0000000000000000000000000000000000000000") {
    throw new Error(`No active address found for ${contractName}`);
  }
  return address;
}
