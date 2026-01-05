const ethers = require("ethers");
const config = require("./config");
const { loadState, saveState } = require("./state");

// Minimal ABIs
const BRIDGE_ABI = [
  "function getClaimCandidates() external view returns (uint64[])",
  "function provisions(uint64 seq) external view returns (tuple(uint64 seq, address sender, address receiver, uint256 amount))",
  "function getClaimFailures() external view returns (uint64[])",
  "function pause() external view returns (bool)",
  "function transferFromKaiaOn() external view returns (bool)",
  "function nTransferHolds() external view returns (uint256)",
  "function operator() external view returns (address)",
  "function guardian() external view returns (address)",
  "function judge() external view returns (address)",
  "function nextProvisionSeq() external view returns (uint64)",
];

const HOLDER_VERIFIER_ABI = [
  "function provisionedConyBalances() external view returns (uint256)",
  "function owner() external view returns (address)",
  "function operator() external view returns (address)",
];

const MULTICALL3_ABI = [
  "function aggregate(tuple(address target, bytes callData)[] calls) payable returns (uint256 blockNumber, bytes[] returnData)",
];

async function getProvider(url) {
  return new ethers.JsonRpcProvider(url);
}

// --- Real-Time Checks (Lightweight) ---
// Checks: Flags, Authorities, Bridge Balance (simple), Next Provision Seq
async function checkRealTime(providerName, provider) {
  const bridge = new ethers.Contract(config.contracts.bridge, BRIDGE_ABI, provider);
  const holderVerifier = new ethers.Contract(config.contracts.holderVerifier, HOLDER_VERIFIER_ABI, provider);
  const multicall = new ethers.Contract(config.contracts.multicall3, MULTICALL3_ABI, provider);

  // Use a slightly older block to avoid RPC sync issues
  const latestBlock = await provider.getBlockNumber();
  const targetBlock = latestBlock - 10;

  const calls = [
    // Bridge Status
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("pause", []) },
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("transferFromKaiaOn", []) },
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("nTransferHolds", []) },
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("operator", []) },
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("guardian", []) },
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("judge", []) },
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("nextProvisionSeq", []) },
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("getClaimFailures", []) },

    // HolderVerifier Status (Simple getters)
    { target: config.contracts.holderVerifier, callData: holderVerifier.interface.encodeFunctionData("owner", []) },
    { target: config.contracts.holderVerifier, callData: holderVerifier.interface.encodeFunctionData("operator", []) },
  ];

  const { blockNumber, returnData } = await multicall.aggregate.staticCall(calls, { blockTag: targetBlock });
  const bn = blockNumber.toString();

  const results = {
    pause: bridge.interface.decodeFunctionResult("pause", returnData[0])[0],
    transferFromKaiaOn: bridge.interface.decodeFunctionResult("transferFromKaiaOn", returnData[1])[0],
    nTransferHolds: bridge.interface.decodeFunctionResult("nTransferHolds", returnData[2])[0],
    bridgeOperator: bridge.interface.decodeFunctionResult("operator", returnData[3])[0],
    bridgeGuardian: bridge.interface.decodeFunctionResult("guardian", returnData[4])[0],
    bridgeJudge: bridge.interface.decodeFunctionResult("judge", returnData[5])[0],
    nextProvisionSeq: bridge.interface.decodeFunctionResult("nextProvisionSeq", returnData[6])[0],
    claimFailures: bridge.interface.decodeFunctionResult("getClaimFailures", returnData[7])[0],
    hvOwner: holderVerifier.interface.decodeFunctionResult("owner", returnData[8])[0],
    hvOperator: holderVerifier.interface.decodeFunctionResult("operator", returnData[9])[0],
  };

  const bridgeBalance = await provider.getBalance(config.contracts.bridge, targetBlock);

  const errors = [];

  // --- Check #3: Claim Failures ---
  if (results.claimFailures.length > 0) {
    errors.push(
      `[ClaimFailures] Found ${results.claimFailures.length} stuck payouts: ${results.claimFailures.join(", ")}`,
    );
  }

  // --- Check #5: Pause / Transfer / Hold Flags ---
  if (results.pause !== false) errors.push(`[Flags] Bridge is PAUSED`);
  if (results.transferFromKaiaOn !== true) errors.push(`[Flags] TransferFromKaiaOn is FALSE`);
  if (results.nTransferHolds > 0) errors.push(`[Flags] nTransferHolds > 0 (${results.nTransferHolds})`);

  // --- Check #6: Authority / Control Addresses ---
  if (results.bridgeOperator !== config.authorities.operator)
    errors.push(`[Auth] Bridge Operator mismatch: ${results.bridgeOperator}`);
  if (results.bridgeGuardian !== config.authorities.guardian)
    errors.push(`[Auth] Bridge Guardian mismatch: ${results.bridgeGuardian}`);
  if (results.bridgeJudge !== config.authorities.judge)
    errors.push(`[Auth] Bridge Judge mismatch: ${results.bridgeJudge}`);
  if (results.hvOwner !== config.authorities.owner)
    errors.push(`[Auth] HolderVerifier Owner mismatch: ${results.hvOwner}`);
  if (results.hvOperator !== config.authorities.operator)
    errors.push(`[Auth] HolderVerifier Operator mismatch: ${results.hvOperator}`);

  return {
    providerName,
    blockNumber: bn,
    bridgeBalance,
    ...results,
    errors,
  };
}

// --- Background Checks (Heavy) ---
// Checks: Claim Candidates (Unclaimed Sum), Claim Failures, HolderVerifier Totals
async function checkBackground(providerName, provider) {
  const bridge = new ethers.Contract(config.contracts.bridge, BRIDGE_ABI, provider);
  const holderVerifier = new ethers.Contract(config.contracts.holderVerifier, HOLDER_VERIFIER_ABI, provider);
  const multicall = new ethers.Contract(config.contracts.multicall3, MULTICALL3_ABI, provider);

  // Use a slightly older block to avoid RPC sync issues
  const latestBlock = await provider.getBlockNumber();
  const targetBlock = latestBlock - 10;

  const calls = [
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("getClaimCandidates", []) },
    {
      target: config.contracts.holderVerifier,
      callData: holderVerifier.interface.encodeFunctionData("provisionedConyBalances", []),
    },
    { target: config.contracts.bridge, callData: bridge.interface.encodeFunctionData("nextProvisionSeq", []) }, // Added
  ];

  const { blockNumber, returnData } = await multicall.aggregate.staticCall(calls, { blockTag: targetBlock });
  const bn = blockNumber.toString();

  const results = {
    claimCandidates: bridge.interface.decodeFunctionResult("getClaimCandidates", returnData[0])[0],
    provisionedConyBalances: holderVerifier.interface.decodeFunctionResult("provisionedConyBalances", returnData[1])[0],
    nextProvisionSeq: bridge.interface.decodeFunctionResult("nextProvisionSeq", returnData[2])[0], // Added
  };

  // --- Check #1: Bridge Balance vs. Total Unclaimed Provisions ---
  let totalUnclaimed = BigInt(0);
  if (results.claimCandidates.length > 0) {
    // Batching logic could be added here if needed
    const provisionCalls = results.claimCandidates.map((seq) => ({
      target: config.contracts.bridge,
      callData: bridge.interface.encodeFunctionData("provisions", [seq]),
    }));

    const { returnData: provReturnData } = await multicall.aggregate.staticCall(provisionCalls, {
      blockTag: targetBlock,
    });

    provReturnData.forEach((data) => {
      const decoded = bridge.interface.decodeFunctionResult("provisions", data)[0];
      totalUnclaimed += decoded.amount;
    });
  }

  const errors = [];

  // --- Check #2: HolderVerifier Totals ---
  const state = loadState();
  const prevProvisioned = BigInt(state.last_provisioned_cony_balances || "0");
  if (results.provisionedConyBalances < prevProvisioned) {
    errors.push(
      `[HolderVerifier] Provisioned balance decreased! Prev: ${prevProvisioned}, Curr: ${results.provisionedConyBalances}`,
    );
  }

  // --- Check #4: Sequential Provision Check ---
  // Verify all provision sequences from last scanned up to nextProvisionSeq (max 100 per run).
  let lastScannedSeq = BigInt(state.last_scanned_seq || 0);
  const nextSeq = results.nextProvisionSeq;
  let startSeq = lastScannedSeq;

  const MAX_BATCH_SIZE = 100;
  let checkedUpTo = lastScannedSeq;

  if (nextSeq > startSeq) {
    const diff = nextSeq - startSeq;
    const count = diff > BigInt(MAX_BATCH_SIZE) ? BigInt(MAX_BATCH_SIZE) : diff;
    const endSeq = startSeq + count; // Exclusive of the batch end? No, let's make it simple loop.

    const checkCalls = [];
    for (let i = startSeq; i < endSeq; i++) {
      checkCalls.push({
        target: config.contracts.bridge,
        callData: bridge.interface.encodeFunctionData("provisions", [i]),
      });
    }

    if (checkCalls.length > 0) {
      const { returnData: checkReturnData } = await multicall.aggregate.staticCall(checkCalls, {
        blockTag: targetBlock,
      });

      checkReturnData.forEach((data, index) => {
        const seqToCheck = startSeq + BigInt(index);
        const decoded = bridge.interface.decodeFunctionResult("provisions", data)[0];
        const decodedSeq = BigInt(decoded.seq);

        // Check provision exists (sender != 0x0)
        if (decoded.sender === ethers.ZeroAddress) {
          errors.push(`[SequentialCheck] Provision missing or empty at seq ${seqToCheck}`);
        }

        // Ensure on-chain seq matches the expected value to catch gaps or reordering
        if (decodedSeq !== seqToCheck) {
          errors.push(`[SequentialCheck] Seq mismatch: expected ${seqToCheck}, got ${decodedSeq}`);
        }

        checkedUpTo = seqToCheck + BigInt(1);
      });
    }
  }

  return {
    providerName,
    blockNumber: bn,
    totalUnclaimed,
    lastScannedSeq: checkedUpTo.toString(), // Return updated seq
    ...results,
    errors,
  };
}

// Wrapper to run real-time checks
async function runRealTime() {
  try {
    const primaryProvider = await getProvider(config.rpc.primary);
    // Execute requests in parallel on both providers and compare results.

    const secondaryProvider = await getProvider(config.rpc.secondary);

    const [primary, secondary] = await Promise.all([
      checkRealTime("primary", primaryProvider),
      checkRealTime("secondary", secondaryProvider),
    ]);

    // Prefix provider name so duplicates are distinguishable
    const prefixErrors = (label, errs = []) => errs.map((err) => `[${label}] ${err}`);
    const errors = [...prefixErrors("primary", primary.errors), ...prefixErrors("secondary", secondary.errors)];

    // Consistency checks
    if (primary.bridgeBalance.toString() !== secondary.bridgeBalance.toString()) {
      errors.push("[Consistency] Bridge balance mismatch");
    }
    if (primary.pause !== secondary.pause) errors.push("[Consistency] Pause flag mismatch");
    if (primary.transferFromKaiaOn !== secondary.transferFromKaiaOn)
      errors.push("[Consistency] TransferFromKaiaOn mismatch");
    if (primary.nTransferHolds !== secondary.nTransferHolds) errors.push("[Consistency] nTransferHolds mismatch");
    if (primary.nextProvisionSeq !== secondary.nextProvisionSeq) errors.push("[Consistency] NextProvisionSeq mismatch");
    if (primary.bridgeOperator !== secondary.bridgeOperator) errors.push("[Consistency] Bridge Operator mismatch");
    if (primary.bridgeGuardian !== secondary.bridgeGuardian) errors.push("[Consistency] Bridge Guardian mismatch");
    if (primary.bridgeJudge !== secondary.bridgeJudge) errors.push("[Consistency] Bridge Judge mismatch");
    if (primary.hvOwner !== secondary.hvOwner) errors.push("[Consistency] HolderVerifier Owner mismatch");
    if (primary.hvOperator !== secondary.hvOperator) errors.push("[Consistency] HolderVerifier Operator mismatch");

    // Compare claim failures arrays
    if (JSON.stringify(primary.claimFailures) !== JSON.stringify(secondary.claimFailures)) {
      errors.push("[Consistency] Claim failures mismatch");
    }

    return {
      status: errors.length > 0 ? "ERROR" : "OK",
      errors,
      data: { primary, secondary },
    };
  } catch (e) {
    return { status: "ERROR", errors: [e.message] };
  }
}

// Wrapper to run background checks
async function runBackground() {
  console.log(`[Background] Starting run at ${new Date().toISOString()}`);
  try {
    const primaryProvider = await getProvider(config.rpc.primary);
    const secondaryProvider = await getProvider(config.rpc.secondary);

    const [primary, secondary] = await Promise.all([
      checkBackground("primary", primaryProvider),
      checkBackground("secondary", secondaryProvider),
    ]);

    const errors = [...primary.errors, ...secondary.errors];

    // Consistency checks between primary and secondary
    if (primary.nextProvisionSeq !== secondary.nextProvisionSeq) {
      errors.push("[Consistency] NextProvisionSeq mismatch");
    }
    if (primary.provisionedConyBalances.toString() !== secondary.provisionedConyBalances.toString()) {
      errors.push("[Consistency] ProvisionedConyBalances mismatch");
    }
    // Compare claim candidates arrays (convert BigInt elements to strings)
    const primaryCandidatesStr = primary.claimCandidates.map((c) => c.toString()).join(",");
    const secondaryCandidatesStr = secondary.claimCandidates.map((c) => c.toString()).join(",");
    if (primaryCandidatesStr !== secondaryCandidatesStr) {
      errors.push("[Consistency] ClaimCandidates mismatch");
    }
    if (primary.totalUnclaimed.toString() !== secondary.totalUnclaimed.toString()) {
      errors.push("[Consistency] TotalUnclaimed mismatch");
    }

    // --- Check #1: Bridge Balance vs. Total Unclaimed (Validation) ---
    const bridgeBalance = await primaryProvider.getBalance(config.contracts.bridge);
    if (bridgeBalance < primary.totalUnclaimed) {
      errors.push(`[Balance] Bridge balance (${bridgeBalance}) < Total Unclaimed (${primary.totalUnclaimed})`);
    }

    const newState = {
      block_number: Number(primary.blockNumber),
      timestamp: new Date().toISOString(),
      last_scanned_seq: primary.lastScannedSeq,
      last_provisioned_cony_balances: primary.provisionedConyBalances.toString(),
      background_status: errors.length > 0 ? "ERROR" : "OK",
      background_errors: errors,
      background_data: {
        totalUnclaimed: primary.totalUnclaimed.toString(),
      },
    };

    saveState(newState);
    console.log(`[Background] Completed. Status: ${newState.background_status}`);
  } catch (e) {
    console.error("[Background] Failed:", e);
    saveState({
      background_status: "ERROR",
      background_errors: [e.message],
    });
  }
}

module.exports = {
  runRealTime,
  runBackground,
};
