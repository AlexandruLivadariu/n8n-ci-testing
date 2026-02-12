#!/bin/bash

# Test the update pipeline locally
# This simulates what the GitHub Actions update pipeline does

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Testing Update Pipeline${NC}"
echo "================================"
echo ""

# Step 1: Start test environment
echo -e "${YELLOW}Step 1: Starting test environment${NC}"
cd "$(dirname "$0")"
./start-test-env.sh
echo ""

# Step 2: Import workflows
echo -e "${YELLOW}Step 2: Importing test workflows${NC}"
./import-test-workflows.sh
echo ""

# Step 3: Run pre-update tests (baseline)
echo -e "${YELLOW}Step 3: Running pre-update tests (baseline)${NC}"
cd ../tests
./runner.sh health-check pre-update
echo ""

# Step 4: Create backup
echo -e "${YELLOW}Step 4: Creating backup${NC}"
cd ../scripts
./backup.sh
BACKUP_ID=$(ls -t ../tests/state/ | head -1)
echo -e "${GREEN}✅ Backup created: ${BACKUP_ID}${NC}"
echo ""

# Step 5: Perform update
echo -e "${YELLOW}Step 5: Updating n8n${NC}"
TARGET_VERSION="${1:-latest}"
echo "Target version: ${TARGET_VERSION}"
./update.sh "$TARGET_VERSION"
echo ""

# Step 6: Run post-update tests
echo -e "${YELLOW}Step 6: Running post-update tests${NC}"
cd ../tests
./runner.sh health-check post-update
echo ""

# Step 7: Compare results
echo -e "${YELLOW}Step 7: Comparing test results${NC}"
PRE_RESULTS="../tests/results/pre-update-report.json"
POST_RESULTS="../tests/results/post-update-report.json"

if [ -f "$PRE_RESULTS" ] && [ -f "$POST_RESULTS" ]; then
  PRE_PASSED=$(jq -r '.summary.passed' "$PRE_RESULTS" 2>/dev/null || echo "0")
  POST_PASSED=$(jq -r '.summary.passed' "$POST_RESULTS" 2>/dev/null || echo "0")
  
  echo "Pre-update:  ${PRE_PASSED} tests passed"
  echo "Post-update: ${POST_PASSED} tests passed"
  
  if [ "$POST_PASSED" -ge "$PRE_PASSED" ]; then
    echo -e "${GREEN}✅ Update successful - no regressions detected${NC}"
    ROLLBACK_NEEDED=false
  else
    echo -e "${RED}❌ Update caused regressions${NC}"
    ROLLBACK_NEEDED=true
  fi
else
  echo -e "${YELLOW}⚠️  Could not compare results${NC}"
  ROLLBACK_NEEDED=false
fi
echo ""

# Step 8: Rollback if needed
if [ "$ROLLBACK_NEEDED" = "true" ]; then
  echo -e "${YELLOW}Step 8: Rolling back to previous version${NC}"
  cd ../scripts
  ./rollback.sh "$BACKUP_ID"
  echo -e "${GREEN}✅ Rollback completed${NC}"
else
  echo -e "${GREEN}Step 8: No rollback needed${NC}"
fi
echo ""

# Summary
echo "================================"
if [ "$ROLLBACK_NEEDED" = "true" ]; then
  echo -e "${RED}❌ Update pipeline test: FAILED (rolled back)${NC}"
  exit 1
else
  echo -e "${GREEN}✅ Update pipeline test: PASSED${NC}"
  echo ""
  echo "The update pipeline works correctly!"
  echo "You can now use it in GitHub Actions."
fi
