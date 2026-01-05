# @kaiachain/system-contracts-v2.0

Kaia v2.0 system contracts.

## Contracts

### Staking

| Contract         | Description                        |
| ---------------- | ---------------------------------- |
| CLRegistry       | Consensus layer registry (KIP-226) |
| StakingTrackerV2 | Staking tracker v2 (KIP-226)       |

### Gasless Transaction

| Contract          | Description                         |
| ----------------- | ----------------------------------- |
| GaslessSwapRouter | Gasless token swap router (KIP-247) |
| WKAIA             | Wrapped KAIA token                  |

### Utility

| Contract          | Description                   |
| ----------------- | ----------------------------- |
| MultiCallContract | Batch multiple contract calls |
| EIP2537           | BLS12-381 precompile wrapper  |

## Installation

```bash
npm install @kaiachain/system-contracts-v2.0
```

## Usage

```solidity
import "@kaiachain/system-contracts-v2.0/contracts/CLRegistry.sol";
import "@kaiachain/system-contracts-v2.0/contracts/StakingTrackerV2.sol";
import "@kaiachain/system-contracts-v2.0/contracts/gasless/GaslessSwapRouter.sol";
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
