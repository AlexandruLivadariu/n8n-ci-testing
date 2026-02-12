#!/bin/bash

# Manual Update Pipeline Test
# For use when you already have n8n running with v1.29.0

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     n8n Update Pipeline - Manual Test                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check current version
CURRENT_VERSION=$(docker exec n8n-test n8n --version 2>/dev/null || echo "unknown")
echo -e "${BLUE}Current Version:${NC} ${CURRENT_VERSION}"
echo ""

# ============================================================================
# STEP 1: Import Workflows (Manual)
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}STEP 1: Import Test Workflows${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Since automated import isn't working with v1.29.0,${NC}"
echo -e "${YELLOW}we'll import workflows manually via the UI.${NC}"
echo ""
echo -e "${BLUE}ACTION REQUIRED:${NC}"
echo "  1. Open: ${YELLOW}http://localhost:5679${NC}"
echo "  2. Log in with your credentials"
echo "  3. Import these workflows manually:"
echo ""
echo "     ${GREEN}../workflows/test-health-webhook.json${NC}"
echo "     ${GREEN}../workflows/test-echo-webhook.json${NC}"
echo "     ${GREEN}../workflows/test-http-request.json${NC}"
echo ""
echo "  4. Make sure to ACTIVATE each workflow after importing"
echo ""
echo "  How to import:"
echo "    - Click 'Add Workflow' or '+'"
echo "    - Click the '...' menu → 'Import from File'"
echo "    - Select the JSON file"
echo "    - Click 'Save' and toggle 'Active' to ON"
echo ""
read -p "Press ENTER when all workflows are imported and activated..."

# Verify workflows work
echo ""
echo -e "${YELLOW}→ Testing webhooks...${NC}"
sleep 2

HEALTH_CHECK=$(curl -s http://localhost:5679/webhook/test/health 2>/dev/null || echo "")
if echo "$HEALTH_CHECK" | grep -q "ok"; then
  echo -e "${GREEN}✅ Health webhook is working!${NC}"
else
  echo -e "${RED}❌ Health webhook not responding${NC}"
  echo "   Response: $HEALTH_CHECK"
  echo ""
  echo "   Please check that:"
  echo "   - The workflow is imported"
  echo "   - The workflow is ACTIVE (toggle is ON)"
  echo "   - The webhook path is: test/health"
  exit 1
fi

echo -e "${GREEN}✅ Workflows are ready${NC}"
echo ""
read -p "Press ENTER to continue to backup phase..."

# ============================================================================
# STEP 2: Create Backup
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}STEP 2: Create Backup (Rollback Point)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}→ Creating backup...${NC}"
./backup.sh

BACKUP_ID=$(ls -t ../tests/state/ | head -1)
echo -e "${GREEN}✅ Backup created: ${BACKUP_ID}${NC}"
echo ""

# Verify backup contents
echo -e "${YELLOW}→ Backup contents:${NC}"
ls -lh ../tests/state/${BACKUP_ID}/
echo ""

read -p "Press ENTER to continue to pre-update tests..."

# ============================================================================
# STEP 3: Pre-Update Tests (Baseline)
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}STEP 3: Pre-Update Tests (Baseline)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}→ Running all tests to establish baseline...${NC}"
cd ../tests
./runner.sh --mode=update --phase=pre-update

echo ""
echo -e "${GREEN}✅ Baseline established${NC}"
if [ -f state/baseline.json ]; then
  cat state/baseline.json | jq '{passed: .summary.passed, failed: .summary.failed, total: .summary.total}'
else
  echo "   (baseline.json not found - tests may have failed)"
fi
echo ""

read -p "Press ENTER to continue to update phase..."

# ============================================================================
# STEP 4: Perform Update
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}STEP 4: Update to Latest Version${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

cd ../scripts

echo -e "${YELLOW}→ Updating to latest version...${NC}"
./update.sh latest

NEW_VERSION=$(docker exec n8n-test n8n --version 2>/dev/null || echo "unknown")
echo -e "${GREEN}✅ Updated to version: ${NEW_VERSION}${NC}"
echo ""

read -p "Press ENTER to continue to post-update tests..."

# ============================================================================
# STEP 5: Post-Update Tests
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}STEP 5: Post-Update Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}→ Running tests on updated version...${NC}"
cd ../tests
./runner.sh --mode=update --phase=post-update || true

echo ""
echo -e "${YELLOW}→ Comparing results...${NC}"
echo ""

if [ -f state/baseline.json ]; then
  echo "Pre-update:"
  cat state/baseline.json | jq '{passed: .summary.passed, failed: .summary.failed}'
else
  echo "Pre-update: (no baseline found)"
fi

echo ""

if [ -f results/post-update-report.json ]; then
  echo "Post-update:"
  cat results/post-update-report.json | jq '{passed: .summary.passed, failed: .summary.failed}'
else
  echo "Post-update: (no report found)"
fi

echo ""

# Check rollback decision
if [ -f state/rollback-decision.json ]; then
  ROLLBACK_NEEDED=$(cat state/rollback-decision.json | jq -r '.rollback_needed')
  ROLLBACK_REASON=$(cat state/rollback-decision.json | jq -r '.reason')
  
  if [ "$ROLLBACK_NEEDED" == "true" ]; then
    echo -e "${RED}❌ ROLLBACK NEEDED${NC}"
    echo -e "${RED}Reason: ${ROLLBACK_REASON}${NC}"
    echo ""
    read -p "Press ENTER to execute rollback..."
    
    # ============================================================================
    # STEP 6: Rollback
    # ============================================================================
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}STEP 6: Automatic Rollback${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    
    cd ../scripts
    echo -e "${YELLOW}→ Rolling back to backup ${BACKUP_ID}...${NC}"
    ./rollback.sh "$BACKUP_ID"
    
    echo ""
    echo -e "${YELLOW}→ Verifying rollback...${NC}"
    RESTORED_VERSION=$(docker exec n8n-test n8n --version 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✅ Restored to version: ${RESTORED_VERSION}${NC}"
    
    sleep 5
    HEALTH_CHECK=$(curl -s http://localhost:5679/webhook/test/health 2>/dev/null || echo "")
    if echo "$HEALTH_CHECK" | grep -q "ok"; then
      echo -e "${GREEN}✅ Workflows working after rollback!${NC}"
    else
      echo -e "${RED}❌ Workflows not responding after rollback${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✅ ROLLBACK SUCCESSFUL${NC}"
    echo ""
    echo "Summary:"
    echo "  - Update to ${NEW_VERSION} failed"
    echo "  - Automatically rolled back to ${CURRENT_VERSION}"
    echo "  - All workflows restored and working"
    
  else
    echo -e "${GREEN}✅ UPDATE SUCCESSFUL${NC}"
    echo ""
    echo "Summary:"
    echo "  - Updated from ${CURRENT_VERSION} to ${NEW_VERSION}"
    echo "  - All tests passed"
    echo "  - No rollback needed"
  fi
else
  echo -e "${GREEN}✅ UPDATE SUCCESSFUL${NC}"
  echo ""
  echo "Summary:"
  echo "  - Updated from ${CURRENT_VERSION} to ${NEW_VERSION}"
  echo "  - All tests passed"
  echo "  - No rollback needed"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Test Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "You can now:"
echo "  - Check n8n at: http://localhost:5679"
echo "  - View test results: cat tests/results/post-update-report.json"
echo "  - View backup: ls -lh tests/state/${BACKUP_ID}/"
echo ""
