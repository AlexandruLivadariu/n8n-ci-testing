#!/bin/bash

# Automated workflow import for n8n CI/CD using cookie-based authentication
#
# This script uses n8n's internal REST API (/rest/workflows) with session cookies
# instead of the public API (/api/v1/workflows) which requires API keys.
#
# This approach:
#   - Works with fresh n8n instances (no pre-created API key needed)
#   - Uses the same authentication method as the n8n UI
#   - Fully automated for CI/CD pipelines

# Don't exit on error - we want to see all failures
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

# CI/CD owner credentials (override with env vars if needed)
OWNER_EMAIL="${N8N_CI_EMAIL:-ci@test.local}"
OWNER_PASSWORD="${N8N_CI_PASSWORD:-TestPassword123!}"
OWNER_FIRST_NAME="${N8N_CI_FIRST_NAME:-CI}"
OWNER_LAST_NAME="${N8N_CI_LAST_NAME:-Test}"

echo ""
echo -e "${YELLOW}Step 1: Setting up owner account (if needed)${NC}"

# Try to set up owner account (will fail gracefully if already exists)
SETUP_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"${OWNER_EMAIL}\",
    \"password\": \"${OWNER_PASSWORD}\",
    \"firstName\": \"${OWNER_FIRST_NAME}\",
    \"lastName\": \"${OWNER_LAST_NAME}\"
  }" \
  "${N8N_HOST}/rest/owner/setup" 2>/dev/null || echo -e "\n000")

SETUP_CODE=$(echo "$SETUP_RESPONSE" | tail -n1)

if [ "$SETUP_CODE" == "200" ]; then
  echo -e "${GREEN}✅ Owner account created${NC}"
elif [ "$SETUP_CODE" == "400" ]; then
  echo -e "${YELLOW}⚠️  Owner already exists (this is fine)${NC}"
else
  echo -e "${YELLOW}⚠️  Owner setup returned HTTP ${SETUP_CODE} (continuing anyway)${NC}"
fi

echo ""
echo -e "${YELLOW}Step 2: Logging in to get session cookie${NC}"

# Login to get session cookie
COOKIE_FILE=$(mktemp)
LOGIN_RESPONSE=$(curl -s -c "$COOKIE_FILE" -w "\n%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "{
    \"emailOrLdapLoginId\": \"${OWNER_EMAIL}\",
    \"password\": \"${OWNER_PASSWORD}\"
  }" \
  "${N8N_HOST}/rest/login" 2>/dev/null || echo -e "\n000")

LOGIN_CODE=$(echo "$LOGIN_RESPONSE" | tail -n1)
LOGIN_BODY=$(echo "$LOGIN_RESPONSE" | head -n -1)

if [ "$LOGIN_CODE" == "200" ]; then
  # Check if we got a session cookie
  if grep -q "n8n-auth" "$COOKIE_FILE" 2>/dev/null; then
    echo -e "${GREEN}✅ Logged in successfully (cookie-based auth)${NC}"
  else
    echo -e "${RED}❌ Failed to get session cookie${NC}"
    rm -f "$COOKIE_FILE"
    exit 1
  fi
else
  echo -e "${RED}❌ Login failed (HTTP ${LOGIN_CODE})${NC}"
  echo "   Response: ${LOGIN_BODY:0:100}"
  rm -f "$COOKIE_FILE"
  exit 1
fi

echo ""
echo -e "${YELLOW}Step 3: Importing workflows${NC}"
echo ""

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
  # Keep 'active' field and set it to true to ensure workflow is active on import
  WORKFLOW_DATA=$(cat "$workflow_file" | jq 'del(.id, .tags, .createdAt, .updatedAt, .versionId) | .active = true')
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}   ❌ Failed to parse workflow JSON${NC}"
    ((FAILED++))
    echo ""
    continue
  fi
  
  # Import via n8n internal REST API using cookie-based authentication
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -b "$COOKIE_FILE" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$WORKFLOW_DATA" \
    "${N8N_HOST}/rest/workflows" 2>/dev/null || echo -e "\n000")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  RESPONSE_BODY=$(echo "$RESPONSE" | head -n -1)
  
  if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "201" ]; then
    echo -e "${GREEN}   ✅ Imported successfully${NC}"
    
    # Debug: Show response structure
    echo "   Debug - Response structure:"
    echo "$RESPONSE_BODY" | jq '{id, data: {id}}' 2>/dev/null || echo "$RESPONSE_BODY" | head -c 200
    
    # Extract workflow ID from response to activate it
    WORKFLOW_ID=$(echo "$RESPONSE_BODY" | jq -r '.id // .data.id' 2>/dev/null)
    
    if [ -n "$WORKFLOW_ID" ] && [ "$WORKFLOW_ID" != "null" ]; then
      echo "   Activating workflow (ID: ${WORKFLOW_ID})..."
      
      # Activate the workflow using internal REST API
      ACTIVATE_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -b "$COOKIE_FILE" \
        -X PATCH \
        -H "Content-Type: application/json" \
        -d '{"active": true}' \
        "${N8N_HOST}/rest/workflows/${WORKFLOW_ID}" 2>/dev/null || echo -e "\n000")
      
      ACTIVATE_CODE=$(echo "$ACTIVATE_RESPONSE" | tail -n1)
      ACTIVATE_BODY=$(echo "$ACTIVATE_RESPONSE" | head -n -1)
      
      if [ "$ACTIVATE_CODE" == "200" ]; then
        echo -e "${GREEN}   ✅ Activated and webhooks registered${NC}"
      else
        echo -e "${YELLOW}   ⚠️  Could not activate (HTTP ${ACTIVATE_CODE})${NC}"
        echo "   Response: ${ACTIVATE_BODY:0:150}"
      fi
    else
      echo -e "${YELLOW}   ⚠️  Could not extract workflow ID for activation${NC}"
      echo "   Full response: ${RESPONSE_BODY:0:300}"
    fi
    
    ((IMPORTED++))
  else
    echo -e "${RED}   ❌ Failed (HTTP ${HTTP_CODE})${NC}"
    ERROR_MSG=$(echo "$RESPONSE_BODY" | cut -c1-150)
    echo "   Response: ${ERROR_MSG}"
    ((FAILED++))
  fi
  echo ""
done

echo "================================"
echo -e "${BLUE}Import Summary${NC}"
echo "  Imported: ${IMPORTED}"
echo "  Failed:   ${FAILED}"
echo ""

# Clean up cookie file if it exists
if [ -f "$COOKIE_FILE" ]; then
  rm -f "$COOKIE_FILE"
fi

if [ $IMPORTED -gt 0 ]; then
  echo -e "${GREEN}✅ Successfully imported ${IMPORTED} workflow(s)${NC}"
  echo ""
  echo -e "${YELLOW}⏳ Waiting for webhooks to register...${NC}"
  sleep 3
  echo -e "${GREEN}✅ Webhooks should now be ready${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  No workflows imported${NC}"
  exit 1
fi
