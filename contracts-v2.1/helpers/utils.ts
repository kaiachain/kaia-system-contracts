import _ from "lodash";

// Re-export everything from common
export * from "@kaiachain/system-contracts-common/helpers/utils";

// v2.1-specific: Auction utilities

export const typeDataAuctionTx = {
  types: {
    AuctionTx: [
      { name: "targetTxHash", type: "bytes32" },
      { name: "blockNumber", type: "uint256" },
      { name: "sender", type: "address" },
      { name: "to", type: "address" },
      { name: "nonce", type: "uint256" },
      { name: "bid", type: "uint256" },
      { name: "callGasLimit", type: "uint256" },
      { name: "data", type: "bytes" },
    ],
  },
  domain: {
    name: "KAIA_AUCTION",
    version: "0.0.1",
    chainId: 31337,
    verifyingContract: "",
  },
  primaryType: "AuctionTx",
  message: {
    targetTxHash: "",
    sender: "",
    to: "",
    nonce: 0,
    blockNumber: 0,
    callGasLimit: 0,
    bid: 0n,
    data: "",
  },
};

export interface typeDataArgs {
  verifyingContract: string;
  targetTxHash: string;
  blockNumber: number;
  sender: string;
  to: string;
  nonce: number;
  bid: string;
  callGasLimit: number;
  data: string;
}

export function fillTypeDataArgs(args: typeDataArgs) {
  const typeData = _.cloneDeep(typeDataAuctionTx);

  typeData.domain.verifyingContract = args.verifyingContract;

  typeData.message.targetTxHash = args.targetTxHash;
  typeData.message.blockNumber = args.blockNumber;
  typeData.message.sender = args.sender;
  typeData.message.to = args.to;
  typeData.message.nonce = args.nonce;
  typeData.message.bid = BigInt(args.bid);
  typeData.message.callGasLimit = args.callGasLimit;
  typeData.message.data = args.data;

  return typeData;
}
