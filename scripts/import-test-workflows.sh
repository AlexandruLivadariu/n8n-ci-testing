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
echo -e "${YELLOW}Step 2: Logging in to get session token${NC}"

# Login to get JWT token
LOGIN_RESPONSE=$(curl -s -w "\n%{http_code}" \
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
  # Extract JWT token from response - try multiple possible locations
  JWT_TOKEN=$(echo "$LOGIN_BODY" | jq -r '.data.token // .token // .data.authToken // .authToken // empty' 2>/dev/null)
  
  if [ -n "$JWT_TOKEN" ] && [ "$JWT_TOKEN" != "null" ]; then
    echo -e "${GREEN}✅ Logged in successfully${NC}"
  else
    # Token might be in cookies or headers, not in body
    # For newer n8n versions, the session is cookie-based
    echo -e "${YELLOW}⚠️  No JWT token in response body (cookie-based auth)${NC}"
    echo "   Response: ${LOGIN_BODY:0:200}"
    echo ""
    echo "Trying cookie-based authentication..."
    
    # Try login again and capture cookies
    COOKIE_FILE=$(mktemp)
    LOGIN_WITH_COOKIES=$(curl -s -c "$COOKIE_FILE" \
      -X POST \
      -H "Content-Type: application/json" \
      -d "{
        \"emailOrLdapLoginId\": \"${OWNER_EMAIL}\",
        \"password\": \"${OWNER_PASSWORD}\"
      }" \
      "${N8N_HOST}/rest/login" 2>/dev/null)
    
    # Check if we got a session cookie
    if grep -q "n8n-auth" "$COOKIE_FILE" 2>/dev/null; then
      echo -e "${GREEN}✅ Got session cookie${NC}"
      USE_COOKIES=true
    else
      echo -e "${RED}❌ Failed to get session cookie${NC}"
      rm -f "$COOKIE_FILE"
      echo ""
      echo "Manual import required:"
      echo "  1. Go to ${N8N_HOST}"
      echo "  2. Complete owner setup"
      echo "  3. Import workflows manually"
      exit 1
    fi
  fi
else
  echo -e "${RED}❌ Login failed (HTTP ${LOGIN_CODE})${NC}"
  echo "   Response: ${LOGIN_BODY:0:100}"
  echo ""
  echo "Manual import required:"
  echo "  1. Go to ${N8N_HOST}"
  echo "  2. Complete owner setup"
  echo "  3. Import workflows manually"
  exit 1
fi

echo ""
echo -e "${YELLOW}Step 3: Creating API key${NC}"

# Create API key using JWT or cookies
if [ "$USE_COOKIES" == "true" ]; then
  # Use cookie-based auth with scopes array
  API_KEY_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -b "$COOKIE_FILE" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{
      "label": "CI/CD Automation Key",
      "scopes": ["workflow:create", "workflow:read", "workflow:update", "workflow:delete"]
    }' \
    "${N8N_HOST}/rest/api-keys" 2>/dev/null || echo -e "\n000")
else
  # Use JWT token with scopes array
  API_KEY_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${JWT_TOKEN}" \
    -d '{
      "label": "CI/CD Automation Key",
      "scopes": ["workflow:create", "workflow:read", "workflow:update", "workflow:delete"]
    }' \
    "${N8N_HOST}/rest/api-keys" 2>/dev/null || echo -e "\n000")
fi

# Clean up cookie file if used
if [ -f "$COOKIE_FILE" ]; then
  rm -f "$COOKIE_FILE"
fi

API_KEY_CODE=$(echo "$API_KEY_RESPONSE" | tail -n1)
API_KEY_BODY=$(echo "$API_KEY_RESPONSE" | head -n -1)

if [ "$API_KEY_CODE" == "200" ] || [ "$API_KEY_CODE" == "201" ]; then
  # Extract API key from response
  N8N_API_KEY=$(echo "$API_KEY_BODY" | jq -r '.data.apiKey // .apiKey // empty' 2>/dev/null)
  
  if [ -n "$N8N_API_KEY" ] && [ "$N8N_API_KEY" != "null" ]; then
    echo -e "${GREEN}✅ API key created${NC}"
    echo "   Key: ${N8N_API_KEY:0:20}..."
  else
    echo -e "${RED}❌ Failed to extract API key${NC}"
    echo "   Response: ${API_KEY_BODY:0:100}"
    exit 1
  fi
else
  echo -e "${RED}❌ API key creation failed (HTTP ${API_KEY_CODE})${NC}"
  echo "   Response: ${API_KEY_BODY:0:100}"
  exit 1
fi

echo ""
echo -e "${YELLOW}Step 4: Importing workflows${NC}"
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
  WORKFLOW_DATA=$(cat "$workflow_file" | jq 'del(.active, .id, .tags, .createdAt, .updatedAt, .versionId)')
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}   ❌ Failed to parse workflow JSON${NC}"
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
    echo -e "${GREEN}   ✅ Imported successfully${NC}"
    
    # Extract workflow ID from response to activate it
    WORKFLOW_ID=$(echo "$RESPONSE_BODY" | jq -r '.id' 2>/dev/null)
    
    if [ -n "$WORKFLOW_ID" ] && [ "$WORKFLOW_ID" != "null" ]; then
      # Activate the workflow using the correct endpoint
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
      fi
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

if [ $IMPORTED -gt 0 ]; then
  echo -e "${GREEN}✅ Successfully imported ${IMPORTED} workflow(s)${NC}"
  exit 0
else
  echo -e "${YELLOW}⚠️  No workflows imported${NC}"
  exit 1
fi
