#!/bin/bash
set -e

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# reset
./script/gasless/qa/cleanup.sh

echo -e "${BLUE}===== Gasless Transaction Test Script =====${NC}"

# Step 1: Run the test
echo -e "${BLUE}Running script...${NC}"
npx hardhat run script/gasless/qa/prepare-and-run-test.ts --network homi
