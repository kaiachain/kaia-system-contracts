import { Contract, Interface } from "ethers";
import { provider, signer } from "./config";

export const GovParam_ABI = new Interface([
  "function owner() external view returns (address)",
  "function transferOwnership(address newOwner) external",
  "function getAllParamNames() external view returns (string[] memory)",
  "function getParamAt(string calldata name, uint256 blockNumber) external view returns (bool, bytes memory)",
  "function getAllParamsAt(uint256 blockNumber) external view returns (string[] memory, bytes[] memory)",
  "function setParam(string calldata name, bool exists, bytes calldata value, uint256 activation) external",
  "function setParamIn(string calldata name, bool exists, bytes calldata value, uint256 relativeActivation) external",
  "function checkpoints(string calldata name) external view returns (tuple(uint256 activation, bool exists, bytes val)[] memory)",
  "function getAllCheckpoints() external view returns (string[] memory, tuple(uint256 activation, bool exists, bytes val)[][] memory)",
]);

export async function getGovParam() {
  const chainConfig = await provider.send("kaia_getChainConfig", ["latest"]);
  const govParamAddress = chainConfig.governance.govParamContract;
  if (govParamAddress === "0x0000000000000000000000000000000000000000") {
    throw new Error("GovParam contract not found");
  }
  return new Contract(govParamAddress, GovParam_ABI, signer);
}
