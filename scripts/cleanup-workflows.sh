#!/bin/bash
# Clean up all test workflows from n8n

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

N8N_HOST="${N8N_HOST:-http://localhost:5679}"
N8N_API_KEY="${N8N_TEST_API_KEY}"

echo -e "${BLUE}🧹 Cleaning up test workflows${NC}"
echo "================================"

if [ -z "$N8N_API_KEY" ]; then
  echo -e "${RED}❌ N8N_TEST_API_KEY not set${NC}"
  exit 1
fi

# Get all workflows
WORKFLOWS=$(curl -s \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  -H "accept: application/json" \
  "${N8N_HOST}/api/v1/workflows" 2>/dev/null)

# Find and delete workflows starting with "Test:"
echo "$WORKFLOWS" | jq -r '.data[] | select(.name | startswith("Test:")) | .id' | while read -r WORKFLOW_ID; do
  WORKFLOW_NAME=$(echo "$WORKFLOWS" | jq -r ".data[] | select(.id == \"$WORKFLOW_ID\") | .name")
  echo -e "${YELLOW}Deleting: ${WORKFLOW_NAME} (${WORKFLOW_ID})${NC}"
  
  DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X DELETE \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_HOST}/api/v1/workflows/${WORKFLOW_ID}" 2>/dev/null || echo -e "\n000")
  
  HTTP_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)
  
  if [ "$HTTP_CODE" == "200" ]; then
    echo -e "${GREEN}   ✅ Deleted${NC}"
  else
    echo -e "${RED}   ❌ Failed (HTTP ${HTTP_CODE})${NC}"
  fi
done

echo ""
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo ""
echo "Now run: ./import-test-workflows.sh"
