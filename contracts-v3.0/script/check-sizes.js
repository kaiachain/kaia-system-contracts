#!/usr/bin/env node
/**
 * Fails if any deployed contract exceeds the EIP-170 runtime code-size limit (24576 B).
 *
 * `forge test` does not enforce EIP-170 (test harnesses deploy via `new`), so a green
 * test run can still hide a non-deployable contract. This gate closes that gap.
 *
 * Scope: only on-chain contracts under src/ are checked. `forge build --sizes` already
 * omits `is Test` suites; the remaining test-only helpers (*Harness, Mock*) are exempt
 * here since they are never deployed. `forge` itself exits non-zero when ANY contract
 * (including those harnesses) is over the limit, so we parse its JSON from a possibly
 * non-zero exit and apply our own deployed-only filter.
 */
"use strict";

const { execFileSync } = require("node:child_process");

const LIMIT = 24576; // EIP-170 runtime code-size limit, in bytes
const isExempt = (name) => name.endsWith("Harness") || name.startsWith("Mock");

function forgeSizesJson() {
  try {
    return execFileSync("forge", ["build", "--sizes", "--json"], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch (err) {
    // Over-limit test harnesses make forge exit non-zero; its JSON is still on stdout.
    if (err.stdout) return err.stdout;
    throw err;
  }
}

const sizes = JSON.parse(forgeSizesJson());

const rows = Object.entries(sizes)
  .filter(([name, m]) => !isExempt(name) && m.runtime_size > 0)
  .map(([name, m]) => ({ name, size: m.runtime_size }))
  .sort((a, b) => b.size - a.size);

for (const { name, size } of rows) {
  const tag = size > LIMIT ? "OVER" : " ok ";
  console.log(`  [${tag}] ${name.padEnd(28)} ${String(size).padStart(6)} B  (margin ${LIMIT - size})`);
}

const over = rows.filter((r) => r.size > LIMIT);
if (over.length > 0) {
  for (const { name, size } of over) {
    console.error(`::error::${name} runtime code ${size} B exceeds EIP-170 limit ${LIMIT} B by ${size - LIMIT} B`);
  }
  process.exit(1);
}

console.log(`\n✓ All ${rows.length} deployed contracts within EIP-170 (${LIMIT} B).`);
