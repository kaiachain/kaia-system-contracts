import { Contract, Interface } from "ethers";
import { getActiveContractAddress } from "./registry";
import { signer } from "./config";

export const GSR_ABI = new Interface([
  "function owner() external view returns (address)",
  "function WKAIA() external view returns (address)",
  "function commissionRate() external view returns (uint256)",
  "function getSupportedTokens() external view returns (address[] memory)",
  "function getDEXInfo(address token) external view returns (address factory, address router)",
  "function claimCommission() external",
  "function updateCommissionRate(uint256 _commissionRate) external",
  "function addToken(address token, address factory, address router) external",
  "function removeToken(address token) external",
]);

export async function getGSR() {
  const address = await getActiveContractAddress("GaslessSwapRouter");
  return new Contract(address, GSR_ABI, signer);
}
