import { Contract, Interface } from "ethers";
import { signer } from "./config";

export const VMC_ADDRESS = process.env.VMC_ADDRESS;
export const VMC_ABI = new Interface([
  "function getNodeInfo(address consensusNodeId) external view returns ((address, address, address[]))",
]);

export function getVMC(): Contract {
  if (VMC_ADDRESS == null) {
    throw new Error("VMC_ADDRESS is not set");
  }
  return new Contract(VMC_ADDRESS, VMC_ABI, signer);
}
