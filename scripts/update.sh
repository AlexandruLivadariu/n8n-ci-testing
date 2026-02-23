#!/bin/bash

set -e

# Load shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common-lib.sh"

echo -e "${BLUE}Updating n8n${NC}"
echo "================================"

# Check for target version argument
if [ -z "$1" ]; then
  echo -e "${YELLOW}No target version specified, using 'latest'${NC}"
  TARGET_VERSION="latest"
else
  TARGET_VERSION="$1"
fi

# Load configuration
load_script_config
warn_default_secrets

# Acquire lock to prevent concurrent updates
acquire_lock "update"
trap 'release_lock "update"' EXIT

echo -e "${YELLOW}Target version: ${TARGET_VERSION}${NC}"
echo -e "${YELLOW}Container: ${N8N_CONTAINER}${NC}"
echo ""

# Step 1: Pull new image
echo -e "${YELLOW}Step 1: Pulling new Docker image${NC}"
NEW_IMAGE="n8nio/n8n:${TARGET_VERSION}"
docker pull "$NEW_IMAGE"
echo -e "${GREEN}Image pulled: ${NEW_IMAGE}${NC}"
echo ""

# Step 2: Get current container configuration
echo -e "${YELLOW}Step 2: Saving container configuration${NC}"
NETWORK=$(docker inspect --format='{{.HostConfig.NetworkMode}}' "$N8N_CONTAINER")
VOLUME_NAME=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/home/node/.n8n"}}{{.Name}}{{end}}{{end}}' "$N8N_CONTAINER" 2>/dev/null || echo "")

echo -e "${GREEN}Configuration saved${NC}"
echo ""

# Step 3: Stop old container
echo -e "${YELLOW}Step 3: Stopping old container${NC}"
docker stop "$N8N_CONTAINER"
docker rm "$N8N_CONTAINER"
echo -e "${GREEN}Old container removed${NC}"
echo ""

# Step 4: Start new container
echo -e "${YELLOW}Step 4: Starting new container${NC}"

echo "Network: $NETWORK"
echo "Volume: $VOLUME_NAME"
echo "Image: $NEW_IMAGE"

# Remove config file from volume to avoid encryption key conflicts
if [ -n "$VOLUME_NAME" ]; then
  echo -e "${YELLOW}Removing old config file to avoid encryption key mismatch...${NC}"
  docker run --rm -v "${VOLUME_NAME}:/data" alpine sh -c "rm -f /data/config" || true
fi

# Get standard Docker env args from shared library
local_env_args=()
get_docker_env_args local_env_args

if [ -n "$VOLUME_NAME" ]; then
  docker run -d \
    --name "$N8N_CONTAINER" \
    --network "$NETWORK" \
    -p 5679:5678 \
    "${local_env_args[@]}" \
    -v "${VOLUME_NAME}:/home/node/.n8n" \
    "$NEW_IMAGE"
else
  docker run -d \
    --name "$N8N_CONTAINER" \
    --network "$NETWORK" \
    -p 5679:5678 \
    "${local_env_args[@]}" \
    "$NEW_IMAGE"
fi

echo -e "${GREEN}New container started${NC}"
echo ""

# Step 5: Wait for health using /healthz endpoint
echo -e "${YELLOW}Step 5: Waiting for n8n to be healthy${NC}"
ELAPSED=0

while [ $ELAPSED -lt $STARTUP_TIMEOUT ]; do
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678/healthz > /dev/null 2>&1; then
    echo -e "${GREEN}n8n is healthy${NC}"
    break
  fi

  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "  Waiting... (${ELAPSED}s / ${STARTUP_TIMEOUT}s)"
done

if [ $ELAPSED -ge $STARTUP_TIMEOUT ]; then
  echo -e "${RED}n8n failed to become healthy within ${STARTUP_TIMEOUT}s${NC}"
  echo "Container logs:"
  docker logs "$N8N_CONTAINER" --tail 30
  exit 1
fi
echo ""

# Step 6: Verify version
echo -e "${YELLOW}Step 6: Verifying version${NC}"
ACTUAL_VERSION=$(docker exec "$N8N_CONTAINER" n8n --version 2>/dev/null || echo "unknown")
echo "  Actual version: ${ACTUAL_VERSION}"
echo -e "${GREEN}Update completed${NC}"
echo ""

# Summary
echo "================================"
echo -e "${GREEN}n8n updated successfully${NC}"
echo ""
echo "Details:"
echo "  Container: ${N8N_CONTAINER}"
echo "  Image: ${NEW_IMAGE}"
echo "  Version: ${ACTUAL_VERSION}"
echo ""
echo "Verify the update:"
echo "  curl http://localhost:5679"
