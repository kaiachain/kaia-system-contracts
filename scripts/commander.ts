import { Command } from "commander";
import { abGCInfo, abInfo, abStatus } from "./commander/abook";
import { cnsShowTracker, cnsV3PDEncode } from "./commander/cns";
import { regInfo, regRegister } from "./commander/registry";
import { clRegInfo, clRegAddPair, clRegRemovePair } from "./commander/clregistry";
import { sbrInfo, sbrVerify, sbrRegister, sbrUnregister } from "./commander/sbr";
import {
  trInfo,
  trRegister,
  trRemove,
  trApprove,
  trFinalize,
  trSetPendingMemo,
  trReset,
  trUpdateRebalanceBN,
  trTransferOwnership,
} from "./commander/tr";
import {
  getOwner,
  gpTransferOwnership,
  getAllParamNames,
  getParamAt,
  getAllParamsAt,
  getCheckpoint,
  getAllCheckpoints,
  setParam,
} from "./commander/govparam";
import {
  gaShowInfo,
  gaAddToken,
  gaRemoveToken,
  gaUpdateCommissionRate,
  gaClaimCommission,
  gaTransferOwnership,
} from "./commander/gasless";
import {
  calcFromMnemonic,
  calcFromPrivateKey,
  DEFAULT_MNEMONIC_PATH,
  addRecord,
  addRecordsFromCsv,
  holderVerifierInfo,
  holderVerifierGetRecord,
  holderVerifierGetRecords,
  verifyRecordsFromCsv,
  addOperator,
} from "./commander/kaiabridge";
import { prepareConstructParams, getDeprecatedInfo, validateVMCDeployment } from "./commander/vmc";

async function main() {
  const program = new Command();

  const abook = program.command("abook").description("AddressBook commands");
  abook
    .command("gc-info")
    .description("Show the GC info (provide one of the options)")
    .option("--idx [index]", "GC index", "0")
    .option("--node [nodeAddr]", "GC nodeId address", "")
    .option("--cns [cnsAddr]", "GC cnStaking address", "")
    .option("--reward [rewardAddr]", "GC reward address", "")
    .option("--gcid [gcId]", "GC ID", "")
    .action(abGCInfo);
  abook
    .command("info")
    .description("Show the GCs registered in AddressBook")
    .option("--csv", "Print in csv format", false)
    .action(abInfo);
  abook.command("status").description("Show the status of AddressBook").action(abStatus);

  const cns = program.command("cns").description("CnStakingV2, V3 commands");
  cns
    .command("show-tracker")
    .description("Show the staking tracker of all CnStakingV2 or later")
    .action(cnsShowTracker);
  cns
    .command("encode")
    .description("Encode pdParam")
    .argument("<owner>", "Owner address")
    .argument("<commissionTo>", "CommissionTo address")
    .argument("<commissionRate>", "Commission rate")
    .argument("<gcName>", "GC name")
    .action(cnsV3PDEncode);

  const clreg = program.command("clreg").description("CLRegistry commands");
  clreg.command("info").description("Show CLRegistsry info").action(clRegInfo);
  clreg
    .command("add")
    .description("Add CL pair")
    .argument("nodeid", "Node ID")
    .argument("gcid", "GC ID")
    .argument("clpool", "CL Pool contract address")
    .argument("clstaking", "CL Staking Reward contract address")
    .action(clRegAddPair);
  clreg.command("remove").description("Remove CL pair").argument("gcid", "GC ID").action(clRegRemovePair);

  // cns
  //   .command("info")
  //   .description("CnStaking info. Provide either cns address of index from AddressBook")
  //   .option("--cns <cnsAddr>", "")
  //   .option("--idx <idx>", "0")
  //   .action(cnsInfo);
  const reg = program.command("reg").description("Registry commands");
  reg.command("info").description("Show Registry info").action(regInfo);
  reg
    .command("register")
    .description("Register a record")
    .argument("name", "Contract name")
    .argument("addr", "Contract address")
    .argument("activation", "Activation block")
    .action(regRegister);

  const sbr = program.command("sbr").description("SimpleBlsRegistry commands");
  sbr.command("info").description("Show SimpleBlsRegistry info").action(sbrInfo);
  sbr
    .command("verify")
    .description("Verify a BLS key; Either enter a file path or function arguments")
    .argument("[nodeId]", "CN node ID")
    .argument("[pubkey]", "BLS public key (48B). e.g., 0x1234...")
    .argument("[pop]", "Activation block (96B), 0x1234...")
    .option("--file <path>", "Path of bls-publicinfo*.json file")
    .action(sbrVerify);
  sbr
    .command("register")
    .description("Register a BLS key; Either enter a file path or function arguments")
    .argument("[nodeId]", "CN node ID")
    .argument("[pubkey]", "BLS public key (48B). e.g., 0x1234...")
    .argument("[pop]", "Activation block (96B), 0x1234...")
    .option("--file <path>", "Path of bls-publicinfo*.json file")
    .action(sbrRegister);
  sbr.command("unregister").description("Unregister a BLS key").argument("nodeId", "CN node ID").action(sbrUnregister);

  const trV2 = program.command("trV2").description("TreasuryRebalanceV2 commands");
  trV2.command("info").description("Show TreasuryRebalanceV2 info").action(trInfo);
  trV2
    .command("register")
    .description("Register zeroed/allocated address")
    .argument("type", "zeroed or allocated")
    .argument("address", "address")
    .option("--amount [amount]", "amount of allocated")
    .action(trRegister);

  trV2
    .command("remove")
    .description("Register zeroed/allocated address")
    .argument("type", "zeroed or allocated")
    .argument("address", "address")
    .action(trRemove);
  trV2.command("finalize").argument("finalize", "registration or approval or contract").action(trFinalize);
  trV2.command("approve").argument("address", "zeroed address").action(trApprove);
  trV2.command("setPendingMemo").argument("memo", "temporary string of memo").action(trSetPendingMemo);
  trV2.command("updateRebalanceBN").argument("newBN", "new rebalance blocknumber").action(trUpdateRebalanceBN);
  trV2.command("reset").action(trReset);
  trV2.command("transfer-ownership").argument("address", "new owner address").action(trTransferOwnership);

  const govparam = program.command("govparam").description("GovParam commands");
  govparam.command("owner").description("Show the owner of GovParam").action(getOwner);
  govparam.command("transfer-ownership").argument("address", "new owner address").action(gpTransferOwnership);
  govparam.command("param-get-names").description("Show all parameter names").action(getAllParamNames);
  govparam
    .command("param-get")
    .description("Show the parameter at a given block number")
    .argument("name")
    .argument("blockNumber", "block number")
    .action(getParamAt);
  govparam
    .command("param-get-all")
    .description("Show all parameters at a given block number")
    .argument("blockNumber", "block number")
    .action(getAllParamsAt);
  govparam
    .command("param-get-ckpt")
    .description("Show the checkpoint of a parameter")
    .argument("name")
    .action(getCheckpoint);
  govparam.command("param-get-ckpts-all").description("Show all checkpoints").action(getAllCheckpoints);
  govparam
    .command("param-set")
    .description("Set a parameter")
    .argument("name")
    .argument("exists", "true or false")
    .argument("value", "value")
    .argument("[block]", "block number or +10")
    .action(setParam);

  // Add Gasless Transaction commands
  const ga = program.command("ga").description("Gasless Transaction commands");

  ga.command("info").description("Show all Gasless contracts info").action(gaShowInfo);
  ga.command("add-token")
    .description("Add a token to the GaslessSwapRouter")
    .argument("<tokenAddress>", "Address of the token to add")
    .argument("<factoryAddress>", "Address of the DEX factory")
    .argument("<routerAddress>", "Address of the DEX router")
    .action((tokenAddress, factoryAddress, routerAddress) => gaAddToken(tokenAddress, factoryAddress, routerAddress));
  ga.command("remove-token")
    .description("Remove a token from the GaslessSwapRouter")
    .argument("<tokenAddress>", "Address of the token to remove")
    .action(gaRemoveToken);
  ga.command("update-commission")
    .description("Update commission rate (range: 0-10000)")
    .argument("<rate>", "New commission rate (basis points: 100 = 1%)")
    .action(gaUpdateCommissionRate);
  ga.command("claim-commission")
    .description("Claim accumulated commission from GaslessSwapRouter")
    .action(gaClaimCommission);
  ga.command("transfer-ownership").argument("address", "new owner address").action(gaTransferOwnership);

  // Add KaiaBridge Transaction commands
  const kaiabridge = program.command("kaiabridge").description("Kaiabridge commands");
  kaiabridge
    .command("calc")
    .description("Derive FNSA/valoper addresses from a credential")
    .argument("<credential>", "Private key (0x...) or mnemonic phrase wrapped in quotes")
    .argument("[path]", `Derivation path for mnemonic. Defaults to ${DEFAULT_MNEMONIC_PATH}`)
    .action(async (credential: string, path: string | undefined) => {
      const trimmed = credential.trim();
      if (/^(0x)?[0-9a-fA-F]{64}$/.test(trimmed.replace(/^0x/, ""))) {
        await calcFromPrivateKey(trimmed);
        return;
      }
      if (trimmed.split(/\s+/).length >= 12) {
        await calcFromMnemonic(trimmed, path);
        return;
      }

      throw new Error("Failed to detect credential type. Provide a 32-byte private key or a mnemonic (12+ words).");
    });
  kaiabridge
    .command("addRecord")
    .description("Add a HolderVerifier record (FNSA address + cony balance)")
    .argument("<fnsaAddr>", "FNSA or valoper address")
    .argument("<conyBalance>", "cony balance (1e-6 FNSA) e.g. 500000")
    .option("--dry-run", "Only show preview without sending transaction", false)
    .action(async (fnsaAddr: string, conyBalance: string, options: { dryRun?: boolean }) => {
      await addRecord(fnsaAddr, conyBalance, { dryRun: options.dryRun });
    });
  kaiabridge
    .command("addRecords")
    .description("Batch add HolderVerifier records from CSV")
    .argument("<csvPath>", "Path to the CSV file")
    .option("--execute", "Send transactions (omit for dry-run)", false)
    .action(async (csvPath: string, options: { execute?: boolean }) => {
      await addRecordsFromCsv(csvPath, options);
    });
  kaiabridge.command("info").description("Show HolderVerifier contract stats").action(holderVerifierInfo);
  kaiabridge
    .command("getRecord")
    .description("Show a single HolderVerifier record")
    .argument("<fnsaAddr>", "FNSA or valoper address")
    .action(async (fnsaAddr: string) => {
      await holderVerifierGetRecord(fnsaAddr);
    });
  kaiabridge
    .command("getRecords")
    .description("Show multiple HolderVerifier records starting from index")
    .argument("<startIdx>", "Start index (0-based)")
    .argument("<maxCount>", "Maximum number of records to fetch")
    .action(async (startIdx: string, maxCount: string) => {
      await holderVerifierGetRecords(startIdx, maxCount);
    });
  kaiabridge
    .command("verifyRecords")
    .description("Verify HolderVerifier records against a CSV file")
    .argument("<csvPath>", "Path to the CSV file")
    .action(async (csvPath: string) => {
      await verifyRecordsFromCsv(csvPath);
    });
  kaiabridge
    .command("addOperator")
    .description("Add new operator")
    .argument("<operator>", "Operator address")
    .argument("<guardian>", "Guardian address")
    .argument("<newOperator>", "New operator address")
    .option("--network <network>", "Network name", "hardhat")
    .action(async (operator: string, guardian: string, newOperator: string, options: { network?: string }) => {
      await addOperator(operator, guardian, newOperator, options);
    });

  const vmc = program.command("vmc").description("ValidatorManager commands");
  vmc.command("prepare-construct-params").description("Prepare construct params").action(prepareConstructParams);
  vmc.command("get-deprecated-info").description("Get deprecated info").action(getDeprecatedInfo);
  vmc.command("validate-deployment").description("Validate VMC deployment").action(validateVMCDeployment);

  program.parse();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
