#!/bin/bash
# Quick test - assumes environment is already running

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

echo -e "${BLUE}🧪 Quick Test Run${NC}"
echo "================================"
echo ""

# Check if n8n is running
N8N_TEST_CHECK=$(docker ps --filter "name=n8n-test" --format "{{.Names}}" 2>/dev/null | grep "^n8n-test$" || echo "")
N8N_DEV_CHECK=$(docker ps --filter "name=n8n-dev" --format "{{.Names}}" 2>/dev/null | grep "^n8n-dev$" || echo "")

if [ -z "$N8N_TEST_CHECK" ] && [ -z "$N8N_DEV_CHECK" ]; then
  echo -e "${RED}❌ No n8n instance is running${NC}"
  echo ""
  echo "Start test environment first:"
  echo "  cd scripts && ./start-test-env.sh"
  echo ""
  echo "Or run full automated test:"
  echo "  cd scripts && ./run-full-test.sh"
  exit 1
fi

# Determine which instance is running
if [ -n "$N8N_TEST_CHECK" ]; then
  echo -e "${GREEN}✅ Using n8n-test instance${NC}"
  export TEST_CONFIG="config.yaml"
elif [ -n "$N8N_DEV_CHECK" ]; then
  echo -e "${GREEN}✅ Using n8n-dev instance${NC}"
  export TEST_CONFIG="config-dev.yaml"
fi
echo ""

# Run tests
echo -e "${BLUE}Running tests...${NC}"
cd "$PROJECT_ROOT/tests"
chmod +x runner.sh
./runner.sh --mode=health-check

echo ""
echo -e "${GREEN}✅ Test complete!${NC}"
echo "Results: tests/results/test-report.json"
