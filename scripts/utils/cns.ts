import { Contract, Interface, JsonRpcProvider } from "ethers";
import { config } from "dotenv";
import * as path from "path";

config({ path: path.resolve(__dirname, "../.env") });

// Common methods for CnStaking
export const CnStaking_ABI = new Interface([
  "function acceptRewardAddress(address _rewardAddress) external",
  "function reviewInitialConditions() external",
  "function VERSION() external view returns (uint256)",
  "function stakingTracker() external view returns (uint256)",
]);

export const PENDING_REWARD_ADDRESS = process.env.PENDING_REWARD_ADDRESS;
export const CN_TARGET_ADDRESS = process.env.CN_TARGET_ADDRESS;

export async function getCnVersion(addr: string, provider: JsonRpcProvider) {
  const cn = new Contract(addr, ["function VERSION() view returns (uint256)"], provider);
  return Number(await cn.VERSION());
}

export async function getCnStaking(addr: string, provider: JsonRpcProvider) {
  const cn = new Contract(addr, CnStaking_ABI, provider);
  return cn;
}
