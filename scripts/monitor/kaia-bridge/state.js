const fs = require("fs");
const path = require("path");

const STATE_FILE = path.join(__dirname, "state.json");

const defaultState = {
  block_number: 0,
  last_scanned_seq: 0,
  timestamp: new Date().toISOString(),
  errors: [],
};

function loadState() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      const data = fs.readFileSync(STATE_FILE, "utf8");
      return JSON.parse(data);
    }
  } catch (error) {
    console.error("Failed to load state:", error);
  }
  return { ...defaultState };
}

function saveState(newState) {
  try {
    const currentState = loadState();
    const updatedState = { ...currentState, ...newState, timestamp: new Date().toISOString() };
    fs.writeFileSync(STATE_FILE, JSON.stringify(updatedState, null, 2));
  } catch (error) {
    console.error("Failed to save state:", error);
  }
}

module.exports = {
  loadState,
  saveState,
};
