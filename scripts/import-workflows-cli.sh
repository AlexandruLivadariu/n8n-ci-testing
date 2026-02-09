#!/bin/bash

# Import workflows using n8n CLI (works without API keys)
# This is the recommended approach for CI/CD automation

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}📥 Importing Workflows via n8n CLI${NC}"
echo "================================"
echo ""

WORKFLOW_DIR="../workflows"
CONTAINER_NAME="${N8N_CONTAINER:-n8n-test}"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo -e "${RED}❌ Container ${CONTAINER_NAME} is not running${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Container ${CONTAINER_NAME} is running${NC}"
echo ""

if [ ! -d "$WORKFLOW_DIR" ]; then
  echo -e "${RED}❌ Workflow directory not found: $WORKFLOW_DIR${NC}"
  exit 1
fi

IMPORTED=0
FAILED=0

for workflow_file in "$WORKFLOW_DIR"/test-*.json; do
  if [ ! -f "$workflow_file" ]; then
    continue
  fi
  
  WORKFLOW_NAME=$(basename "$workflow_file" .json)
  echo -e "${YELLOW}Importing: ${WORKFLOW_NAME}${NC}"
  
  # Copy workflow file into container
  docker cp "$workflow_file" "${CONTAINER_NAME}:/tmp/${WORKFLOW_NAME}.json"
  
  # Import using n8n CLI
  if docker exec "${CONTAINER_NAME}" n8n import:workflow --input="/tmp/${WORKFLOW_NAME}.json" 2>&1 | grep -q "Successfully imported"; then
    echo -e "${GREEN}   ✅ Imported successfully${NC}"
    
    # Activate the workflow
    # Note: n8n CLI doesn't have a direct activate command, workflows need to be activated via API or UI
    echo -e "${YELLOW}   ⚠️  Workflow imported but needs manual activation${NC}"
    
    ((IMPORTED++))
  else
    echo -e "${RED}   ❌ Import failed${NC}"
    ((FAILED++))
  fi
  
  # Clean up temp file
  docker exec "${CONTAINER_NAME}" rm -f "/tmp/${WORKFLOW_NAME}.json"
  echo ""
done

echo "================================"
echo -e "${BLUE}Import Summary${NC}"
echo "  Imported: ${IMPORTED}"
echo "  Failed:   ${FAILED}"
echo ""

if [ $IMPORTED -gt 0 ]; then
  echo -e "${GREEN}✅ Successfully imported ${IMPORTED} workflow(s)${NC}"
  echo -e "${YELLOW}⚠️  Note: Workflows need to be activated manually or via API${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  No workflows imported${NC}"
  exit 1
fi
