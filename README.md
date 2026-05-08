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

You can also use interfaces to interact with on-chain system contracts. For example, reading CN reward addresses from the AddressBook:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@kaiachain/system-contracts-klaytn-v1.10/contracts/interfaces/IAddressBook.sol";

contract AddressBookReader {
    address constant ADDRESS_BOOK = 0x0000000000000000000000000000000000000400;

    function getRewardAddresses() external view returns (address[] memory) {
        (, address[] memory addressList) = IAddressBook(ADDRESS_BOOK).getAllAddress();
        uint256 cnCount = (addressList.length - 2) / 3;
        address[] memory rewards = new address[](cnCount);
        for (uint256 i = 0; i < cnCount; i++) {
            rewards[i] = addressList[i * 3 + 2];
        }
        return rewards;
    }
}
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
