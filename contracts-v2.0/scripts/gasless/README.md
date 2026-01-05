# How to use it

## 1. Setup local net

- Use homi to set up your local network.
- ## To run `homi setup`, use the following command:
  ```
  homi setup --cn-num 4 --pn-num 4 --en-num 2 --kairos-test --mnemonic test,junk --patch-address-book --docker-image-id test/kaia:v2.0.0-rc.4 --gen-type docker
  cd homi-output && docker compose up -d
  ```
- The commands need to be run from the project root (git root)

## 2. Set env

```
HARDHAT_NETWORK=homi
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

## 3. Run scripts

1. Deploying all contracts

```
npx hardhat deploy --tags Gasless --reset
```

2. Setup the environment

This scripts can be executed once per homi network.

```
npx hardhat run scripts/gasless/qa/01_setup.ts
npx hardhat run scripts/gasless/qa/02_transfer_token.ts
```

3. Run the test scripts

This scripts can be executed multiple times once the environment is set.

```
npx hardhat run scripts/gasless/qa/03_send_approve_swap_tx.ts
npx hardhat run scripts/gasless/qa/04_send_swap_tx.ts
npx hardhat run scripts/gasless/qa/05_send_multiple_approve_swap_tx.ts
npx hardhat run scripts/gasless/qa/06_success_and_revert.ts
```
