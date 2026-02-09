#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Bypass corporate proxy for localhost
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

echo -e "${BLUE}📥 Importing Test Workflows to n8n${NC}"
echo "================================"

N8N_HOST="${N8N_HOST:-http://localhost:5679}"
N8N_API_KEY="${N8N_TEST_API_KEY}"

if [ -z "$N8N_API_KEY" ]; then
  echo -e "${YELLOW}⚠️  N8N_TEST_API_KEY not set - attempting without API key${NC}"
  echo "   This may fail if n8n requires authentication"
  echo ""
fi

WORKFLOW_DIR="../workflows"

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
  
  # Try to import via API if key is available
  if [ -n "$N8N_API_KEY" ]; then
    RESPONSE=$(curl -s -w "\n%{http_code}" \
      -X POST \
      -H "Content-Type: application/json" \
      -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
      -d @"$workflow_file" \
      "${N8N_HOST}/rest/workflows" 2>/dev/null || echo -e "\n000")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "201" ]; then
      echo -e "${GREEN}✅ Imported successfully${NC}"
      ((IMPORTED++))
    else
      echo -e "${RED}❌ Failed (HTTP ${HTTP_CODE})${NC}"
      echo "   Response: $(echo "$RESPONSE" | head -n1 | cut -c1-100)"
      ((FAILED++))
    fi
  else
    echo -e "${YELLOW}⚠️  Skipped (no API key)${NC}"
    echo "   Please import manually via n8n UI"
  fi
  echo ""
done

echo "================================"
echo -e "${BLUE}Import Summary${NC}"
echo "  Imported: ${IMPORTED}"
echo "  Failed:   ${FAILED}"
echo ""

if [ $IMPORTED -gt 0 ]; then
  echo -e "${GREEN}✅ Successfully imported ${IMPORTED} workflow(s)${NC}"
  echo ""
  echo "Next steps:"
  echo "1. Go to ${N8N_HOST}"
  echo "2. Verify workflows are active"
  echo "3. Test webhooks manually:"
  echo "   curl ${N8N_HOST}/webhook-test/test/health"
  echo "   curl -X POST -H 'Content-Type: application/json' -d '{\"input\":\"test\"}' ${N8N_HOST}/webhook-test/test/echo"
  exit 0
else
  echo -e "${YELLOW}⚠️  No workflows imported${NC}"
  echo ""
  echo "Manual import instructions:"
  echo "1. Go to ${N8N_HOST}"
  echo "2. Click 'Add workflow' → 'Import from file'"
  echo "3. Import each file from: ${WORKFLOW_DIR}"
  echo "4. Activate each workflow"
  exit 1
fi
