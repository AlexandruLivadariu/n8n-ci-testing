#!/bin/bash
# Test n8n API authentication and endpoints

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

N8N_HOST="${N8N_HOST:-http://localhost:5679}"
N8N_API_KEY="${N8N_TEST_API_KEY}"

echo -e "${BLUE}🔍 n8n API Diagnostics${NC}"
echo "================================"
echo "Host: $N8N_HOST"
echo "API Key: ${N8N_API_KEY:0:20}..."
echo ""

if [ -z "$N8N_API_KEY" ]; then
  echo -e "${RED}❌ N8N_TEST_API_KEY not set${NC}"
  echo "Export your API key first:"
  echo "  export N8N_TEST_API_KEY='your-key-here'"
  exit 1
fi

# Test 1: Check if n8n is responding
echo -e "${YELLOW}Test 1: n8n Web Interface${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$N8N_HOST" 2>/dev/null)
if [ "$HTTP_CODE" == "200" ]; then
  echo -e "${GREEN}✅ n8n is responding (HTTP $HTTP_CODE)${NC}"
else
  echo -e "${RED}❌ n8n not responding (HTTP $HTTP_CODE)${NC}"
  exit 1
fi
echo ""

# Test 2: Try different API endpoints and auth methods
echo -e "${YELLOW}Test 2: API Endpoint Discovery${NC}"

# Try /api/v1/workflows with X-N8N-API-KEY
echo "Trying: POST /api/v1/workflows with X-N8N-API-KEY header"
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X GET \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  "${N8N_HOST}/api/v1/workflows" 2>/dev/null || echo -e "\n000")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
echo "  Response: HTTP $HTTP_CODE"
if [ "$HTTP_CODE" != "401" ] && [ "$HTTP_CODE" != "404" ]; then
  echo -e "${GREEN}  ✅ This endpoint works!${NC}"
  echo "  Body: $(echo "$RESPONSE" | head -n1 | cut -c1-100)"
fi
echo ""

# Try /rest/workflows with X-N8N-API-KEY
echo "Trying: GET /rest/workflows with X-N8N-API-KEY header"
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X GET \
  -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  "${N8N_HOST}/rest/workflows" 2>/dev/null || echo -e "\n000")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
echo "  Response: HTTP $HTTP_CODE"
if [ "$HTTP_CODE" != "401" ] && [ "$HTTP_CODE" != "404" ]; then
  echo -e "${GREEN}  ✅ This endpoint works!${NC}"
  echo "  Body: $(echo "$RESPONSE" | head -n1 | cut -c1-100)"
fi
echo ""

# Try with Bearer token (if JWT)
if [[ "$N8N_API_KEY" == eyJ* ]]; then
  echo "Detected JWT token, trying Bearer authentication"
  
  echo "Trying: GET /api/v1/workflows with Authorization: Bearer"
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X GET \
    -H "Authorization: Bearer ${N8N_API_KEY}" \
    "${N8N_HOST}/api/v1/workflows" 2>/dev/null || echo -e "\n000")
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  echo "  Response: HTTP $HTTP_CODE"
  if [ "$HTTP_CODE" != "401" ] && [ "$HTTP_CODE" != "404" ]; then
    echo -e "${GREEN}  ✅ This endpoint works!${NC}"
    echo "  Body: $(echo "$RESPONSE" | head -n1 | cut -c1-100)"
  fi
  echo ""
  
  echo "Trying: GET /rest/workflows with Authorization: Bearer"
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X GET \
    -H "Authorization: Bearer ${N8N_API_KEY}" \
    "${N8N_HOST}/rest/workflows" 2>/dev/null || echo -e "\n000")
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  echo "  Response: HTTP $HTTP_CODE"
  if [ "$HTTP_CODE" != "401" ] && [ "$HTTP_CODE" != "404" ]; then
    echo -e "${GREEN}  ✅ This endpoint works!${NC}"
    echo "  Body: $(echo "$RESPONSE" | head -n1 | cut -c1-100)"
  fi
  echo ""
fi

echo "================================"
echo -e "${BLUE}Recommendations:${NC}"
echo ""
echo "If all tests show 401 Unauthorized:"
echo "  - Your API key may be invalid or expired"
echo "  - Generate a new one: Settings → API → Create API key"
echo ""
echo "If tests show 404 Not Found:"
echo "  - n8n version may not support API keys"
echo "  - Try manual workflow import via UI"
echo ""
echo "For manual import:"
echo "  1. Go to $N8N_HOST"
echo "  2. Click 'Add workflow' → 'Import from file'"
echo "  3. Import files from: ../workflows/"
