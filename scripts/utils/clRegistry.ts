import { Contract, Interface } from "ethers";
import { getActiveContractAddress } from "./registry";
import { signer } from "./config";

export const CLRegistry_ABI = new Interface([
  "function getAllCLs() external view returns (address[] memory, uint256[] memory, address[] memory)",
  "function getAllGCIds() external view returns (uint256[] memory)",
  "function addCLPair(tuple(address nodeId, uint256 gcId, address clPool)[] calldata list) external",
  "function removeCLPair(uint256 gcId) external",
  "function clPoolList(uint256 gcId) external view returns (tuple(address nodeId, uint256 gcId, address clPool))",
]);

export async function getCLRegistry() {
  const address = await getActiveContractAddress("CLRegistry");
  return new Contract(address, CLRegistry_ABI, signer);
}
