#!/bin/bash

set -e

# Load shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common-lib.sh"

echo -e "${BLUE}Rolling Back n8n${NC}"
echo "================================"

# Check for backup timestamp argument
if [ -z "$1" ]; then
  echo -e "${RED}Usage: $0 <backup_timestamp>${NC}"
  echo ""
  echo "Available backups:"
  ls -1 /tmp/n8n-backups/ 2>/dev/null || echo "  No backups found"
  exit 1
fi

BACKUP_TIMESTAMP="$1"

# Load configuration
load_script_config

BACKUP_PATH="${BACKUP_DIR}/${BACKUP_TIMESTAMP}"

# If specified backup doesn't exist, try to find the most recent one
if [ ! -d "$BACKUP_PATH" ]; then
  echo -e "${YELLOW}Specified backup not found: ${BACKUP_PATH}${NC}"
  echo -e "${YELLOW}   Looking for most recent backup...${NC}"

  LATEST_BACKUP=$(ls -t "$BACKUP_DIR" 2>/dev/null | grep -E '^[0-9]{8}_[0-9]{6}$' | head -1)

  if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_PATH="${BACKUP_DIR}/${LATEST_BACKUP}"
    BACKUP_TIMESTAMP="$LATEST_BACKUP"
    echo -e "${GREEN}Found backup: ${BACKUP_TIMESTAMP}${NC}"
  else
    echo -e "${RED}No backups found in ${BACKUP_DIR}${NC}"
    exit 1
  fi
fi

if [ ! -d "$BACKUP_PATH" ]; then
  echo -e "${RED}Backup not found: ${BACKUP_PATH}${NC}"
  exit 1
fi

# Load manifest using jq for reliable JSON parsing
MANIFEST_FILE="${BACKUP_PATH}/manifest.json"
if [ ! -f "$MANIFEST_FILE" ]; then
  echo -e "${RED}Manifest file not found${NC}"
  exit 1
fi

echo -e "${YELLOW}Loading backup manifest...${NC}"
N8N_CONTAINER=$(jq -r '.n8n_container' "$MANIFEST_FILE")
POSTGRES_CONTAINER=$(jq -r '.postgres_container' "$MANIFEST_FILE")
BACKUP_IMAGE_TAG=$(jq -r '.backup_image_tag' "$MANIFEST_FILE")
DB_NAME=$(jq -r '.db_name' "$MANIFEST_FILE")
DB_USER=$(jq -r '.db_user' "$MANIFEST_FILE")
VOLUME_NAME=$(jq -r '.volume_name // empty' "$MANIFEST_FILE")

# Validate DB_NAME to prevent SQL injection (allow only alphanumeric and underscores)
if ! [[ "$DB_NAME" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
  echo -e "${RED}Invalid database name in manifest: ${DB_NAME}${NC}"
  exit 1
fi

echo -e "${GREEN}Manifest loaded${NC}"
echo "  Backup date: $(jq -r '.date' "$MANIFEST_FILE")"
echo "  Image: ${BACKUP_IMAGE_TAG}"
echo ""

# Acquire lock to prevent concurrent rollbacks
acquire_lock "rollback"
trap 'release_lock "rollback"' EXIT

# Confirm rollback
if [ "${AUTO_CONFIRM:-false}" != "true" ]; then
  echo -e "${YELLOW}WARNING: This will restore n8n to the backup state${NC}"
  echo "   Current data will be replaced!"
  echo ""
  read -p "Continue with rollback? (yes/no): " CONFIRM

  if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Rollback cancelled${NC}"
    exit 0
  fi
else
  echo -e "${YELLOW}Auto-confirming rollback (CI/CD mode)${NC}"
fi
echo ""

# Step 1: Stop n8n container
echo -e "${YELLOW}Step 1: Stopping n8n container${NC}"
docker stop "$N8N_CONTAINER" || echo "Container already stopped"
echo -e "${GREEN}Container stopped${NC}"
echo ""

# Step 2: Restore database
echo -e "${YELLOW}Step 2: Restoring database${NC}"
DB_DUMP_FILE="${BACKUP_PATH}/database.sql.gz"

if [ ! -f "$DB_DUMP_FILE" ]; then
  echo -e "${RED}Database dump not found${NC}"
  exit 1
fi

# Drop and recreate database (using quoted identifier and --dbname for safety)
docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" --dbname postgres -c "DROP DATABASE IF EXISTS \"${DB_NAME}\";"
docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" --dbname postgres -c "CREATE DATABASE \"${DB_NAME}\";"

# Restore dump
gunzip -c "$DB_DUMP_FILE" | docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" "$DB_NAME"

echo -e "${GREEN}Database restored${NC}"
echo ""

# Step 3: Restore data volume (if exists)
if [ -n "$VOLUME_NAME" ] && [ "$VOLUME_NAME" != "null" ]; then
  echo -e "${YELLOW}Step 3: Restoring data volume${NC}"
  VOLUME_BACKUP="${BACKUP_PATH}/n8n-data.tar.gz"

  if [ -f "$VOLUME_BACKUP" ]; then
    docker run --rm -v "${VOLUME_NAME}:/data" -v "${BACKUP_PATH}:/backup" alpine sh -c "rm -rf /data/* && tar xzf /backup/n8n-data.tar.gz -C /data"

    # Remove config file to avoid encryption key conflicts
    echo -e "${YELLOW}   Removing config file to avoid encryption key mismatch...${NC}"
    docker run --rm -v "${VOLUME_NAME}:/data" alpine sh -c "rm -f /data/config" || true

    echo -e "${GREEN}Volume restored${NC}"
  else
    echo -e "${YELLOW}Volume backup not found, skipping${NC}"
  fi
else
  echo -e "${YELLOW}Step 3: No volume to restore${NC}"
fi
echo ""

# Step 4: Start container with backup image
echo -e "${YELLOW}Step 4: Starting container with backup image${NC}"

# Detect network dynamically instead of hardcoding
NETWORK=$(docker network ls --format '{{.Name}}' | grep -E 'n8n-test-network' | head -1)
if [ -z "$NETWORK" ]; then
  NETWORK="docker_n8n-test-network"
fi

# Remove old container
docker rm "$N8N_CONTAINER" || true

# Get standard Docker env args from shared library
local_env_args=()
get_docker_env_args local_env_args

if [ -n "$VOLUME_NAME" ] && [ "$VOLUME_NAME" != "null" ]; then
  docker run -d \
    --name "$N8N_CONTAINER" \
    --network "$NETWORK" \
    -p 5679:5678 \
    "${local_env_args[@]}" \
    -v "${VOLUME_NAME}:/home/node/.n8n" \
    "$BACKUP_IMAGE_TAG"
else
  docker run -d \
    --name "$N8N_CONTAINER" \
    --network "$NETWORK" \
    -p 5679:5678 \
    "${local_env_args[@]}" \
    "$BACKUP_IMAGE_TAG"
fi

echo -e "${GREEN}Container started${NC}"
echo ""

# Step 5: Wait for health using /healthz endpoint
echo -e "${YELLOW}Step 5: Waiting for n8n to be healthy${NC}"
TIMEOUT="${STARTUP_TIMEOUT:-120}"
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678/healthz > /dev/null 2>&1; then
    echo -e "${GREEN}n8n is healthy${NC}"
    break
  fi

  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "  Waiting... (${ELAPSED}s / ${TIMEOUT}s)"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo -e "${RED}n8n failed to become healthy${NC}"
  echo "Container logs:"
  docker logs "$N8N_CONTAINER" --tail 20
  exit 1
fi
echo ""

# Summary
echo "================================"
echo -e "${GREEN}Rollback completed successfully${NC}"
echo ""
echo "n8n has been restored to backup: ${BACKUP_TIMESTAMP}"
echo "Container: ${N8N_CONTAINER}"
echo "Image: ${BACKUP_IMAGE_TAG}"
echo ""
echo "Verify the rollback:"
echo "  curl http://localhost:5679"
