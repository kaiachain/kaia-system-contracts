import { ethers, formatEther, formatUnits } from "ethers";
import { bech32 } from "bech32";
import type { HDNodeWallet, Wallet } from "ethers";
import { promises as fs } from "fs";
import path from "path";
import { getHolderVerifier, getGuardian, getNetworkName, getOperator, signer } from "../utils";
const CONV_RATE = 148079656000000n;

export const DEFAULT_MNEMONIC_PATH = "m/44'/438'/0'/0/0";

type WalletSource = "mnemonic" | "private-key";

interface DerivedAddresses {
  source: WalletSource;
  networkName: string;
  ethereumAddress: string;
  fnsaAddress: string;
  valoperAddress: string;
  fnsaAddressHash: string;
  valoperAddressHash: string;
  compressedPublicKey: string;
  uncompressedPublicKey: string;
  derivationPath?: string;
}

interface CsvBalanceRecord {
  account: string;
  total: bigint;
}

interface CsvParseResult {
  records: CsvBalanceRecord[];
  duplicateCount: number;
  totalCony: bigint;
  totalRowCount: number;
  skippedCount: number;
}

interface AddRecordsCliOptions {
  execute?: boolean;
}

interface BatchSummary {
  batchNumber: number;
  endIndex: number;
  records: CsvBalanceRecord[];
  totalCony: bigint;
}

interface FullParseResult extends CsvParseResult {
  batches: BatchSummary[];
}

interface ProcessBatchContext {
  totalBatches: number;
  totalRecords: number;
  processedBatches: number;
  processedRecords: number;
}

function chunkRecords(
  records: CsvBalanceRecord[],
  batchSize: number,
  startIndex: number,
  totalCount: number,
): BatchSummary[] {
  const result: BatchSummary[] = [];
  if (records.length === 0) {
    return result;
  }

  const size = Math.max(1, batchSize);

  for (let offset = 0; offset < records.length; offset += size) {
    const batchRecords = records.slice(offset, offset + size);
    const totalCony = batchRecords.reduce((acc, record) => acc + record.total, 0n);

    result.push({
      batchNumber: result.length + 1,
      endIndex: Math.min(startIndex + offset + batchRecords.length, totalCount),
      records: batchRecords,
      totalCony,
    });
  }

  return result;
}

const CSV_EXPECTED_HEADER_EXAMPLES = '"account,total"';

const CONY_DECIMALS = 6n;
const CSV_DECIMAL_SCALE = CONY_DECIMALS;
const NUMBER_REGEX = /^[+-]?[0-9]+$/;
const CSV_COMMENT_PREFIXES = ["#", "//"];
const DEFAULT_BATCH_SIZE = 100;

function sanitizeCell(cell: string | undefined): string {
  if (cell === undefined) {
    return "";
  }
  let sanitized = cell.trim();
  if (sanitized.startsWith("\ufeff")) {
    sanitized = sanitized.slice(1);
  }
  if (sanitized.length >= 2 && sanitized.startsWith('"') && sanitized.endsWith('"')) {
    sanitized = sanitized.slice(1, -1);
  }
  return sanitized.trim();
}

function splitCsvRow(row: string): string[] {
  const result: string[] = [];
  let current = "";
  let inQuotes = false;

  for (let i = 0; i < row.length; i++) {
    const char = row[i];

    if (char === '"') {
      if (inQuotes && i + 1 < row.length && row[i + 1] === '"') {
        current += '"';
        i++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char === "," && !inQuotes) {
      result.push(current);
      current = "";
      continue;
    }

    current += char;
  }

  result.push(current);
  return result;
}

function parseNumericCell(raw: string | undefined, line: number): bigint {
  const sanitized = sanitizeCell(raw).replace(/[, _]/g, "");

  if (sanitized.length === 0) {
    return 0n;
  }

  if (!NUMBER_REGEX.test(sanitized)) {
    throw new Error(`Invalid numeric value '${raw ?? ""}' at line ${line}`);
  }

  return BigInt(sanitized);
}

function formatWithSeparators(value: bigint): string {
  const sign = value < 0n ? "-" : "";
  const digits = (value < 0n ? -value : value).toString();
  return sign + digits.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function formatConyUnits(value: bigint): string {
  return formatUnits(value, Number(CSV_DECIMAL_SCALE));
}

async function parseCsvFile(csvPath: string): Promise<CsvParseResult> {
  const resolvedPath = path.isAbsolute(csvPath) ? csvPath : path.resolve(process.cwd(), csvPath);
  const content = await fs.readFile(resolvedPath, "utf8");
  const lines = content.split(/\r?\n/);

  const records: CsvBalanceRecord[] = [];
  const seenAccounts = new Set<string>();
  let duplicateCount = 0;
  let skippedCount = 0;
  let totalCony = 0n;

  const headerIndex = lines.findIndex((line) => {
    if (line === undefined) {
      return false;
    }
    const trimmed = line.trim();
    const lowered = trimmed.toLowerCase();
    if (trimmed.length === 0 || lowered.startsWith("subtotal")) {
      return false;
    }

    const normalized = splitCsvRow(trimmed)
      .map((cell) => sanitizeCell(cell).toLowerCase().replace(/\s+/g, ""))
      .join(",");
    if (normalized !== "account,total") {
      throw new Error(
        `CSV header does not match expected columns. Expected ${CSV_EXPECTED_HEADER_EXAMPLES}, found: ${trimmed}`,
      );
    }

    return true;
  });

  if (headerIndex === -1) {
    throw new Error(`CSV header not found. Expected columns similar to ${CSV_EXPECTED_HEADER_EXAMPLES}.`);
  }

  for (let idx = headerIndex + 1; idx < lines.length; idx++) {
    const rawLine = lines[idx];
    if (rawLine === undefined) {
      continue;
    }

    const trimmed = rawLine.trim();
    const lowered = trimmed.toLowerCase();
    if (trimmed.length === 0 || CSV_COMMENT_PREFIXES.some((prefix) => lowered.startsWith(prefix))) {
      continue;
    }

    const cells = splitCsvRow(rawLine);
    const account = sanitizeCell(cells[0]);
    if (account.length === 0) {
      continue;
    }

    const total = parseNumericCell(cells[1], idx + 1);
    if (total === 0n) {
      skippedCount += 1;
      continue;
    }

    totalCony += total;
    if (!seenAccounts.add(account)) {
      duplicateCount += 1;
    }

    records.push({ account, total });
  }

  return {
    records,
    duplicateCount,
    totalCony,
    totalRowCount: records.length + skippedCount,
    skippedCount,
  };
}

async function parseCsvWithBatches(csvPath: string): Promise<FullParseResult> {
  const result = await parseCsvFile(csvPath);

  const batches = chunkRecords(result.records, DEFAULT_BATCH_SIZE, 0, result.totalRowCount);

  return {
    ...result,
    batches,
  };
}

function aggregateCsvAccountTotals(records: CsvBalanceRecord[]): Map<string, bigint> {
  const aggregated = new Map<string, bigint>();

  for (const record of records) {
    const current = aggregated.get(record.account) ?? 0n;
    aggregated.set(record.account, current + record.total);
  }

  return aggregated;
}

async function fetchHolderVerifierRecords(pageSize: number): Promise<{
  recordCount: number;
  balances: Map<string, bigint>;
}> {
  const holderVerifier = getHolderVerifier();
  const recordCountRaw = await holderVerifier.getRecordCount();
  const recordCount = Number(recordCountRaw);

  if (!Number.isFinite(recordCount)) {
    throw new Error("HolderVerifier record count exceeds JavaScript number range");
  }

  const balances = new Map<string, bigint>();

  if (recordCount === 0) {
    return { recordCount, balances };
  }

  for (let start = 0; start < recordCount; start += pageSize) {
    const fetchSize = Math.min(pageSize, recordCount - start);
    const [addresses, balancesRaw] = await holderVerifier.getRecords(start, fetchSize);

    for (let idx = 0; idx < addresses.length; idx++) {
      balances.set(addresses[idx], BigInt(balancesRaw[idx]));
    }
  }

  return { recordCount, balances };
}

function describeConyAmount(value: bigint): string {
  return `${formatWithSeparators(value)} (${formatConyUnits(value)} FNSA)`;
}

export async function verifyRecordsFromCsv(csvPath: string): Promise<void> {
  const pageSize = 200;

  console.log("Parsing CSV file ...");
  const parsed = await parseCsvFile(csvPath);
  const aggregated = aggregateCsvAccountTotals(parsed.records);

  console.log("Fetching HolderVerifier records ...");
  const { recordCount, balances } = await fetchHolderVerifierRecords(pageSize);

  const missing: string[] = [];
  let missingTotal = 0n;
  const mismatched: {
    account: string;
    csvTotal: bigint;
    onChainTotal: bigint;
    diff: bigint;
  }[] = [];
  let mismatchedDiffTotal = 0n;
  let matchedTotal = 0n;

  for (const [account, csvTotal] of aggregated) {
    const onChain = balances.get(account);
    if (onChain === undefined) {
      missing.push(account);
      missingTotal += csvTotal;
      continue;
    }

    const diff = csvTotal - onChain;
    if (diff !== 0n) {
      mismatched.push({ account, csvTotal, onChainTotal: onChain, diff });
      mismatchedDiffTotal += diff;
      continue;
    }

    matchedTotal += csvTotal;
  }

  const matchedCount = aggregated.size - missing.length - mismatched.length;

  console.log("\nCSV Summary:");
  console.log(`- Records parsed     : ${parsed.records.length}`);
  console.log(`- Total CSV records  : ${parsed.totalRowCount}`);
  console.log(`- Skipped (total=0)  : ${parsed.skippedCount}`);
  console.log(`- Unique accounts    : ${aggregated.size}`);
  console.log(`- CSV total (cony)   : ${describeConyAmount(parsed.totalCony)}`);

  console.log("\nVerification Result:");
  console.log(`- Matched accounts    : ${matchedCount}`);
  console.log(`- Missing accounts    : ${missing.length}`);
  console.log(`  * Total (cony)      : ${describeConyAmount(missingTotal)}`);
  console.log(`- Balance mismatches  : ${mismatched.length}`);
  if (mismatched.length > 0) {
    console.log(`  * Total diff (CSV-OnChain): ${describeConyAmount(mismatchedDiffTotal)}`);
  }
  console.log(`- Matched total (cony): ${describeConyAmount(matchedTotal)}`);
  console.log(`- CSV accounts missing on chain: ${missing.length}`);

  if (mismatched.length > 0) {
    console.log(`- Balance mismatches (up to 20 shown): ${mismatched.length}`);
    const display = mismatched.slice(0, 20);
    for (const mismatch of display) {
      console.log(`  - ${mismatch.account}`);
      console.log(`      CSV total   : ${describeConyAmount(mismatch.csvTotal)}`);
      console.log(`      On-chain    : ${describeConyAmount(mismatch.onChainTotal)}`);
      console.log(`      Difference  : ${describeConyAmount(mismatch.diff)}`);
    }
    if (display.length < mismatched.length) {
      console.log(`  ... and ${mismatched.length - display.length} more mismatches`);
    }
  }

  if (missing.length === 0 && mismatched.length === 0) {
    console.log("\nAll CSV accounts are present on chain with matching balances.");
  } else {
    console.log("\nDiscrepancies detected. Review the list above.");
  }
}

export async function addRecordsFromCsv(csvPath: string, options: AddRecordsCliOptions): Promise<void> {
  const execute = options.execute === true;
  const dryRun = !execute;

  console.log("Parsing CSV ...");
  const parsed = await parseCsvWithBatches(csvPath);

  const totalCony = parsed.totalCony;

  console.log("\nCSV Summary:");
  console.log(`- Records parsed    : ${parsed.records.length}`);
  console.log(`- Total CSV records : ${parsed.totalRowCount}`);
  console.log(`- Duplicate accounts: ${parsed.duplicateCount}`);
  console.log(`- Skipped (total=0) : ${parsed.skippedCount}`);
  console.log(`- Batch size        : ${DEFAULT_BATCH_SIZE}`);
  console.log(`- Batches           : ${parsed.batches.length}`);

  console.log("\nSelected Amounts:");
  console.log(`- Total (cony)      : ${formatWithSeparators(totalCony)} (${formatConyUnits(totalCony)} FNSA)`);

  if (parsed.records.length === 0) {
    console.log("\nNo CSV records matched the provided filters.");
    return;
  }

  if (dryRun) {
    console.log("\n--- DRY RUN ---");
    console.log(`Processed records   : ${parsed.records.length}`);
    console.log(`Skipped (total=0)   : ${parsed.skippedCount}`);
    return;
  }

  console.log("\nExecuting on-chain addRecords ...");
  const holderVerifier = getHolderVerifier();
  const contractAddress = await holderVerifier.getAddress();
  console.log(`Signer              : ${signer.address}`);
  console.log(`HolderVerifier      : ${contractAddress}`);

  const context: ProcessBatchContext = {
    totalBatches: parsed.batches.length,
    totalRecords: parsed.records.length,
    processedBatches: 0,
    processedRecords: 0,
  };

  for (const batch of parsed.batches) {
    context.processedBatches += 1;
    context.processedRecords += batch.records.length;

    const fnsaAddrs = batch.records.map((record) => record.account);
    const balances = batch.records.map((record) => record.total);

    console.log(`\nProcessing batch #${batch.batchNumber}/${context.totalBatches}`);
    console.log(`  Records           : ${batch.records.length}`);
    console.log(
      `  Total (cony)      : ${formatWithSeparators(batch.totalCony)} (${formatConyUnits(batch.totalCony)} FNSA)`,
    );

    const tx = await holderVerifier.addRecords(fnsaAddrs, balances);
    console.log(`  tx hash           : ${tx.hash}`);
    const receipt = await tx.wait();
    console.log(`  status            : ${receipt?.status === 1 ? "SUCCESS" : receipt?.status}`);
  }

  console.log("\n--- Completed ---");
  console.log(`Processed records   : ${context.processedRecords}`);
  console.log(`Skipped (total=0)   : ${parsed.skippedCount}`);
}

function computeKaiaAmount(conyBalance: bigint, convRate: bigint = CONV_RATE): bigint {
  return conyBalance * convRate;
}

function ensureHexPrivateKey(rawKey: string): string {
  const trimmed = rawKey.trim();
  const prefixed = trimmed.startsWith("0x") ? trimmed : `0x${trimmed}`;
  const hexBody = prefixed.slice(2);
  if (hexBody.length !== 64 || !/^[0-9a-fA-F]+$/.test(hexBody)) {
    throw new Error("Invalid private key. Expected a 32-byte hex string.");
  }
  return prefixed;
}

function getWalletFromMnemonic(mnemonicPhrase: string, path: string): HDNodeWallet {
  try {
    const mnemonic = ethers.Mnemonic.fromPhrase(mnemonicPhrase.trim());
    return ethers.HDNodeWallet.fromMnemonic(mnemonic, path);
  } catch (error) {
    throw new Error(
      `Failed to parse mnemonic or derivation path: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

async function deriveAddresses(
  wallet: Wallet | HDNodeWallet,
  source: WalletSource,
  path?: string,
): Promise<DerivedAddresses> {
  const compressed = wallet.signingKey.compressedPublicKey;
  const uncompressed = wallet.signingKey.publicKey;
  const compressedBytes = ethers.getBytes(compressed);

  const sha256 = ethers.sha256(compressedBytes);
  const ripemd160 = ethers.ripemd160(ethers.getBytes(sha256));
  const addressHash = ethers.getBytes(ripemd160);

  const fnsaAddr = bech32.encode("link", bech32.toWords(addressHash));
  const valoperAddr = bech32.encode("linkvaloper", bech32.toWords(addressHash));

  const ethereumAddr = await wallet.getAddress();
  const fnsaAddrHash = ethers.keccak256(ethers.toUtf8Bytes(fnsaAddr));
  const valoperAddrHash = ethers.keccak256(ethers.toUtf8Bytes(valoperAddr));

  return {
    source,
    networkName: await getNetworkName(),
    ethereumAddress: ethereumAddr,
    fnsaAddress: fnsaAddr,
    valoperAddress: valoperAddr,
    fnsaAddressHash: fnsaAddrHash,
    valoperAddressHash: valoperAddrHash,
    compressedPublicKey: compressed,
    uncompressedPublicKey: uncompressed,
    derivationPath: path,
  };
}

function logDerivedAddressSummary(info: DerivedAddresses): void {
  console.log("Network             :", info.networkName);
  console.log("Source              :", info.source === "mnemonic" ? "mnemonic" : "private key");
  if (info.source === "mnemonic" && info.derivationPath) {
    console.log("Derivation Path     :", info.derivationPath);
  }
  console.log("Ethereum Address    :", info.ethereumAddress);
  console.log("Compressed PubKey   :", info.compressedPublicKey);
  console.log("Uncompressed PubKey :", info.uncompressedPublicKey);
  console.log("FNSA Address        :", info.fnsaAddress);
  console.log("  keccak256(addr)   :", info.fnsaAddressHash);
  console.log("Valoper Address     :", info.valoperAddress);
  console.log("  keccak256(addr)   :", info.valoperAddressHash);
}

export async function calcFromPrivateKey(rawKey: string): Promise<void> {
  const privateKey = ensureHexPrivateKey(rawKey);
  const wallet = new ethers.Wallet(privateKey);
  const info = await deriveAddresses(wallet, "private-key");
  logDerivedAddressSummary(info);
}

export async function calcFromMnemonic(mnemonicPhrase: string, path?: string): Promise<void> {
  const effectivePath = path?.trim() && path.trim().length > 0 ? path.trim() : DEFAULT_MNEMONIC_PATH;
  const wallet = getWalletFromMnemonic(mnemonicPhrase, effectivePath);
  const info = await deriveAddresses(wallet, "mnemonic", effectivePath);
  logDerivedAddressSummary(info);
}

function parseConyBalanceArg(raw: string): bigint {
  const normalized = raw.replace(/_/g, "").trim();
  if (normalized.length === 0) {
    throw new Error("conyBalance must be a non-empty numeric string.");
  }

  try {
    const value = BigInt(normalized);
    if (value <= 0n) {
      throw new Error("conyBalance must be greater than zero.");
    }
    return value;
  } catch (error) {
    throw new Error(`Failed to parse conyBalance '${raw}': ${error instanceof Error ? error.message : String(error)}`);
  }
}

export async function addRecord(fnsaAddr: string, conyBalanceRaw: string, options: { dryRun?: boolean }) {
  if (!fnsaAddr || fnsaAddr.trim().length === 0) {
    throw new Error("FNSA address must be provided.");
  }

  const conyBalance = parseConyBalanceArg(conyBalanceRaw);
  const dryRun = options.dryRun ?? process.env.DRY_RUN === "true";
  const privateKey = ensureHexPrivateKey(process.env.PRIVATE_KEY ?? "");

  const holderVerifier = getHolderVerifier();
  const contractAddress = await holderVerifier.getAddress();
  const kaiaAmount = computeKaiaAmount(conyBalance, CONV_RATE);

  console.log("HolderVerifier :: addRecord");
  console.log("Network            :", await getNetworkName());
  console.log("Contract           :", contractAddress);
  console.log("Signer             :", await signer.getAddress());
  console.log("FNSA Address       :", fnsaAddr);
  console.log("conyBalance (1e-6) :", conyBalance.toString());
  console.log("KAIA amount (kei)  :", kaiaAmount.toString());
  console.log("Dry run            :", dryRun ? "YES" : "NO");

  if (dryRun) {
    return;
  }

  const tx = await holderVerifier.addRecord(fnsaAddr, conyBalance);
  console.log("tx hash            :", tx.hash);
  const receipt = await tx.wait();
  console.log("status             :", receipt?.status === 1 ? "SUCCESS" : receipt?.status);

  const record = await holderVerifier.getRecord(fnsaAddr);
  console.log("On-chain balance   :", record[0].toString());
  console.log("Is provisioned     :", record[1]);
}

function formatKaiaAmount(kaiaAmount: bigint): string {
  try {
    return formatEther(kaiaAmount);
  } catch (error) {
    return `${kaiaAmount.toString()} (formatting error: ${error instanceof Error ? error.message : String(error)})`;
  }
}

function printRecordSummary(params: { index?: number; fnsaAddr: string; conyBalance: bigint; seq: bigint }) {
  const { index, fnsaAddr, conyBalance, seq } = params;
  const kaiaAmount = computeKaiaAmount(conyBalance);

  const header = index !== undefined ? `Record #${index}` : "Record";
  console.log(`- ${header}:`);
  console.log("  FNSA Address       :", fnsaAddr);
  console.log("  conyBalance (1e-6) :", conyBalance.toString());
  console.log("  KAIA amount (kei)  :", kaiaAmount.toString());
  console.log("  KAIA amount        :", formatKaiaAmount(kaiaAmount));
  console.log("  Provisioned        :", seq == 0n ? "YES" : "NO");
  console.log("  Seq                :", seq.toString());
}

export async function holderVerifierInfo(): Promise<void> {
  const holderVerifier = getHolderVerifier();
  const contractAddress = await holderVerifier.getAddress();

  const [owner, recordCountRaw, allConyRaw, provisionedConyRaw, provisionedAccountsRaw] = await Promise.all([
    holderVerifier.owner(),
    holderVerifier.getRecordCount(),
    holderVerifier.allConyBalances(),
    holderVerifier.provisionedConyBalances(),
    holderVerifier.provisionedAccounts(),
  ]);

  const recordCount = BigInt(recordCountRaw);
  const allCony = BigInt(allConyRaw);
  const provisionedCony = BigInt(provisionedConyRaw);
  const provisionedAccounts = BigInt(provisionedAccountsRaw);
  const pendingCony = allCony - provisionedCony;

  console.log("\nHolderVerifier Configuration:");
  console.log("- Network             :", await getNetworkName());
  console.log("- Contract            :", contractAddress);
  console.log("- Owner               :", owner);
  console.log("- Record Count        :", recordCount.toString());
  console.log("- Total cony          :", describeConyAmount(allCony));
  console.log("- Provisioned cony    :", describeConyAmount(provisionedCony));
  console.log("- Provisioned accounts:", provisionedAccounts.toString());
  console.log("- Pending cony        :", describeConyAmount(pendingCony));
}

export async function holderVerifierGetRecord(fnsaAddr: string): Promise<void> {
  if (!fnsaAddr || fnsaAddr.trim().length === 0) {
    throw new Error("FNSA address must be provided.");
  }

  const holderVerifier = getHolderVerifier();
  const [conyBalanceRaw, seq] = await holderVerifier.getRecord(fnsaAddr);
  const conyBalance = BigInt(conyBalanceRaw);

  console.log("\nHolderVerifier Record:");
  console.log("- Network          :", await getNetworkName());
  printRecordSummary({ fnsaAddr, conyBalance, seq });
}

export async function holderVerifierGetRecords(startIdxRaw: string, maxCountRaw: string): Promise<void> {
  const startIdx = Number.parseInt(startIdxRaw, 10);
  const maxCount = Number.parseInt(maxCountRaw, 10);

  if (Number.isNaN(startIdx) || startIdx < 0) {
    throw new Error(`Invalid startIdx: ${startIdxRaw}`);
  }

  if (Number.isNaN(maxCount) || maxCount <= 0) {
    throw new Error(`Invalid maxCount: ${maxCountRaw}`);
  }

  const holderVerifier = getHolderVerifier();
  const recordCountRaw = await holderVerifier.getRecordCount();
  const recordCount = Number(recordCountRaw);

  console.log("\nHolderVerifier Records:");
  console.log("- Network          :", await getNetworkName());

  if (recordCount === 0) {
    console.log("- No records available.");
    return;
  }

  if (startIdx >= recordCount) {
    console.log(`- No records starting from index ${startIdx}. Current record count: ${recordCount}.`);
    return;
  }

  const [fnsaAddrs, conyBalancesRaw, seqs] = await holderVerifier.getRecords(startIdx, maxCount);

  console.log(`- Range            : [${startIdx}, ${startIdx + fnsaAddrs.length})`);

  if (fnsaAddrs.length === 0) {
    console.log("- No records returned.");
    return;
  }

  for (let i = 0; i < fnsaAddrs.length; i++) {
    const conyBalance = BigInt(conyBalancesRaw[i]);
    printRecordSummary({
      index: startIdx + i,
      fnsaAddr: fnsaAddrs[i],
      conyBalance,
      seq: seqs[i],
    });
  }
}

export async function addOperator(
  operatorAddress: string,
  guardianAddress: string,
  newOperatorAddress: string,
  options: { network?: string },
): Promise<void> {
  console.log("Operator :: addOperator");
  console.log("Network              :", options.network);
  console.log("New Operator Address :", newOperatorAddress);
  console.log("Operator Address     :", operatorAddress);
  console.log("Guardian Address     :", guardianAddress);

  const operator = getOperator(operatorAddress);
  const guardian = getGuardian(guardianAddress);

  const addOperatorData = (await operator.addOperator.populateTransaction(newOperatorAddress)).data;
  const tx = await guardian.submitTransaction(operatorAddress, addOperatorData!, 0);
  console.log("tx hash            :", tx.hash);
  const receipt = await tx.wait();
  console.log("status             :", receipt?.status === 1 ? "SUCCESS" : receipt?.status);
}
