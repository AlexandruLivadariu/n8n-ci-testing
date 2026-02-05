#!/bin/bash

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check arguments
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <dev|test>"
  exit 1
fi

ENVIRONMENT=$1

# Set configuration based on environment
if [ "$ENVIRONMENT" == "dev" ]; then
  N8N_HOST="http://localhost:5678"
  echo -e "${YELLOW}📥 Importing workflows to n8n-dev...${NC}"
elif [ "$ENVIRONMENT" == "test" ]; then
  N8N_HOST="http://localhost:5679"
  echo -e "${YELLOW}📥 Importing workflows to n8n-test...${NC}"
else
  echo -e "${RED}Invalid environment. Use 'dev' or 'test'${NC}"
  exit 1
fi

N8N_USER="admin"
N8N_PASSWORD="admin123"

# Check if n8n is accessible
if ! curl -s -f -u "${N8N_USER}:${N8N_PASSWORD}" "${N8N_HOST}/api/v1/workflows" > /dev/null; then
  echo -e "${RED}❌ Cannot connect to n8n at ${N8N_HOST}${NC}"
  echo "Make sure n8n-${ENVIRONMENT} is running"
  exit 1
fi

# Count workflow files
WORKFLOW_COUNT=$(find ../workflows -name "*.json" | wc -l)

if [ "$WORKFLOW_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}⚠️  No workflow files found in ./workflows/${NC}"
  exit 0
fi

echo -e "${GREEN}Found ${WORKFLOW_COUNT} workflow files${NC}"

# Import each workflow
SUCCESS=0
FAILED=0

for file in ../workflows/*.json; do
  if [ ! -f "$file" ]; then
    continue
  fi
  
  FILENAME=$(basename "$file")
  echo -e "  📄 Importing: ${FILENAME}"
  
  # Read workflow JSON
  WORKFLOW_DATA=$(cat "$file")
  
  # Remove ID field (n8n will assign new one)
  WORKFLOW_DATA=$(echo "$WORKFLOW_DATA" | jq 'del(.id)')
  
  # Import workflow
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -u "${N8N_USER}:${N8N_PASSWORD}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$WORKFLOW_DATA" \
    "${N8N_HOST}/api/v1/workflows")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  
  if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "201" ]; then
    echo -e "  ${GREEN}✅ Imported successfully${NC}"
    ((SUCCESS++))
  else
    echo -e "  ${RED}❌ Failed (HTTP ${HTTP_CODE})${NC}"
    ((FAILED++))
  fi
done

echo ""
echo -e "${GREEN}✅ Import complete!${NC}"
echo "  Success: ${SUCCESS}"
echo "  Failed: ${FAILED}"