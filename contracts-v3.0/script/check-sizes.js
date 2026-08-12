#!/usr/bin/env node
/**
 * Fails if any deployed contract exceeds the EIP-170 runtime code-size limit (24576 B).
 *
 * `forge test` does not enforce EIP-170 (test harnesses deploy via `new`), so a green
 * test run can still hide a non-deployable contract. This gate closes that gap.
 *
 * Scope: only on-chain contracts are checked. `forge build --sizes` already omits
 * `is Test` suites; the remaining test-only helpers (*Harness, Mock*) are exempt here
 * since they are never deployed. `forge` itself exits non-zero (and prints its own
 * "some contracts exceed..." error) when ANY contract — including those exempt
 * harnesses — is over the limit, so we read its JSON regardless of exit code, suppress
 * that noise on success, and apply our own deployed-only filter.
 */
"use strict";

const { spawnSync } = require("node:child_process");

const LIMIT = 24576; // EIP-170 runtime code-size limit, in bytes
const isExempt = (name) => name.endsWith("Harness") || name.startsWith("Mock");

const res = spawnSync("forge", ["build", "--sizes", "--json"], {
  encoding: "utf8",
  maxBuffer: 64 * 1024 * 1024,
});
if (res.error) throw res.error;

let sizes;
try {
  sizes = JSON.parse(res.stdout);
} catch {
  // No parseable JSON means the build itself failed — surface forge's output to debug.
  process.stderr.write(res.stderr || "");
  console.error("check-sizes: `forge build --sizes --json` did not produce parseable output");
  process.exit(1);
}

const deployed = Object.entries(sizes)
  .filter(([name, m]) => !isExempt(name) && m.runtime_size > 0)
  .map(([name, m]) => ({ name, size: m.runtime_size }))
  .sort((a, b) => b.size - a.size);

for (const { name, size } of deployed) {
  const tag = size > LIMIT ? "OVER" : " ok ";
  console.log(`  [${tag}] ${name.padEnd(28)} ${String(size).padStart(6)} B  (margin ${LIMIT - size})`);
}

const exemptOver = Object.entries(sizes)
  .filter(([name, m]) => isExempt(name) && m.runtime_size > LIMIT)
  .map(([name, m]) => `${name} (${m.runtime_size} B)`);
if (exemptOver.length > 0) {
  console.log(`\n  exempt (test-only, never deployed): ${exemptOver.join(", ")}`);
}

const over = deployed.filter((r) => r.size > LIMIT);
if (over.length > 0) {
  for (const { name, size } of over) {
    console.error(`::error::${name} runtime code ${size} B exceeds EIP-170 limit ${LIMIT} B by ${size - LIMIT} B`);
  }
  process.exit(1);
}

console.log(`\n✓ All ${deployed.length} deployed contracts within EIP-170 (${LIMIT} B).`);
