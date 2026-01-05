# @kaiachain/system-contracts-klaytn-v1.10

Klaytn v1.10 system contracts.

## Contracts

| Contract | Description |
|----------|-------------|
| CnStakingV2 | Consensus node staking contract v2 |
| GovParam | On-chain governance parameters |
| StakingTracker | Tracks staking amounts across all CNs |
| TreasuryRebalance | Treasury fund rebalancing (KIP-103) |
| Voting | On-chain voting for governance |

## Installation

```bash
npm install @kaiachain/system-contracts-klaytn-v1.10
```

## Usage

```solidity
import "@kaiachain/system-contracts-klaytn-v1.10/contracts/CnStakingV2.sol";
import "@kaiachain/system-contracts-klaytn-v1.10/contracts/GovParam.sol";
import "@kaiachain/system-contracts-klaytn-v1.10/contracts/StakingTracker.sol";
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
