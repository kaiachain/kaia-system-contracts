import { Contract, Interface } from "ethers";
import { getActiveContractAddress } from "./registry";
import { signer } from "./config";
import loadBls from "bls-signatures";
import { ModuleInstance } from "bls-signatures";

export const SBR_ABI = new Interface([
  "function register(address cnNodeId, bytes calldata publicKey, bytes calldata pop) external",
  "function unregister(address cnNodeId) external",
  "function getAllBlsInfo() external view returns (address[] memory nodeIdList, tuple(bytes publicKey, bytes pop)[] memory pubkeyList)",
]);

export async function getSBR() {
  const address = await getActiveContractAddress("KIP113");
  return new Contract(address, SBR_ABI, signer);
}

let BLS: ModuleInstance;

export type BlsPublicKeyInfo = {
  pop: string;
  publicKey: string;
};

export type BlsPublicInfoFile = {
  address: string;
  blsPublicKeyInfo: BlsPublicKeyInfo;
};

export async function validatePop(publicKey: string, pop: string) {
  if (BLS == null) {
    BLS = await loadBls();
  }

  if (publicKey.startsWith("0x")) {
    publicKey = publicKey.substring(2);
  }
  if (pop.startsWith("0x")) {
    pop = pop.substring(2);
  }

  const pubkeyBuf = BLS.G1Element.from_bytes(new Uint8Array(Buffer.from(publicKey, "hex")));
  const popBuf = BLS.G2Element.from_bytes(new Uint8Array(Buffer.from(pop, "hex")));
  return BLS.PopSchemeMPL.pop_verify(pubkeyBuf, popBuf);
}
