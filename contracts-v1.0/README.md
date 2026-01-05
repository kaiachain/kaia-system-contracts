# @kaiachain/system-contracts-v1.0

Kaia v1.0 system contracts.

## Contracts

### Staking

| Contract            | Description                                         |
| ------------------- | --------------------------------------------------- |
| CnStakingV3MultiSig | Multi-signature extension for CnStakingV3 (KIP-163) |

### Public Delegation

| Contract                | Description                                  |
| ----------------------- | -------------------------------------------- |
| PublicDelegation        | Public staking delegation contract (KIP-163) |
| PublicDelegationFactory | Factory for deploying PublicDelegation       |

### Bridge

| Contract | Description                |
| -------- | -------------------------- |
| Bridge   | Kaia bridge contract       |
| Guardian | Bridge guardian management |
| Operator | Bridge operator management |
| Judge    | Bridge dispute resolution  |

### TreasuryRebalance

| Contract            | Description                       |
| ------------------- | --------------------------------- |
| TreasuryRebalanceV2 | Treasury rebalancing v2 (KIP-160) |

### Miscs

| Contract  | Description                |
| --------- | -------------------------- |
| Airdrop   | Token airdrop distribution |
| Lockup    | Token lockup management    |
| Delegator | Delegation proxy contract  |

### Utility

| Contract          | Description                   |
| ----------------- | ----------------------------- |
| MultiCallContract | Batch multiple contract calls |

## Installation

```bash
npm install @kaiachain/system-contracts-v1.0
```

## Usage

```solidity
import "@kaiachain/system-contracts-v1.0/contracts/CnStakingV3/CnStakingV3.sol";
import "@kaiachain/system-contracts-v1.0/contracts/PublicDelegation/PublicDelegation.sol";
import "@kaiachain/system-contracts-v1.0/contracts/TreasuryRebalanceV2.sol";
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
