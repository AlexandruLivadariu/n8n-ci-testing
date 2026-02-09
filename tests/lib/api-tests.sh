#!/bin/bash
# API Tests

test_api_001_list_workflows() {
  # Ensure proxy bypass
  export no_proxy="localhost,127.0.0.1"
  export NO_PROXY="localhost,127.0.0.1"
  
  # Check if API key is set
  if [ -z "$N8N_TEST_API_KEY" ]; then
    echo "N8N_TEST_API_KEY environment variable not set - skipping API test"
    return 0  # Don't fail if API key not set
  fi
  
  # GET /rest/workflows with API key
  local response=$(timeout 10 curl -s -w "\n%{http_code}" --noproxy '*' \
    -H "X-N8N-API-KEY: $N8N_TEST_API_KEY" \
    "$N8N_URL/rest/workflows" 2>/dev/null || echo -e "\n000")
  
  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | head -n-1)
  
  if [ "$http_code" != "200" ]; then
    echo "API request failed with status: $http_code"
    return 1
  fi
  
  # Verify response is valid JSON with data array
  if ! echo "$body" | jq -e '.data' > /dev/null 2>&1; then
    echo "API response does not contain 'data' array"
    return 1
  fi
  
  return 0
}
