const express = require("express");
const cron = require("node-cron");
const config = require("./config");
const { runRealTime, runBackground } = require("./monitor");
const { loadState } = require("./state");

const app = express();

// Endpoints
app.get("/bridge-monitor", async (req, res) => {
  const state = loadState();
  const realTimeResult = await runRealTime();

  // Combine Status
  const isBackgroundOk = state.background_status === "OK" || state.background_status === undefined;
  const isRealTimeOk = realTimeResult.status === "OK";

  if (isBackgroundOk && isRealTimeOk) {
    res.status(200).send("OK");
  } else {
    // Return 500 on error so GCP alerts
    res.status(500).json({
      error: "Monitoring Check Failed",
      realTimeErrors: realTimeResult.errors,
      backgroundErrors: state.background_errors || [],
      timestamp: new Date().toISOString(),
    });
  }
});

app.get("/bridge-monitor/status", async (req, res) => {
  const state = loadState();
  const realTimeResult = await runRealTime();

  res.json({
    realTime: realTimeResult,
    background: state,
  });
});

// Schedule the background monitoring task
cron.schedule(config.monitoring.cronSchedule, () => {
  runBackground();
});

// Run background check immediately on startup
runBackground();

app.listen(config.monitoring.port, () => {
  console.log(`Kaia Bridge Monitor running on port ${config.monitoring.port}`);
});
