#!/bin/bash

# Don't exit on error - we want to collect all test results
set +e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Bypass corporate proxy for localhost
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

echo -e "${BLUE}🧪 Running n8n Webhook Tests${NC}"
echo "================================"

N8N_HOST="${N8N_HOST:-http://localhost:5679}"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test 1: Container Health
echo -e "${YELLOW}Test 1: Container Health Check${NC}"
((TOTAL_TESTS++))

# Check for n8n-test container
if docker ps --filter "name=n8n-test" --format "{{.Names}}" 2>/dev/null | grep -q "^n8n-test$"; then
  echo -e "${GREEN}✅ PASS${NC} - n8n-test container is running"
  ((PASSED_TESTS++))
# Check for n8n-dev container
elif docker ps --filter "name=n8n-dev" --format "{{.Names}}" 2>/dev/null | grep -q "^n8n-dev$"; then
  echo -e "${GREEN}✅ PASS${NC} - n8n-dev container is running"
  ((PASSED_TESTS++))
else
  echo -e "${RED}❌ FAIL${NC} - No n8n container running (expected n8n-test or n8n-dev)"
  ((FAILED_TESTS++))
  echo ""
  echo "Available containers:"
  docker ps --format "{{.Names}}" 2>/dev/null || echo "Could not list containers"
  echo ""
  echo -e "${YELLOW}⚠️  Skipping remaining tests - n8n not available${NC}"
  echo ""
  echo "================================"
  echo -e "${BLUE}Test Summary${NC}"
  echo "  Total:  ${TOTAL_TESTS}"
  echo -e "  ${GREEN}Passed: ${PASSED_TESTS}${NC}"
  echo -e "  ${RED}Failed: ${FAILED_TESTS}${NC}"
  exit 1
fi
echo ""

# Test 2: Web Interface
echo -e "${YELLOW}Test 2: Web Interface Accessibility${NC}"
((TOTAL_TESTS++))
RESPONSE=$(timeout 5 curl -s -o /dev/null -w "%{http_code}" "${N8N_HOST}" 2>/dev/null || echo "000")
if [ "$RESPONSE" == "200" ]; then
  echo -e "${GREEN}✅ PASS${NC} - Web interface accessible (HTTP ${RESPONSE})"
  ((PASSED_TESTS++))
else
  echo -e "${RED}❌ FAIL${NC} - Web interface not accessible (HTTP ${RESPONSE})"
  ((FAILED_TESTS++))
fi
echo ""

# Test 3: Database Connectivity
echo -e "${YELLOW}Test 3: Database Connectivity${NC}"
((TOTAL_TESTS++))
if docker exec n8n-postgres-test psql -U n8n -d n8n -c "SELECT COUNT(*) FROM workflow_entity;" > /dev/null 2>&1; then
  WORKFLOW_COUNT=$(docker exec n8n-postgres-test psql -U n8n -d n8n -t -c "SELECT COUNT(*) FROM workflow_entity;" | tr -d ' ')
  echo -e "${GREEN}✅ PASS${NC} - Database accessible (${WORKFLOW_COUNT} workflows in DB)"
  ((PASSED_TESTS++))
else
  echo -e "${RED}❌ FAIL${NC} - Database not accessible"
  ((FAILED_TESTS++))
fi
echo ""

# Test 4: Health Webhook
echo -e "${YELLOW}Test 4: Health Check Webhook${NC}"
((TOTAL_TESTS++))
RESPONSE=$(timeout 5 curl -s "${N8N_HOST}/webhook-test/test/health" 2>/dev/null || echo "")
if echo "$RESPONSE" | grep -q "status.*ok"; then
  echo -e "${GREEN}✅ PASS${NC} - Health webhook responding"
  echo "   Response: ${RESPONSE:0:100}"
  ((PASSED_TESTS++))
else
  echo -e "${RED}❌ FAIL${NC} - Health webhook not responding"
  echo "   Response: ${RESPONSE:0:100}"
  ((FAILED_TESTS++))
fi
echo ""

# Test 5: Echo Webhook (Data Processing)
echo -e "${YELLOW}Test 5: Echo Data Processing Webhook${NC}"
((TOTAL_TESTS++))
RESPONSE=$(timeout 5 curl -s -X POST \
  -H "Content-Type: application/json" \
  -d '{"input":"test_data_123"}' \
  "${N8N_HOST}/webhook-test/test/echo" 2>/dev/null || echo "")
if echo "$RESPONSE" | grep -q "processed_at"; then
  echo -e "${GREEN}✅ PASS${NC} - Echo webhook processing data"
  echo "   Response: ${RESPONSE:0:100}"
  ((PASSED_TESTS++))
else
  echo -e "${RED}❌ FAIL${NC} - Echo webhook not processing data"
  echo "   Response: ${RESPONSE:0:100}"
  ((FAILED_TESTS++))
fi
echo ""

# Test 6: HTTP Request Node
echo -e "${YELLOW}Test 6: HTTP Request Node${NC}"
((TOTAL_TESTS++))
RESPONSE=$(timeout 10 curl -s "${N8N_HOST}/webhook-test/test/http" 2>/dev/null || echo "")
if echo "$RESPONSE" | grep -q "success.*true"; then
  echo -e "${GREEN}✅ PASS${NC} - HTTP Request node working"
  echo "   Response: ${RESPONSE:0:100}"
  ((PASSED_TESTS++))
else
  echo -e "${RED}❌ FAIL${NC} - HTTP Request node not working"
  echo "   Response: ${RESPONSE:0:100}"
  ((FAILED_TESTS++))
fi
echo ""

# Summary
echo "================================"
echo -e "${BLUE}Test Summary${NC}"
echo "  Total:  ${TOTAL_TESTS}"
echo -e "  ${GREEN}Passed: ${PASSED_TESTS}${NC}"
echo -e "  ${RED}Failed: ${FAILED_TESTS}${NC}"
echo ""

# Save results to log file
mkdir -p ../logs
{
  echo "# n8n Test Results"
  echo ""
  echo "**Date:** $(date)"
  echo "**Total Tests:** ${TOTAL_TESTS}"
  echo "**Passed:** ${PASSED_TESTS}"
  echo "**Failed:** ${FAILED_TESTS}"
  echo ""
  if [ $FAILED_TESTS -eq 0 ]; then
    echo "**Status:** ✅ All tests passed"
  else
    echo "**Status:** ❌ Some tests failed"
  fi
} > ../logs/test-results.log

if [ $FAILED_TESTS -eq 0 ]; then
  echo -e "${GREEN}✅ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ ${FAILED_TESTS} test(s) failed${NC}"
  exit 1
fi
