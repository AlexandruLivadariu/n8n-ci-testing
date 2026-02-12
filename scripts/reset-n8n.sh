#!/bin/bash

# Reset n8n test environment (clears all data)

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔄 Resetting n8n Test Environment${NC}"
echo "================================"
echo ""
echo -e "${RED}⚠️  WARNING: This will delete ALL data in the test environment!${NC}"
echo "   - All workflows"
echo "   - All credentials"
echo "   - All executions"
echo "   - User accounts"
echo ""
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Cancelled."
  exit 0
fi

echo ""
echo -e "${YELLOW}Step 1: Stopping containers${NC}"
docker stop n8n-test n8n-postgres-test 2>/dev/null || true

echo -e "${YELLOW}Step 2: Removing containers${NC}"
docker rm n8n-test n8n-postgres-test 2>/dev/null || true

echo -e "${YELLOW}Step 3: Removing volumes (data will be deleted)${NC}"
docker volume rm docker_n8n-test-data docker_postgres-test-data 2>/dev/null || true

echo -e "${YELLOW}Step 4: Starting fresh environment${NC}"
cd ../docker
docker-compose -f docker-compose.test.yml up -d

echo ""
echo -e "${YELLOW}Waiting for services to start...${NC}"
sleep 10

# Wait for n8n to be ready
echo "Checking n8n..."
for i in {1..30}; do
  if curl -s http://localhost:5679 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ n8n is ready!${NC}"
    break
  fi
  sleep 2
  echo "  Waiting... ($i/30)"
done

echo ""
echo -e "${GREEN}✅ Reset complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Go to http://localhost:5679"
echo "  2. Complete owner setup with:"
echo "     Email: ci@test.local"
echo "     Password: TestPassword123!"
echo "  3. Then run: ./import-test-workflows.sh"
