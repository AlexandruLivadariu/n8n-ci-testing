#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🧪 Running n8n Workflow Tests${NC}"
echo "================================"

N8N_TEST_HOST="${N8N_TEST_HOST:-http://localhost:5679}"
N8N_API_KEY="${N8N_TEST_API_KEY}"

if [ -z "$N8N_API_KEY" ]; then
  echo -e "${RED}❌ N8N_TEST_API_KEY environment variable not set${NC}"
  echo "Set it with: export N8N_TEST_API_KEY='your-api-key'"
  exit 1
fi

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

test_webhook() {
  local WEBHOOK_PATH=$1
  local TEST_NAME=$2
  local TEST_DATA=$3
  local EXPECTED_STATUS=$4
  
  echo -e "${YELLOW}Testing: ${TEST_NAME}${NC}"
  ((TOTAL_TESTS++))
  
  RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$TEST_DATA" \
    "${N8N_TEST_HOST}${WEBHOOK_PATH}" 2>/dev/null || echo -e "\n000")
  
  HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
  
  if [ "$HTTP_CODE" == "$EXPECTED_STATUS" ]; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((PASSED_TESTS++))
    return 0
  else
    echo -e "${RED}❌ FAIL${NC} (Expected ${EXPECTED_STATUS}, got ${HTTP_CODE})"
    ((FAILED_TESTS++))
    return 1
  fi
}

test_api_health() {
  echo -e "${YELLOW}Testing: n8n API Health${NC}"
  ((TOTAL_TESTS++))
  
  if curl -s -f -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_TEST_HOST}/rest/workflows" > /dev/null; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((PASSED_TESTS++))
    return 0
  else
    echo -e "${RED}❌ FAIL${NC}"
    ((FAILED_TESTS++))
    return 1
  fi
}

test_workflows_loaded() {
  echo -e "${YELLOW}Testing: Workflows Loaded${NC}"
  ((TOTAL_TESTS++))
  
  WORKFLOW_COUNT=$(curl -s -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_TEST_HOST}/rest/workflows" | jq '.data | length')
  
  if [ "$WORKFLOW_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ PASS${NC} - ${WORKFLOW_COUNT} workflows loaded"
    ((PASSED_TESTS++))
    return 0
  else
    echo -e "${RED}❌ FAIL${NC}"
    ((FAILED_TESTS++))
    return 1
  fi
}

echo "Step 1: API Health Check"
test_api_health
echo ""

echo "Step 2: Workflow Load Check"
test_workflows_loaded
echo ""

if [ -f "../tests/test-cases/webhook-tests.json" ]; then
  echo "Step 3: Webhook Tests"
  
  jq -c '.tests[]' ../tests/test-cases/webhook-tests.json | while read -r test; do
    WEBHOOK=$(echo "$test" | jq -r '.webhook')
    NAME=$(echo "$test" | jq -r '.name')
    DATA=$(echo "$test" | jq -c '.data')
    EXPECTED=$(echo "$test" | jq -r '.expectedStatus')
    
    test_webhook "$WEBHOOK" "$NAME" "$DATA" "$EXPECTED"
    echo ""
  done
fi

echo "================================"
echo -e "${BLUE}Test Summary${NC}"
echo "  Total:  ${TOTAL_TESTS}"
echo -e "  ${GREEN}Passed: ${PASSED_TESTS}${NC}"
echo -e "  ${RED}Failed: ${FAILED_TESTS}${NC}"

if [ $FAILED_TESTS -eq 0 ]; then
  echo -e "${GREEN}✅ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi