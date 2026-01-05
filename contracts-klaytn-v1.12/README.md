# @kaiachain/system-contracts-klaytn-v1.12

Klaytn v1.12 system contracts.

## Contracts

| Contract          | Description                        |
| ----------------- | ---------------------------------- |
| Registry          | System contract registry (KIP-149) |
| SimpleBlsRegistry | BLS public key registry (KIP-113)  |

## Installation

```bash
npm install @kaiachain/system-contracts-klaytn-v1.12
```

## Usage

```solidity
import "@kaiachain/system-contracts-klaytn-v1.12/contracts/Registry.sol";
import "@kaiachain/system-contracts-klaytn-v1.12/contracts/SimpleBlsRegistry.sol";
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
