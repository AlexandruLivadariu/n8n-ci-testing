#!/bin/bash

# Don't exit on error - we want to import all workflows even if activation fails
set +e

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

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo -e "${RED}❌ 'jq' is not installed${NC}"
  echo ""
  echo "jq is required to process workflow JSON files."
  echo "Install it with:"
  echo "  Ubuntu/Debian: sudo apt-get install jq"
  echo "  macOS: brew install jq"
  echo "  Windows (WSL): sudo apt-get install jq"
  echo ""
  exit 1
fi

N8N_HOST="${N8N_HOST:-http://localhost:5679}"
N8N_API_KEY="${N8N_TEST_API_KEY}"

if [ -z "$N8N_API_KEY" ]; then
  echo -e "${YELLOW}⚠️  N8N_TEST_API_KEY not set${NC}"
  echo ""
  echo "To get an API key:"
  echo "  1. Go to ${N8N_HOST}"
  echo "  2. Settings → n8n API"
  echo "  3. Create an API key"
  echo "  4. Copy the key (JWT format starting with 'eyJ...')"
  echo "  5. Export it: export N8N_TEST_API_KEY='eyJ...'"
  echo ""
  echo "For now, please import workflows manually:"
  echo "  1. Go to ${N8N_HOST}"
  echo "  2. Click 'Add workflow' → 'Import from file'"
  echo "  3. Import each file from: ../workflows/"
  exit 1
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
  
  # Remove read-only fields from workflow JSON before import
  # Fields like 'active', 'id', 'tags', 'createdAt', 'updatedAt' cannot be set during import
  WORKFLOW_DATA=$(cat "$workflow_file" | jq 'del(.active, .id, .tags, .createdAt, .updatedAt, .versionId)')
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to parse workflow JSON${NC}"
    echo "   Make sure 'jq' is installed: sudo apt-get install jq"
    ((FAILED++))
    echo ""
    continue
  fi
  
  # Import via n8n API (v1)
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    -H "accept: application/json" \
    -d "$WORKFLOW_DATA" \
    "${N8N_HOST}/api/v1/workflows" 2>/dev/null || echo -e "\n000")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  RESPONSE_BODY=$(echo "$RESPONSE" | head -n -1)
  
  if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "201" ]; then
    echo -e "${GREEN}✅ Imported successfully${NC}"
    
    # Extract workflow ID from response to activate it
    WORKFLOW_ID=$(echo "$RESPONSE_BODY" | jq -r '.id' 2>/dev/null)
    
    if [ -n "$WORKFLOW_ID" ] && [ "$WORKFLOW_ID" != "null" ]; then
      # Activate the workflow using the correct endpoint
      # POST /api/v1/workflows/{id}/activate automatically registers webhooks
      ACTIVATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
        -H "accept: application/json" \
        "${N8N_HOST}/api/v1/workflows/${WORKFLOW_ID}/activate" 2>/dev/null || echo -e "\n000")
      
      ACTIVATE_CODE=$(echo "$ACTIVATE_RESPONSE" | tail -n1)
      
      if [ "$ACTIVATE_CODE" == "200" ]; then
        echo -e "${GREEN}   ✅ Activated and webhooks registered${NC}"
      else
        echo -e "${YELLOW}   ⚠️  Could not activate (HTTP ${ACTIVATE_CODE})${NC}"
        ACTIVATE_BODY=$(echo "$ACTIVATE_RESPONSE" | head -n -1 | cut -c1-100)
        if [ -n "$ACTIVATE_BODY" ]; then
          echo "   Response: ${ACTIVATE_BODY}"
        fi
        echo "   Please activate manually: ${N8N_HOST} → Workflows → Toggle 'Active'"
      fi
    fi
    
    ((IMPORTED++))
  else
    echo -e "${RED}❌ Failed (HTTP ${HTTP_CODE})${NC}"
    ERROR_MSG=$(echo "$RESPONSE_BODY" | cut -c1-150)
    echo "   Response: ${ERROR_MSG}"
    
    # Provide helpful hints
    if [ "$HTTP_CODE" == "401" ]; then
      echo -e "${YELLOW}   Hint: API key is invalid or expired${NC}"
      echo "   Generate a new key: ${N8N_HOST} → Settings → n8n API"
    elif [ "$HTTP_CODE" == "404" ]; then
      echo -e "${YELLOW}   Hint: API endpoint not found${NC}"
      echo "   Your n8n version may not support the API"
    elif [ "$HTTP_CODE" == "400" ]; then
      echo -e "${YELLOW}   Hint: Invalid workflow data${NC}"
      echo "   This might be a workflow format issue"
    elif [ "$HTTP_CODE" == "000" ]; then
      echo -e "${YELLOW}   Hint: Could not connect to n8n${NC}"
      echo "   Check if n8n is running: docker ps | grep n8n"
    fi
    ((FAILED++))
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
