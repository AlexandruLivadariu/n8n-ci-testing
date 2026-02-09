#!/bin/bash
# Start n8n test environment

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo -e "${BLUE}🚀 Starting n8n Test Environment${NC}"
echo "================================"
echo ""

# Navigate to docker directory
cd "$PROJECT_ROOT/docker"

# Stop any existing test instance
echo -e "${YELLOW}Stopping existing test instance (if any)...${NC}"
docker-compose -f docker-compose.test.yml down -v --remove-orphans 2>/dev/null || true
echo ""

# Start test instance
echo -e "${BLUE}Starting n8n test instance...${NC}"
docker-compose -f docker-compose.test.yml up -d --remove-orphans

echo ""
echo -e "${YELLOW}Waiting for containers to start...${NC}"
sleep 5

# Check if containers exist and are running (using docker ps without grep for status)
CONTAINER_CHECK=$(docker ps --filter "name=n8n-test" --format "{{.Names}}" 2>/dev/null | grep "^n8n-test$" || echo "")
if [ -n "$CONTAINER_CHECK" ]; then
  echo -e "${GREEN}✅ n8n-test container is running${NC}"
else
  echo -e "${RED}❌ n8n-test container failed to start${NC}"
  echo "Container status:"
  docker ps -a --filter "name=n8n-test"
  echo ""
  echo "Container logs:"
  docker logs n8n-test 2>&1 || echo "Could not get logs"
  exit 1
fi

POSTGRES_CHECK=$(docker ps --filter "name=n8n-postgres-test" --format "{{.Names}}" 2>/dev/null | grep "^n8n-postgres-test$" || echo "")
if [ -n "$POSTGRES_CHECK" ]; then
  echo -e "${GREEN}✅ n8n-postgres-test container is running${NC}"
else
  echo -e "${RED}❌ n8n-postgres-test container failed to start${NC}"
  echo "Container status:"
  docker ps -a --filter "name=n8n-postgres-test"
  exit 1
fi

echo ""
echo -e "${YELLOW}Waiting for database to be ready...${NC}"
for i in {1..30}; do
  if docker exec n8n-postgres-test pg_isready -U n8n > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Database is ready!${NC}"
    break
  fi
  echo "Waiting for database... ($i/30)"
  sleep 2
done

echo ""
echo -e "${YELLOW}Waiting for n8n to be ready...${NC}"
sleep 30

echo ""
echo -e "${YELLOW}Checking n8n web interface...${NC}"
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

for i in {1..30}; do
  if curl -s --max-time 5 http://localhost:5679 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ n8n web interface is ready!${NC}"
    break
  fi
  if [ $i -eq 30 ]; then
    echo -e "${RED}❌ n8n web interface failed to respond${NC}"
    echo "Container logs:"
    docker logs n8n-test --tail 50
    exit 1
  fi
  echo "Waiting for n8n... ($i/30)"
  sleep 2
done

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  n8n Test Environment Ready!                               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}n8n URL:${NC} http://localhost:5679"
echo -e "${BLUE}Containers:${NC}"
docker ps | grep "n8n-test\|n8n-postgres-test"
echo ""
