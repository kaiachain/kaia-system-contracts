# @kaiachain/system-contracts-v2.1

Kaia v2.1 system contracts.

## Contracts

### Auction

| Contract            | Description                                        |
| ------------------- | -------------------------------------------------- |
| AuctionEntryPoint   | Main entry point for block space auction (KIP-249) |
| AuctionDepositVault | Manages auction deposits                           |
| AuctionFeeVault     | Collects and distributes auction fees              |

## Installation

```bash
npm install @kaiachain/system-contracts-v2.1
```

## Usage

```solidity
import "@kaiachain/system-contracts-v2.1/contracts/auction/AuctionEntryPoint.sol";
import "@kaiachain/system-contracts-v2.1/contracts/auction/AuctionDepositVault.sol";
import "@kaiachain/system-contracts-v2.1/contracts/auction/AuctionFeeVault.sol";
```

## Development

```bash
# Compile contracts
npm run compile

# Run tests
npm test
```

## License

LGPL-3.0
