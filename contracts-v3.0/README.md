# @kaiachain/system-contracts-v3.0

Kaia v3.0 system contracts.

## Contracts

### AddressBook

| Contract | Description |
| --- | --- |
| AddressBookV2 | Unified validator/candidate lifecycle manager (KIP-286) |
| ABv2DataContract | Read-only genesis data for hardfork initialization |

### CnStaking

| Contract | Description |
| --- | --- |
| CnStakingV4 | CN staking contract v4 with UUPS upgradeability |
| CnStakingV4Factory | Factory for deploying CnStakingV4 proxies |

### PublicDelegation

| Contract | Description |
| --- | --- |
| PublicDelegation | Public delegation contract for validator staking |

### Proxy

| Contract | Description |
| --- | --- |
| ERC1967Proxy | ERC-1967 transparent proxy |
| UpgradeableBeacon | Beacon for beacon proxy pattern |

### Libraries

| Contract | Description |
| --- | --- |
| SlotMath | BFT slot calculations for validator set sizing |
| NodeVerifier | Input validation and address uniqueness checks |

## Installation

```bash
npm install @kaiachain/system-contracts-v3.0
```

## Usage

```solidity
import "@kaiachain/system-contracts-v3.0/src/AddressBookV2/AddressBookV2.sol";
import "@kaiachain/system-contracts-v3.0/src/CnStaking/CnStakingV4/CnStakingV4.sol";
import "@kaiachain/system-contracts-v3.0/src/PublicDelegation/PublicDelegation.sol";
```

## Development

```bash
# Compile contracts (Foundry)
# AddressBookV2 is compiled with via_ir=true (required for contract size); other contracts use via_ir=false
forge build

# Run tests (full, accurate)
forge test

# Run tests (fast, via_ir disabled for all contracts including AddressBookV2)
# Note: tests that deploy AddressBookV2 may fail due to contract size limit
FOUNDRY_PROFILE=lite forge test

# Format
forge fmt
```

## License

LGPL-3.0
