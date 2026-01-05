# Scripts

This contains various scripts for managing and interacting with the Kaia system contracts. The scripts are organized into different categories based on their functionality.

## Overview

The script directory contains the following main components:

- **Commander CLI** (`commander.ts`) - Main command-line interface for contract interactions
- **Miscellaneous Scripts** (`miscs/`) - Utility scripts for various operations

## Commander CLI

The main command-line interface provides a unified way to interact with all system contracts.

### Usage

```bash
# Set the correct RPC URL
echo "RPC_URL=https://..." >> .env

# Set the correct private key
echo "PRIVATE_KEY=0x..." >> .env

# Run the commander script
npx ts-node script/commander.ts [command] [subcommand] [options]
```

### Available Commands

#### AddressBook (`abook`)

```bash
# Show GC info by various criteria
npx ts-node script/commander.ts abook gc-info --idx 0
npx ts-node script/commander.ts abook gc-info --node 0x1234...
npx ts-node script/commander.ts abook gc-info --cns 0x1234...
npx ts-node script/commander.ts abook gc-info --reward 0x1234...
npx ts-node script/commander.ts abook gc-info --gcid GC_ID

# Show all registered GCs
npx ts-node script/commander.ts abook info
npx ts-node script/commander.ts abook info --csv

# Show AddressBook status
npx ts-node script/commander.ts abook status
```

#### CnStaking (`cns`)

Manage CnStaking contracts (V2, V3).

```bash
# Show staking tracker for all CnStaking contracts (V2 or later)
npx ts-node script/commander.ts cns show-tracker

# Encode Public Delegation parameters for V3
npx ts-node script/commander.ts cns encode <owner> <commissionTo> <commissionRate> <gcName>
```

#### CL Registry (`clreg`)

Manage Consensus Layer registry.

```bash
# Show CL Registry info
npx ts-node script/commander.ts clreg info

# Add CL pair
npx ts-node script/commander.ts clreg add <nodeid> <gcid> <clpool>

# Remove CL pair
npx ts-node script/commander.ts clreg remove <gcid>
```

#### Registry (`reg`)

Manage general contract registry.

```bash
# Show registry info
npx ts-node script/commander.ts reg info

# Register a contract
npx ts-node script/commander.ts reg register <name> <addr> <activation>
```

#### Simple BLS Registry (`sbr`)

Manage BLS key registrations for consensus nodes.

```bash
# Show BLS registry info
npx ts-node script/commander.ts sbr info

# Verify BLS key
npx ts-node script/commander.ts sbr verify <nodeId> <pubkey> <pop>
npx ts-node script/commander.ts sbr verify --file ./bls-publicinfo.json

# Register BLS key
npx ts-node script/commander.ts sbr register <nodeId> <pubkey> <pop>
npx ts-node script/commander.ts sbr register --file ./bls-publicinfo.json

# Unregister BLS key
npx ts-node script/commander.ts sbr unregister <nodeId>
```

#### Treasury Rebalance V2 (`trV2`)

Manage treasury rebalancing operations.

```bash
# Show treasury rebalance info
npx ts-node script/commander.ts trV2 info

# Register addresses
npx ts-node script/commander.ts trV2 register <type> <address> --amount <amount>
npx ts-node script/commander.ts trV2 remove <type> <address>

# Finalize operations
npx ts-node script/commander.ts trV2 finalize <type>

# Approve zeroed addresses
npx ts-node script/commander.ts trV2 approve <address>

# Set pending memo
npx ts-node script/commander.ts trV2 setPendingMemo <memo>

# Update rebalance block number
npx ts-node script/commander.ts trV2 updateRebalanceBN <newBN>

# Reset treasury rebalance
npx ts-node script/commander.ts trV2 reset

# Transfer ownership
npx ts-node script/commander.ts trV2 transfer-ownership <address>
```

#### Governance Parameters (`govparam`)

Manage governance parameters.

```bash
# Show owner
npx ts-node script/commander.ts govparam owner

# Transfer ownership
npx ts-node script/commander.ts govparam transfer-ownership <address>

# Get parameter names
npx ts-node script/commander.ts govparam param-get-names

# Get parameter at block
npx ts-node script/commander.ts govparam param-get <name> <blockNumber>

# Get all parameters at block
npx ts-node script/commander.ts govparam param-get-all <blockNumber>

# Get parameter checkpoint
npx ts-node script/commander.ts govparam param-get-ckpt <name>

# Get all checkpoints
npx ts-node script/commander.ts govparam param-get-ckpts-all

# Set parameter
npx ts-node script/commander.ts govparam param-set <name> <exists> <value> [block]
```

#### Gasless Transactions (`ga`)

Manage gasless swap functionality.

```bash
# Show gasless contracts info
npx ts-node script/commander.ts ga info

# Add token to gasless router
npx ts-node script/commander.ts ga add-token <tokenAddress> <factoryAddress> <routerAddress>

# Remove token from gasless router
npx ts-node script/commander.ts ga remove-token <tokenAddress>

# Update commission rate
npx ts-node script/commander.ts ga update-commission <rate>

# Claim commission
npx ts-node script/commander.ts ga claim-commission

# Transfer ownership
npx ts-node script/commander.ts ga transfer-ownership <address>
```

#### Kaiabridge

Utilities for Kaiabridge-related workflows.

```bash
# Derive addresses from a private key (0x-prefixed)
npx ts-node script/commander.ts calc 0x<privateKey>

# Derive addresses from a mnemonic (default path m/44'/438'/0'/0/0)
npx ts-node script/commander.ts calc "word1 word2 ... word12"

# Derive addresses from a mnemonic with a custom derivation path
npx ts-node script/commander.ts calc "word1 word2 ... word12" "m/44'/438'/0'/0/1"

# Add HolderVerifier record (cony balance in 1e-6 FNSA)
npx ts-node script/commander.ts addRecord <fnsaAddr> <conyBalance> [--dry-run]

# Batch add HolderVerifier records from CSV (dry-run by default)
npx ts-node script/commander.ts addRecords <csvPath>
# Execute on-chain batch add (requires PRIVATE_KEY)
npx ts-node script/commander.ts addRecords <csvPath> --execute

# Verify on-chain HolderVerifier records against a CSV snapshot
npx ts-node script/commander.ts verifyRecords <csvPath>

# Show HolderVerifier contract summary
npx ts-node script/commander.ts info

# Inspect a single HolderVerifier record
npx ts-node script/commander.ts getRecord <fnsaAddr>

# List HolderVerifier records from index with count
npx ts-node script/commander.ts getRecords <startIdx> <maxCount>
```
