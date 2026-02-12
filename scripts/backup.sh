#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}📦 Creating n8n Backup${NC}"
echo "================================"

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../tests/config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo -e "${RED}❌ Config file not found: ${CONFIG_FILE}${NC}"
  exit 1
fi

# Parse config (simple grep-based parsing for bash)
N8N_CONTAINER=$(grep "container_name:" "$CONFIG_FILE" | head -1 | awk '{print $2}' | tr -d '"' | tr -d '\r' | tr -d '\n')
POSTGRES_CONTAINER=$(grep "container_name:" "$CONFIG_FILE" | tail -1 | awk '{print $2}' | tr -d '"' | tr -d '\r' | tr -d '\n')
DB_NAME=$(grep "db_name:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"' | tr -d '\r' | tr -d '\n')
DB_USER=$(grep "db_user:" "$CONFIG_FILE" | awk '{print $2}' | tr -d '"' | tr -d '\r' | tr -d '\n')
BACKUP_DIR=$(grep "^backup:" -A 3 "$CONFIG_FILE" | grep "directory:" | awk '{print $2}' | tr -d '"' | tr -d '\r' | tr -d '\n')

# Create backup directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
mkdir -p "$BACKUP_PATH"

echo -e "${YELLOW}Backup location: ${BACKUP_PATH}${NC}"
echo ""

# Step 1: Tag current Docker image
echo -e "${YELLOW}Step 1: Tagging Docker image${NC}"
CURRENT_IMAGE=$(docker inspect --format='{{.Config.Image}}' "$N8N_CONTAINER" 2>/dev/null || echo "")
if [ -z "$CURRENT_IMAGE" ]; then
  echo -e "${RED}❌ Failed to get current image${NC}"
  exit 1
fi

BACKUP_IMAGE_TAG="${CURRENT_IMAGE}-backup-${TIMESTAMP}"
docker tag "$CURRENT_IMAGE" "$BACKUP_IMAGE_TAG"
echo -e "${GREEN}✅ Tagged image: ${BACKUP_IMAGE_TAG}${NC}"
echo ""

# Step 2: Dump PostgreSQL database
echo -e "${YELLOW}Step 2: Dumping PostgreSQL database${NC}"
DB_DUMP_FILE="${BACKUP_PATH}/database.sql.gz"
docker exec "$POSTGRES_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$DB_DUMP_FILE"

if [ -f "$DB_DUMP_FILE" ] && [ -s "$DB_DUMP_FILE" ]; then
  DB_SIZE=$(du -h "$DB_DUMP_FILE" | cut -f1)
  echo -e "${GREEN}✅ Database dumped: ${DB_SIZE}${NC}"
else
  echo -e "${RED}❌ Database dump failed${NC}"
  exit 1
fi
echo ""

# Step 3: Backup n8n data volume (if exists)
echo -e "${YELLOW}Step 3: Backing up n8n data volume${NC}"
VOLUME_NAME=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "/home/node/.n8n"}}{{.Name}}{{end}}{{end}}' "$N8N_CONTAINER" 2>/dev/null || echo "")

if [ -n "$VOLUME_NAME" ]; then
  VOLUME_BACKUP="${BACKUP_PATH}/n8n-data.tar.gz"
  docker run --rm -v "${VOLUME_NAME}:/data" -v "${BACKUP_PATH}:/backup" alpine tar czf "/backup/n8n-data.tar.gz" -C /data .
  
  if [ -f "$VOLUME_BACKUP" ] && [ -s "$VOLUME_BACKUP" ]; then
    VOLUME_SIZE=$(du -h "$VOLUME_BACKUP" | cut -f1)
    echo -e "${GREEN}✅ Volume backed up: ${VOLUME_SIZE}${NC}"
  else
    echo -e "${YELLOW}⚠️  Volume backup created but may be empty${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  No named volume found, skipping volume backup${NC}"
fi
echo ""

# Step 4: Create manifest file
echo -e "${YELLOW}Step 4: Creating backup manifest${NC}"
MANIFEST_FILE="${BACKUP_PATH}/manifest.json"

cat > "$MANIFEST_FILE" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "n8n_container": "${N8N_CONTAINER}",
  "postgres_container": "${POSTGRES_CONTAINER}",
  "original_image": "${CURRENT_IMAGE}",
  "backup_image_tag": "${BACKUP_IMAGE_TAG}",
  "database_dump": "database.sql.gz",
  "volume_backup": "$([ -n "$VOLUME_NAME" ] && echo "n8n-data.tar.gz" || echo "none")",
  "volume_name": "${VOLUME_NAME}",
  "db_name": "${DB_NAME}",
  "db_user": "${DB_USER}"
}
EOF

echo -e "${GREEN}✅ Manifest created${NC}"
echo ""

# Step 5: Verify backup
echo -e "${YELLOW}Step 5: Verifying backup${NC}"
ERRORS=0

if [ ! -f "$DB_DUMP_FILE" ] || [ ! -s "$DB_DUMP_FILE" ]; then
  echo -e "${RED}❌ Database dump missing or empty${NC}"
  ((ERRORS++))
fi

if [ ! -f "$MANIFEST_FILE" ]; then
  echo -e "${RED}❌ Manifest file missing${NC}"
  ((ERRORS++))
fi

if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}✅ Backup verification passed${NC}"
else
  echo -e "${RED}❌ Backup verification failed with ${ERRORS} error(s)${NC}"
  exit 1
fi
echo ""

# Summary
echo "================================"
echo -e "${GREEN}✅ Backup completed successfully${NC}"
echo ""
echo "Backup details:"
echo "  Location: ${BACKUP_PATH}"
echo "  Image tag: ${BACKUP_IMAGE_TAG}"
echo "  Database: ${DB_DUMP_FILE}"
if [ -n "$VOLUME_NAME" ]; then
  echo "  Volume: ${VOLUME_BACKUP}"
fi
echo ""
echo "To restore this backup, run:"
echo "  ./rollback.sh ${TIMESTAMP}"
