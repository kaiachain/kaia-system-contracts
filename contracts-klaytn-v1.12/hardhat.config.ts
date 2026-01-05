import { HardhatUserConfig, task } from "hardhat/config";
import "hardhat-deploy";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
import "@primitivefi/hardhat-dodoc";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-gas-reporter";
import * as dotenv from "dotenv";
import { formatEther } from "ethers";

export const env = dotenv.config().parsed;

const defaultKey = "0x00000000000000000000000000000000000000000000000000000000cafebabe";

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();
  for (const account of accounts) {
    const balance = await hre.ethers.provider.getBalance(account.address);
    console.log(account.address, formatEther(balance), "KAIA");
  }
});

task("import", "Import a contract deployment")
  .addPositionalParam("name")
  .addPositionalParam("address")
  .setAction(async (taskArgs, hre) => {
    const { name, address } = taskArgs;
    const { deployments } = hre;
    const { save, getExtendedArtifact } = deployments;

    try {
      await deployments.get(name);
      console.log(`reusing ${name} at ${address}`);
    } catch {
      const artifacts = await getExtendedArtifact(name);
      save(name, {
        address: address,
        ...artifacts,
      });
      console.log(`saving ${name} at ${address}`);
    }
  });

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.4.24", // AddressBookMock
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
      {
        version: "0.8.19", // Registry
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
    ],
    overrides: {
      "contracts/SimpleBlsRegistry.sol": {
        version: "0.8.18",
        settings: { optimizer: { enabled: true, runs: 200 } },
      },
    },
  },
  networks: {
    hardhat: {
      accounts: {
        accountsBalance: 1_000_000_000n.toString() + "0".repeat(18),
      },
    },
    baobab: {
      url: env?.["KAIROS_URL"] || "https://archive-en-kairos.node.kaia.io/",
      chainId: 1001,
      // Sample private keys for testing
      accounts: [env?.["PRIVATE_KEY"] || defaultKey],
      live: true,
      saveDeployments: true,
    },
    cypress: {
      url: env?.["MAINNET_URL"] || "https://archive-en.node.kaia.io",
      chainId: 8217,
      accounts: [env?.["PRIVATE_KEY"] || defaultKey, env?.["PRIVATE_KEY2"] || defaultKey],
      live: true,
      saveDeployments: true,
    },
    homi: {
      url: "http://127.0.0.1:8551",
      accounts: [env?.["PRIVATE_KEY"] || defaultKey, env?.["PRIVATE_KEY2"] || defaultKey],
      live: false,
      saveDeployments: true,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      accounts: {
        mnemonic: "test test test test test test test test test test test junk",
        path: "m/44'/60'/0'/0",
        initialIndex: 0,
        count: 30,
        passphrase: "",
      },
      live: false,
      saveDeployments: true,
    },
  },
  namedAccounts: {
    deployer: {
      default: 0, // here this will by default take the first account as deployer
    },
  },
  etherscan: {
    apiKey: {
      cypress: "unnecessary",
      baobab: "unnecessary",
    },
    customChains: [
      {
        network: "cypress",
        chainId: 8217,
        urls: {
          apiURL: "https://mainnet-api.kaiascan.io/hardhat-verify",
          browserURL: "https://kaiascan.io",
        },
      },
      {
        network: "baobab",
        chainId: 1001,
        urls: {
          apiURL: "https://kairos-api.kaiascan.io/hardhat-verify",
          browserURL: "https://kairos.kaiascan.io",
        },
      },
    ],
  },
  gasReporter: {
    currency: "USD",
    gasPrice: 25, // 25 ston
    enabled: true, // env?.["REPORT_GAS"] ? true : false,
    outputFile: "gas-report.txt",
  },
  dodoc: {
    exclude: ["hardhat/", "lib/"],
    runOnCompile: false,
    freshOutput: false,
  },
  paths: {
    deployments: "deployments",
  },
};

export default config;
