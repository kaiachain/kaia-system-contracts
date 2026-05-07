# Kaia System Contracts

This monorepo contains the official system contracts for the Kaia blockchain.

## Packages

| Package | Description |
|---------|-------------|
| [@kaiachain/system-contracts-klaytn-v1.0](./contracts-klaytn-v1.0) | Legacy Klaytn v1.0 contracts (AddressBook, CnStaking) |
| [@kaiachain/system-contracts-klaytn-v1.10](./contracts-klaytn-v1.10) | Klaytn v1.10 contracts (CnStakingV2, GovParam, StakingTracker) |
| [@kaiachain/system-contracts-klaytn-v1.12](./contracts-klaytn-v1.12) | Klaytn v1.12 contracts (Registry, SimpleBlsRegistry) |
| [@kaiachain/system-contracts-v1.0](./contracts-v1.0) | Kaia v1.0 contracts (CnStakingV3, PublicDelegation, Bridge) |
| [@kaiachain/system-contracts-v2.0](./contracts-v2.0) | Kaia v2.0 contracts (CLRegistry, StakingTrackerV2, GaslessSwapRouter) |
| [@kaiachain/system-contracts-v2.1](./contracts-v2.1) | Kaia v2.1 contracts (Auction) |
| [@kaiachain/system-contracts-v2.2](./contracts-v2.2) | Kaia v2.2 contracts (ValidatorManager, CnStakingV3MultiSigFactory, MultiCallContract(Flexible reward)) |
| [@kaiachain/system-contracts-v3.0](./contracts-v3.0) | Kaia v3.0 contracts (AddressBookV2, CnStakingV4, PublicDelegation, StakingTrackerV3, MultiCallContract) |

## Installation

```bash
npm install @kaiachain/system-contracts-v2.2
```

## Usage

Import contracts in your Solidity files:

```solidity
import "@kaiachain/system-contracts-v2.2/contracts/ValidatorManager.sol";
```

## Development

### Prerequisites

- Node.js >= 20
- Foundry (for contracts-v2.2)

### Setup

```bash
npm install
```

### Commands

```bash
# Compile all contracts
npm run compile

# Run all tests
npm test

# Run linter
npm run lint

# Clean build artifacts
npm run clean
```

## License

LGPL-3.0
