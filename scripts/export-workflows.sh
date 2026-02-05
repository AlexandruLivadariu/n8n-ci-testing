#!/bin/bash

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔄 Exporting workflows from n8n-dev...${NC}"

# Configuration
N8N_HOST="http://localhost:5678"
N8N_USER="admin"
N8N_PASSWORD="admin123"

# Create workflows directory if doesn't exist
mkdir -p ../workflows

# Get all workflows using n8n API
WORKFLOWS=$(curl -s -u "${N8N_USER}:${N8N_PASSWORD}" \
  "${N8N_HOST}/api/v1/workflows")

# Check if request was successful
if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Failed to connect to n8n-dev${NC}"
  echo "Make sure n8n-dev is running on port 5678"
  exit 1
fi

# Count workflows
WORKFLOW_COUNT=$(echo "$WORKFLOWS" | jq '.data | length')

if [ "$WORKFLOW_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}⚠️  No workflows found in n8n-dev${NC}"
  exit 0
fi

echo -e "${GREEN}Found ${WORKFLOW_COUNT} workflows${NC}"

# Export each workflow
echo "$WORKFLOWS" | jq -c '.data[]' | while read -r workflow; do
  WORKFLOW_ID=$(echo "$workflow" | jq -r '.id')
  WORKFLOW_NAME=$(echo "$workflow" | jq -r '.name')
  
  # Sanitize filename (remove special characters)
  SAFE_NAME=$(echo "$WORKFLOW_NAME" | sed 's/[^a-zA-Z0-9_-]/_/g')
  FILENAME="../workflows/${SAFE_NAME}.json"
  
  echo -e "  📄 Exporting: ${WORKFLOW_NAME}"
  
  # Get full workflow details
  curl -s -u "${N8N_USER}:${N8N_PASSWORD}" \
    "${N8N_HOST}/api/v1/workflows/${WORKFLOW_ID}" | jq '.' > "$FILENAME"
  
  if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✅ Saved to: ${FILENAME}${NC}"
  else
    echo -e "  ${RED}❌ Failed to export${NC}"
  fi
done

echo -e "${GREEN}✅ Export complete!${NC}"
echo ""
echo "Exported workflows are in: ./workflows/"
ls -lh ../workflows/