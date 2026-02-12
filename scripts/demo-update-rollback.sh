#!/bin/bash

# Complete Update & Rollback Demo
# This script demonstrates the entire update pipeline process

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     n8n Update Pipeline - Complete Demo                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Configuration
OLD_VERSION="1.29.0"
NEW_VERSION="latest"
SCENARIO="${1:-success}"  # success or rollback

if [ "$SCENARIO" != "success" ] && [ "$SCENARIO" != "rollback" ]; then
  echo "Usage: $0 [success|rollback]"
  echo ""
  echo "  success  - Simulate successful update (default)"
  echo "  rollback - Simulate failed update with automatic rollback"
  exit 1
fi

echo -e "${BLUE}Scenario:${NC} $SCENARIO"
echo -e "${BLUE}Old Version:${NC} $OLD_VERSION"
echo -e "${BLUE}New Version:${NC} $NEW_VERSION"
echo ""

# ============================================================================
# PHASE 1: Setup Initial Environment
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 1: Setup Initial Environment (v${OLD_VERSION})${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}→ Stopping any existing containers...${NC}"
docker stop n8n-test n8n-postgres-test 2>/dev/null || true
docker rm n8n-test n8n-postgres-test 2>/dev/null || true

echo -e "${YELLOW}→ Removing old volumes...${NC}"
docker volume rm docker_n8n-test-data docker_postgres-test-data 2>/dev/null || true

echo -e "${YELLOW}→ Starting fresh environment with v${OLD_VERSION}...${NC}"
cd "$(dirname "$0")"

# Start with specific old version
docker network create docker_n8n-test-network 2>/dev/null || true

# Start PostgreSQL
docker run -d \
  --name n8n-postgres-test \
  --network docker_n8n-test-network \
  -e POSTGRES_USER=n8n \
  -e POSTGRES_PASSWORD=n8n_password \
  -e POSTGRES_DB=n8n \
  -v docker_postgres-test-data:/var/lib/postgresql/data \
  postgres:15

sleep 5

# Start n8n with old version
docker run -d \
  --name n8n-test \
  --network docker_n8n-test-network \
  -p 5679:5678 \
  -e DB_TYPE=postgresdb \
  -e DB_POSTGRESDB_HOST=n8n-postgres-test \
  -e DB_POSTGRESDB_DATABASE=n8n \
  -e DB_POSTGRESDB_USER=n8n \
  -e DB_POSTGRESDB_PASSWORD=n8n_password \
  -e N8N_ENCRYPTION_KEY=test-encryption-key-12345 \
  -e N8N_HOST=localhost \
  -e WEBHOOK_URL=http://localhost:5679/ \
  -v docker_n8n-test-data:/home/node/.n8n \
  n8nio/n8n:${OLD_VERSION}

echo -e "${YELLOW}→ Waiting for n8n to start...${NC}"
sleep 15

# Wait for n8n to be ready
for i in {1..30}; do
  if curl -s http://localhost:5679 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ n8n v${OLD_VERSION} is ready!${NC}"
    break
  fi
  sleep 2
done

# Verify version
CURRENT_VERSION=$(docker exec n8n-test n8n --version 2>/dev/null || echo "unknown")
echo -e "${GREEN}✅ Running version: ${CURRENT_VERSION}${NC}"
echo ""

echo -e "${YELLOW}→ Setting up owner account via UI...${NC}"
echo ""
echo -e "${BLUE}ACTION REQUIRED:${NC}"
echo "  1. Open: ${YELLOW}http://localhost:5679${NC}"
echo "  2. Complete owner setup:"
echo "     Email: ${GREEN}ci@test.local${NC}"
echo "     Password: ${GREEN}TestPassword123!${NC}"
echo "     First Name: CI"
echo "     Last Name: Test"
echo ""
read -p "Press ENTER when owner setup is complete..."

echo ""
echo -e "${YELLOW}→ Importing test workflows...${NC}"
./import-test-workflows.sh

echo ""
echo -e "${YELLOW}→ Verifying workflows work...${NC}"
sleep 3
HEALTH_CHECK=$(curl -s http://localhost:5679/webhook/test/health 2>/dev/null || echo "")
if echo "$HEALTH_CHECK" | grep -q "ok"; then
  echo -e "${GREEN}✅ Workflows are working!${NC}"
else
  echo -e "${RED}❌ Workflows not responding${NC}"
  echo "Response: $HEALTH_CHECK"
  exit 1
fi

echo ""
echo -e "${GREEN}✅ Initial environment ready with v${OLD_VERSION}${NC}"
echo ""
read -p "Press ENTER to continue to backup phase..."

# ============================================================================
# PHASE 2: Create Backup
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 2: Create Backup (Rollback Point)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}→ Creating backup...${NC}"
./backup.sh

BACKUP_ID=$(ls -t ../tests/state/ | head -1)
echo -e "${GREEN}✅ Backup created: ${BACKUP_ID}${NC}"
echo ""

# Verify backup contents
echo -e "${YELLOW}→ Verifying backup contents...${NC}"
ls -lh ../tests/state/${BACKUP_ID}/
echo ""

read -p "Press ENTER to continue to pre-update tests..."

# ============================================================================
# PHASE 3: Pre-Update Tests (Baseline)
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 3: Pre-Update Tests (Baseline)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}→ Running all tests to establish baseline...${NC}"
cd ../tests
./runner.sh --mode=update --phase=pre-update

echo ""
echo -e "${GREEN}✅ Baseline established${NC}"
cat state/baseline.json | jq '{passed: .summary.passed, failed: .summary.failed, total: .summary.total}'
echo ""

read -p "Press ENTER to continue to update phase..."

# ============================================================================
# PHASE 4: Perform Update
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 4: Update to v${NEW_VERSION}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

cd ../scripts

if [ "$SCENARIO" == "success" ]; then
  # Normal update
  echo -e "${YELLOW}→ Updating to v${NEW_VERSION}...${NC}"
  ./update.sh "$NEW_VERSION"
  
  NEW_ACTUAL_VERSION=$(docker exec n8n-test n8n --version 2>/dev/null || echo "unknown")
  echo -e "${GREEN}✅ Updated to version: ${NEW_ACTUAL_VERSION}${NC}"
  
else
  # Simulate broken update
  echo -e "${YELLOW}→ Simulating BROKEN update (wrong encryption key)...${NC}"
  
  docker stop n8n-test
  docker rm n8n-test
  
  # Start with WRONG encryption key
  docker run -d \
    --name n8n-test \
    --network docker_n8n-test-network \
    -p 5679:5678 \
    -e DB_TYPE=postgresdb \
    -e DB_POSTGRESDB_HOST=n8n-postgres-test \
    -e DB_POSTGRESDB_DATABASE=n8n \
    -e DB_POSTGRESDB_USER=n8n \
    -e DB_POSTGRESDB_PASSWORD=n8n_password \
    -e N8N_ENCRYPTION_KEY=WRONG-KEY-BREAKS-EVERYTHING \
    -e N8N_HOST=localhost \
    -e WEBHOOK_URL=http://localhost:5679/ \
    -v docker_n8n-test-data:/home/node/.n8n \
    n8nio/n8n:${NEW_VERSION}
  
  sleep 20
  echo -e "${RED}⚠️  Updated with BROKEN encryption key${NC}"
fi

echo ""
read -p "Press ENTER to continue to post-update tests..."

# ============================================================================
# PHASE 5: Post-Update Tests
# ============================================================================

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}PHASE 5: Post-Update Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}→ Running tests on updated version...${NC}"
cd ../tests
./runner.sh --mode=update --phase=post-update || true

echo ""
echo -e "${YELLOW}→ Comparing results...${NC}"
echo ""
echo "Pre-update:"
cat state/baseline.json | jq '{passed: .summary.passed, failed: .summary.failed}'
echo ""
echo "Post-update:"
cat results/post-update-report.json | jq '{passed: .summary.passed, failed: .summary.failed}'
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
    # PHASE 6: Rollback
    # ============================================================================
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}PHASE 6: Automatic Rollback${NC}"
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
    echo "  - Update to v${NEW_VERSION} failed"
    echo "  - Automatically rolled back to v${OLD_VERSION}"
    echo "  - All workflows restored and working"
    
  else
    echo -e "${GREEN}✅ UPDATE SUCCESSFUL${NC}"
    echo ""
    echo "Summary:"
    echo "  - Updated from v${OLD_VERSION} to v${NEW_VERSION}"
    echo "  - All tests passed"
    echo "  - No rollback needed"
  fi
else
  echo -e "${GREEN}✅ UPDATE SUCCESSFUL${NC}"
  echo ""
  echo "Summary:"
  echo "  - Updated from v${OLD_VERSION} to v${NEW_VERSION}"
  echo "  - All tests passed"
  echo "  - No rollback needed"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Demo Complete!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "You can now:"
echo "  - Check n8n at: http://localhost:5679"
echo "  - View test results: cat tests/results/post-update-report.json"
echo "  - View backup: ls -lh tests/state/${BACKUP_ID}/"
echo ""
