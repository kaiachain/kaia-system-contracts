const { runRealTime, runBackground } = require("./monitor");
const { loadState } = require("./state");

async function main() {
  console.log("Starting Bridge Monitor Test...");
  console.log("---------------------------------------------------");

  // 1. Run Real-Time Checks
  console.log("\nRunning Real-Time Checks (Flags, Auth, Balance)...");
  const realTimeResult = await runRealTime();

  if (realTimeResult.status === "OK") {
    console.log("✅ Real-Time Checks PASSED");
  } else {
    console.log("❌ Real-Time Checks FAILED");
    realTimeResult.errors.forEach((e) => console.log(`   - ${e}`));
  }
  console.log(
    "   Data:",
    JSON.stringify(realTimeResult.data, (key, value) => (typeof value === "bigint" ? value.toString() : value), 2),
  );

  // 2. Run Background Checks
  console.log("\nRunning Background Checks (Heavy operations)...");
  await runBackground();
  const state = loadState();

  if (state.background_status === "OK") {
    console.log("✅ Background Checks PASSED");
  } else {
    console.log("❌ Background Checks FAILED");
    (state.background_errors || []).forEach((e) => console.log(`   - ${e}`));
  }
  console.log("   Data:", JSON.stringify(state.background_data, null, 2));

  console.log("\n---------------------------------------------------");
  console.log("Test Completed.");
}

main();
