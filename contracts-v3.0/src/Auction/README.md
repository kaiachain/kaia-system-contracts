# Auction (v3.0)

The Auction contracts in v3.0 ships **only the two contracts that changed** from v2.1. The deposit vault is not redeployed — v3.0 contracts talk to the **existing v2.1 `AuctionDepositVault` deployment** through the same ABI.

## Overview

| Contract               | Changed? | Description                                                                                                                              |
| ---------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `AuctionEntryPoint`    | **Yes**  | Logic changed: gasprice upper-bound check in `_verifyInputIntegrity` + `AuctionTx.maxGasPrice` added to the EIP-712 payload.             |
| `AuctionFeeVault`      | **Yes**  | Logic changed: `registerRewardAddress` now auth's via `AddressBookV2(0x...0400).getNodeInfo(nodeId).manager` instead of CnStaking admin. |
| `AuctionDepositVault`  | **No**   | Source unchanged — reuses the audited v2.1 deployment. Not present in `src/` of v3.0.                                                    |
| `IAuctionDepositVault` | **No**   | ABI-verbatim copy of v2.1's interface (header note only). Provided so v3.0 compiles without a cross-repo path.                           |

```
src/Auction/
├── AuctionEntryPoint.sol       ← modified
├── AuctionFeeVault.sol         ← modified
├── AuctionError.sol            ← +OnlyNodeManager, −OnlyStakingAdmin
└── interfaces/
    ├── IAuctionEntryPoint.sol  ← AuctionTx.maxGasPrice added (typehash changed)
    ├── IAuctionFeeVault.sol    ← RewardAddressRegistered adds indexed `caller`
    └── IAuctionDepositVault.sol ← verbatim from v2.1
```

## Diff summary

### AuctionEntryPoint — gasprice upper-bound check

The signed `AuctionTx` payload now includes `maxGasPrice` — the **ceiling** on the effective gas price the searcher authorizes the proposer to land the bundle at. On-chain check:

```solidity
if (tx.gasprice > auctionTx.maxGasPrice) {
    return false; // _verifyInputIntegrity rejects → call() reverts
}
```

Consequences:

- **EIP-712 typehash changed.** Off-chain signers must update their EIP-712 type definition to include `uint256 maxGasPrice` (immediately after `bid`).
- `AUCTION_VERSION` is kept at `"0.0.1"`. Cross-version signature replay is already structurally prevented because the v3.0 EntryPoint is a fresh deployment, so `verifyingContract` in the EIP-712 domain separator differs from v2.1's.
- The proposer (block.coinbase) cannot land a signed bundle at a higher effective gas price than the searcher authorized. The threat is one-directional — over-charging harms the searcher; under-charging does not — so an upper bound is sufficient and lets searchers sign a ceiling without predicting EIP-1559 `baseFee` at the target block. The naming aligns with EIP-1559's `maxFeePerGas`.

### AuctionFeeVault — manager auth on `registerRewardAddress`

```solidity
function registerRewardAddress(address nodeId, address rewardAddr) external override {
    NodeInfo memory info = IAddressBookV2(ADDRESS_BOOK).getNodeInfo(nodeId);
    if (info.manager == address(0) || msg.sender != info.manager) revert OnlyNodeManager();
    ...
}
```

- Replaces v2.1's two-hop `AddressBook.getCnInfo → CnStaking.isAdmin` check with a one-hop `AddressBookV2.getNodeInfo(...).manager` lookup.
- Nodes that have never been `createNode()`'d in AddressBookV2 have `manager == 0`, so the zero-manager guard explicitly rejects unknown nodes.
- Owner-only `registerRewardAddresses` (plural, bootstrap path) is unchanged.

The `RewardAddressRegistered` event gains an indexed `caller` field so indexers can distinguish owner-batch from manager-driven updates.

## Integration notes

### Off-chain signers (searchers, auctioneer)

EIP-712 type (note `maxGasPrice` between `bid` and `callGasLimit`):

```
AuctionTx(
  bytes32 targetTxHash,
  uint256 blockNumber,
  address sender,
  address to,
  uint256 nonce,
  uint256 bid,
  uint256 maxGasPrice,
  uint256 callGasLimit,
  bytes data
)
```

Domain:

```
EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)
name             = "KAIA_AUCTION"
version          = "0.0.1"
chainId          = <kaia chain id>
verifyingContract = <AuctionEntryPoint v3.0 address>
```

The submitter MUST keep the effective `tx.gasprice` at or below the signed `maxGasPrice`. The auctioneer signature is unchanged: it is `eth_sign(searcherSig)` (i.e. `personal_sign` over the raw `searcherSig` bytes).

### On-chain integration with the existing DepositVault

The v3.0 `AuctionEntryPoint` is wired to the existing v2.1 `AuctionDepositVault` via its constructor. The DepositVault gates `onlyEntryPoint` by looking up `Registry(0x...0401).getActiveAddr("AuctionEntryPoint")`, which will be updated to point to the v3.0 `AuctionEntryPoint` address accordingly.
