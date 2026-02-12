#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}⏮️  Rolling Back n8n${NC}"
echo "================================"

# Check for backup timestamp argument
if [ -z "$1" ]; then
  echo -e "${RED}❌ Usage: $0 <backup_timestamp>${NC}"
  echo ""
  echo "Available backups:"
  ls -1 /tmp/n8n-backups/ 2>/dev/null || echo "  No backups found"
  exit 1
fi

BACKUP_TIMESTAMP="$1"

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../tests/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}❌ Config file not found: ${CONFIG_FILE}${NC}"
  exit 1
fi

# Parse config
BACKUP_DIR=$(grep "^backup:" -A 3 "$CONFIG_FILE" | grep "directory:" | awk '{print $2}' | tr -d '"' | tr -d '\r' | tr -d '\n')
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_TIMESTAMP}"

# If specified backup doesn't exist, try to find the most recent one
if [ ! -d "$BACKUP_PATH" ]; then
  echo -e "${YELLOW}⚠️  Specified backup not found: ${BACKUP_PATH}${NC}"
  echo -e "${YELLOW}   Looking for most recent backup...${NC}"
  
  LATEST_BACKUP=$(ls -t "$BACKUP_DIR" 2>/dev/null | grep -E '^[0-9]{8}_[0-9]{6}$' | head -1)
  
  if [ -n "$LATEST_BACKUP" ]; then
    BACKUP_PATH="${BACKUP_DIR}/${LATEST_BACKUP}"
    BACKUP_TIMESTAMP="$LATEST_BACKUP"
    echo -e "${GREEN}✅ Found backup: ${BACKUP_TIMESTAMP}${NC}"
  else
    echo -e "${RED}❌ No backups found in ${BACKUP_DIR}${NC}"
    exit 1
  fi
fi

if [ ! -d "$BACKUP_PATH" ]; then
  echo -e "${RED}❌ Backup not found: ${BACKUP_PATH}${NC}"
  exit 1
fi

# Load manifest
MANIFEST_FILE="${BACKUP_PATH}/manifest.json"
if [ ! -f "$MANIFEST_FILE" ]; then
  echo -e "${RED}❌ Manifest file not found${NC}"
  exit 1
fi

echo -e "${YELLOW}Loading backup manifest...${NC}"
N8N_CONTAINER=$(grep -o '"n8n_container": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4)
POSTGRES_CONTAINER=$(grep -o '"postgres_container": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4)
BACKUP_IMAGE_TAG=$(grep -o '"backup_image_tag": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4)
DB_NAME=$(grep -o '"db_name": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4)
DB_USER=$(grep -o '"db_user": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4)
VOLUME_NAME=$(grep -o '"volume_name": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4)

echo -e "${GREEN}✅ Manifest loaded${NC}"
echo "  Backup date: $(grep -o '"date": "[^"]*"' "$MANIFEST_FILE" | cut -d'"' -f4)"
echo "  Image: ${BACKUP_IMAGE_TAG}"
echo ""

# Confirm rollback
echo -e "${YELLOW}⚠️  WARNING: This will restore n8n to the backup state${NC}"
echo "   Current data will be replaced!"
echo ""
read -p "Continue with rollback? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo -e "${YELLOW}Rollback cancelled${NC}"
  exit 0
fi
echo ""

# Step 1: Stop n8n container
echo -e "${YELLOW}Step 1: Stopping n8n container${NC}"
docker stop "$N8N_CONTAINER" || echo "Container already stopped"
echo -e "${GREEN}✅ Container stopped${NC}"
echo ""

# Step 2: Restore database
echo -e "${YELLOW}Step 2: Restoring database${NC}"
DB_DUMP_FILE="${BACKUP_PATH}/database.sql.gz"

if [ ! -f "$DB_DUMP_FILE" ]; then
  echo -e "${RED}❌ Database dump not found${NC}"
  exit 1
fi

# Drop and recreate database
docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -c "DROP DATABASE IF EXISTS ${DB_NAME};" postgres
docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -c "CREATE DATABASE ${DB_NAME};" postgres

# Restore dump
gunzip -c "$DB_DUMP_FILE" | docker exec -i "$POSTGRES_CONTAINER" psql -U "$DB_USER" "$DB_NAME"

echo -e "${GREEN}✅ Database restored${NC}"
echo ""

# Step 3: Restore data volume (if exists)
if [ -n "$VOLUME_NAME" ] && [ "$VOLUME_NAME" != "null" ]; then
  echo -e "${YELLOW}Step 3: Restoring data volume${NC}"
  VOLUME_BACKUP="${BACKUP_PATH}/n8n-data.tar.gz"
  
  if [ -f "$VOLUME_BACKUP" ]; then
    docker run --rm -v "${VOLUME_NAME}:/data" -v "${BACKUP_PATH}:/backup" alpine sh -c "rm -rf /data/* && tar xzf /backup/n8n-data.tar.gz -C /data"
    echo -e "${GREEN}✅ Volume restored${NC}"
  else
    echo -e "${YELLOW}⚠️  Volume backup not found, skipping${NC}"
  fi
else
  echo -e "${YELLOW}Step 3: No volume to restore${NC}"
fi
echo ""

# Step 4: Start container with backup image
echo -e "${YELLOW}Step 4: Starting container with backup image${NC}"

# Get current container configuration
CONTAINER_CONFIG=$(docker inspect "$N8N_CONTAINER")
NETWORK=$(echo "$CONTAINER_CONFIG" | grep -o '"NetworkMode": "[^"]*"' | cut -d'"' -f4 | head -1)
ENV_VARS=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$N8N_CONTAINER")

# Remove old container
docker rm "$N8N_CONTAINER" || true

# Start new container with backup image
docker run -d \
  --name "$N8N_CONTAINER" \
  --network "$NETWORK" \
  -p 5679:5678 \
  $(echo "$ENV_VARS" | sed 's/^/-e /') \
  $([ -n "$VOLUME_NAME" ] && echo "-v ${VOLUME_NAME}:/home/node/.n8n") \
  "$BACKUP_IMAGE_TAG"

echo -e "${GREEN}✅ Container started${NC}"
echo ""

# Step 5: Wait for health
echo -e "${YELLOW}Step 5: Waiting for n8n to be healthy${NC}"
TIMEOUT=120
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ n8n is healthy${NC}"
    break
  fi
  
  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo "  Waiting... (${ELAPSED}s / ${TIMEOUT}s)"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo -e "${RED}❌ n8n failed to become healthy${NC}"
  echo "Container logs:"
  docker logs "$N8N_CONTAINER" --tail 20
  exit 1
fi
echo ""

# Summary
echo "================================"
echo -e "${GREEN}✅ Rollback completed successfully${NC}"
echo ""
echo "n8n has been restored to backup: ${BACKUP_TIMESTAMP}"
echo "Container: ${N8N_CONTAINER}"
echo "Image: ${BACKUP_IMAGE_TAG}"
echo ""
echo "Verify the rollback:"
echo "  curl http://localhost:5679"
