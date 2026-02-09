#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔄 Updating n8n${NC}"
echo "================================"

# Check for target version argument
if [ -z "$1" ]; then
  echo -e "${YELLOW}⚠️  No target version specified, using 'latest'${NC}"
  TARGET_VERSION="latest"
else
  TARGET_VERSION="$1"
fi

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../tests/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}❌ Config file not found: ${CONFIG_FILE}${NC}"
  exit 1
fi

# Parse config
N8N_CONTAINER=$(grep "container_name:" "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"')
STARTUP_TIMEOUT=$(grep "container_startup_timeout_seconds:" "$CONFIG_FILE" | awk '{print $2}')

echo -e "${YELLOW}Target version: ${TARGET_VERSION}${NC}"
echo -e "${YELLOW}Container: ${N8N_CONTAINER}${NC}"
echo ""

# Step 1: Pull new image
echo -e "${YELLOW}Step 1: Pulling new Docker image${NC}"
NEW_IMAGE="n8nio/n8n:${TARGET_VERSION}"
docker pull "$NEW_IMAGE"
echo -e "${GREEN}✅ Image pulled: ${NEW_IMAGE}${NC}"
echo ""

# Step 2: Get current container configuration
echo -e "${YELLOW}Step 2: Saving container configuration${NC}"
CONTAINER_CONFIG=$(docker inspect "$N8N_CONTAINER")
NETWORK=$(echo "$CONTAINER_CONFIG" | grep -o '"NetworkMode": "[^"]*"' | cut -d'"' -f4 | head -1)
ENV_VARS=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$N8N_CONTAINER")
VOLUME_NAME=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/home/node/.n8n"}}{{.Name}}{{end}}{{end}}' "$N8N_CONTAINER" 2>/dev/null || echo "")

echo -e "${GREEN}✅ Configuration saved${NC}"
echo ""

# Step 3: Stop old container
echo -e "${YELLOW}Step 3: Stopping old container${NC}"
docker stop "$N8N_CONTAINER"
docker rm "$N8N_CONTAINER"
echo -e "${GREEN}✅ Old container removed${NC}"
echo ""

# Step 4: Start new container
echo -e "${YELLOW}Step 4: Starting new container${NC}"
docker run -d \
  --name "$N8N_CONTAINER" \
  --network "$NETWORK" \
  -p 5679:5678 \
  $(echo "$ENV_VARS" | sed 's/^/-e /') \
  $([ -n "$VOLUME_NAME" ] && echo "-v ${VOLUME_NAME}:/home/node/.n8n") \
  "$NEW_IMAGE"

echo -e "${GREEN}✅ New container started${NC}"
echo ""

# Step 5: Wait for health
echo -e "${YELLOW}Step 5: Waiting for n8n to be healthy${NC}"
ELAPSED=0

while [ $ELAPSED -lt $STARTUP_TIMEOUT ]; do
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ n8n is healthy${NC}"
    break
  fi
  
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "  Waiting... (${ELAPSED}s / ${STARTUP_TIMEOUT}s)"
done

if [ $ELAPSED -ge $STARTUP_TIMEOUT ]; then
  echo -e "${RED}❌ n8n failed to become healthy within ${STARTUP_TIMEOUT}s${NC}"
  echo "Container logs:"
  docker logs "$N8N_CONTAINER" --tail 30
  exit 1
fi
echo ""

# Step 6: Verify version
echo -e "${YELLOW}Step 6: Verifying version${NC}"
ACTUAL_VERSION=$(docker exec "$N8N_CONTAINER" n8n --version 2>/dev/null || echo "unknown")
echo "  Actual version: ${ACTUAL_VERSION}"
echo -e "${GREEN}✅ Update completed${NC}"
echo ""

# Summary
echo "================================"
echo -e "${GREEN}✅ n8n updated successfully${NC}"
echo ""
echo "Details:"
echo "  Container: ${N8N_CONTAINER}"
echo "  Image: ${NEW_IMAGE}"
echo "  Version: ${ACTUAL_VERSION}"
echo ""
echo "Verify the update:"
echo "  curl http://localhost:5679"
