#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🔄 Exporting workflows from n8n-dev...${NC}"

# Use environment variable or default
N8N_HOST="${N8N_DEV_HOST:-http://localhost:5678}"
N8N_API_KEY="${N8N_DEV_API_KEY}"

if [ -z "$N8N_API_KEY" ]; then
  echo -e "${RED}❌ N8N_DEV_API_KEY environment variable not set${NC}"
  echo "Set it with: export N8N_DEV_API_KEY='your-api-key'"
  exit 1
fi

mkdir -p ../workflows

WORKFLOWS=$(curl -s -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  "${N8N_HOST}/rest/workflows")

if [ $? -ne 0 ]; then
  echo -e "${RED}❌ Failed to connect to n8n-dev${NC}"
  exit 1
fi

WORKFLOW_COUNT=$(echo "$WORKFLOWS" | jq '.data | length')

if [ "$WORKFLOW_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}⚠️  No workflows found${NC}"
  exit 0
fi

echo -e "${GREEN}Found ${WORKFLOW_COUNT} workflows${NC}"

echo "$WORKFLOWS" | jq -c '.data[]' | while read -r workflow; do
  WORKFLOW_ID=$(echo "$workflow" | jq -r '.id')
  WORKFLOW_NAME=$(echo "$workflow" | jq -r '.name')
  SAFE_NAME=$(echo "$WORKFLOW_NAME" | sed 's/[^a-zA-Z0-9_-]/_/g')
  FILENAME="../workflows/${SAFE_NAME}.json"
  
  echo -e "  📄 Exporting: ${WORKFLOW_NAME}"
  
  curl -s -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_HOST}/rest/workflows/${WORKFLOW_ID}" | jq '.' > "$FILENAME"
  
  echo -e "  ${GREEN}✅ Saved to: ${FILENAME}${NC}"
done

echo -e "${GREEN}✅ Export complete!${NC}"