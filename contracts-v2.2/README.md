# @kaiachain/system-contracts-v2.2

Kaia v2.2 system contracts.

## Contracts

### Validator Manager

| Contract         | Description                                            |
| ---------------- | ------------------------------------------------------ |
| ValidatorManager | Manages validator registration and lifecycle (KIP-277) |

### Bridge

| Contract       | Description                           |
| -------------- | ------------------------------------- |
| HolderVerifier | Verifies FNSA token holder signatures |

### Staking Factory

| Contract                   | Description                               |
| -------------------------- | ----------------------------------------- |
| CnStakingV3MultiSigFactory | Factory for deploying CnStakingV3MultiSig |
| PublicDelegationFactoryV2  | V2 Factory for deploying PublicDelegation |

## Installation

```bash
npm install @kaiachain/system-contracts-v2.2
```

## Usage

```solidity
import "@kaiachain/system-contracts-v2.2/contracts/ValidatorManager.sol";
import "@kaiachain/system-contracts-v2.2/contracts/HolderVerifier.sol";
import "@kaiachain/system-contracts-v2.2/contracts/CnStakingV3MultiSigFactory/CnStakingV3MultiSigFactory.sol";
```

## Development

```bash
# Compile contracts (Hardhat)
npm run compile

# Run tests (Hardhat + Forge)
npm test
```

## License

LGPL-3.0
