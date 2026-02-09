#!/bin/bash
# Stop n8n test environment

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}🛑 Stopping n8n Test Environment${NC}"
echo "================================"
echo ""

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Stop test instance
docker-compose -f docker-compose.test.yml down

echo ""
echo -e "${GREEN}✅ Test environment stopped${NC}"
