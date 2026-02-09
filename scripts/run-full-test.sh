#!/bin/bash
# Complete automated test run - starts environment, imports workflows, runs tests

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Bypass proxy for localhost
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     n8n Automated Test Suite - Full Run                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Start test environment
echo -e "${BLUE}[1/4] Starting test environment...${NC}"
cd "$SCRIPT_DIR"
chmod +x start-test-env.sh
./start-test-env.sh
echo ""

# Step 2: Import test workflows (optional - continue on failure)
echo -e "${BLUE}[2/4] Importing test workflows...${NC}"
cd "$SCRIPT_DIR"
chmod +x import-test-workflows.sh

if [ -n "$N8N_TEST_API_KEY" ]; then
  echo "API key found, attempting import..."
  ./import-test-workflows.sh || echo -e "${YELLOW}⚠️  Workflow import failed (API key issue) - continuing with existing workflows${NC}"
else
  echo -e "${YELLOW}⚠️  N8N_TEST_API_KEY not set - skipping workflow import${NC}"
  echo "   Assuming workflows are already imported or will be imported manually"
fi
echo ""

# Step 3: Run webhook tests
echo -e "${BLUE}[3/4] Running webhook tests...${NC}"
cd "$SCRIPT_DIR"
chmod +x test-webhooks.sh
./test-webhooks.sh
WEBHOOK_RESULT=$?
echo ""

# Step 4: Run full test suite
echo -e "${BLUE}[4/4] Running full test suite...${NC}"
cd "$PROJECT_ROOT/tests"
chmod +x runner.sh
./runner.sh --mode=health-check
TEST_RESULT=$?
echo ""

# Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Test Run Complete                                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ $WEBHOOK_RESULT -eq 0 ] && [ $TEST_RESULT -eq 0 ]; then
  echo -e "${GREEN}✅ All tests passed!${NC}"
  echo ""
  echo "Test results available in:"
  echo "  - tests/results/test-report.json"
  echo "  - logs/test-results.log"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  echo ""
  echo "Check logs for details:"
  echo "  - tests/results/test-report.json"
  echo "  - logs/test-results.log"
  exit 1
fi
