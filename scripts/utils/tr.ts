import { Contract, Interface } from "ethers";
import { provider } from "./config";

export const TREASURY_REBALANCE_V2_ADDRESS = process.env.TREASURY_REBALANCE_V2_ADDRESS;
export const TreasuryRebalanceV2_ABI = new Interface([
  "function getZeroedCount() external view returns (uint256)",
  "function getAllocatedCount() external view returns (uint256)",
  "function zeroeds(uint256) external view returns (address)",
  "function allocateds(uint256) external view returns (address, uint256)",
  "function rebalanceBlockNumber() external view returns (uint256)",
  "function status() external view returns (uint256)",
  "function pendingMemo() external view returns (string)",
  "function memo() external view returns (string)",
  "function setPendingMemo(string _memo) external",
  "function approve(address _zeroed) external",
  "function registerZeroed(address _zeroed) external",
  "function registerAllocated(address _allocated, uint256 _amount) external",
  "function removeZeroed(address _zeroed) external",
  "function removeAllocated(address _allocated) external",
  "function finalizeApproval() external",
  "function finalizeRegistration() external",
  "function finalizeContract() external",
  "function reset() external",
  "function updateRebalanceBlocknumber(uint256 _newBN) external",
  "function transferOwnership(address _newOwner) external",
  "function checkZeroedsApproved() external view",
]);

export function getTreasuryRebalanceV2(): Contract {
  if (TREASURY_REBALANCE_V2_ADDRESS == null) {
    throw new Error("TREASURY_REBALANCE_V2_ADDRESS is not set");
  }
  return new Contract(TREASURY_REBALANCE_V2_ADDRESS, TreasuryRebalanceV2_ABI, provider);
}
