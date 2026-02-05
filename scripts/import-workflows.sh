#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <dev|test>"
  exit 1
fi

ENVIRONMENT=$1

if [ "$ENVIRONMENT" == "dev" ]; then
  N8N_HOST="${N8N_DEV_HOST:-http://localhost:5678}"
  N8N_API_KEY="${N8N_DEV_API_KEY}"
  echo -e "${YELLOW}📥 Importing workflows to n8n-dev...${NC}"
elif [ "$ENVIRONMENT" == "test" ]; then
  N8N_HOST="${N8N_TEST_HOST:-http://localhost:5679}"
  N8N_API_KEY="${N8N_TEST_API_KEY}"
  echo -e "${YELLOW}📥 Importing workflows to n8n-test...${NC}"
else
  echo -e "${RED}Invalid environment. Use 'dev' or 'test'${NC}"
  exit 1
fi

if [ -z "$N8N_API_KEY" ]; then
  echo -e "${RED}❌ API key environment variable not set${NC}"
  echo "For dev: export N8N_DEV_API_KEY='your-api-key'"
  echo "For test: export N8N_TEST_API_KEY='your-api-key'"
  exit 1
fi

if ! curl -s -f -H "X-N8N-API-KEY: ${N8N_API_KEY}" "${N8N_HOST}/rest/workflows" > /dev/null; then
  echo -e "${RED}❌ Cannot connect to n8n at ${N8N_HOST}${NC}"
  exit 1
fi

WORKFLOW_COUNT=$(find ../workflows -name "*.json" | wc -l)

if [ "$WORKFLOW_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}⚠️  No workflow files found${NC}"
  exit 0
fi

echo -e "${GREEN}Found ${WORKFLOW_COUNT} workflow files${NC}"

SUCCESS=0
FAILED=0

for file in ../workflows/*.json; do
  if [ ! -f "$file" ]; then
    continue
  fi
  
  FILENAME=$(basename "$file")
  echo -e "  📄 Importing: ${FILENAME}"
  
  WORKFLOW_DATA=$(cat "$file" | jq 'del(.id)')
  
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$WORKFLOW_DATA" \
    "${N8N_HOST}/rest/workflows")
  
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
