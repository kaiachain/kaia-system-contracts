#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}===== Cleaning up test environment =====${NC}"

# Remove temporary files
if [ -d "./script/gasless/qa/temp" ]; then
    echo -e "Removing temporary directory..."
    rm -rf ./script/gasless/qa/temp
    echo -e "${GREEN}✅ Temporary files removed${NC}"
    rm -rf ./deployments/homi
else
    echo -e "${YELLOW}No temporary directory found${NC}"
fi

echo -e "${BLUE}===== Cleanup Complete =====${NC}"
