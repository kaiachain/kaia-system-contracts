import * as path from "path";
import { ethers, Interface } from "ethers";
import { config } from "dotenv";

// Load .env from project root
config({ path: path.resolve(__dirname, "../../.env") });

const defaultKey = "0x00000000000000000000000000000000000000000000000000000000cafebabe";

export const RPC_URL = process.env.RPC_URL;
export const PRIVATE_KEY = process.env.PRIVATE_KEY || defaultKey;

export const provider = new ethers.JsonRpcProvider(RPC_URL);
export const signer = new ethers.Wallet(PRIVATE_KEY, provider);
