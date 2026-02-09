#!/bin/bash
# Performance Tests

test_perf_001_response_time() {
  # Ensure proxy bypass
  export no_proxy="localhost,127.0.0.1"
  export NO_PROXY="localhost,127.0.0.1"
  
  # Skip if no API key
  if [ -z "$N8N_TEST_API_KEY" ]; then
    echo "N8N_TEST_API_KEY not set - skipping performance test"
    return 0
  fi
  
  # Measure API response time
  local start_time=$(date +%s%3N)
  
  local response=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" --noproxy '*' \
    -H "X-N8N-API-KEY: $N8N_TEST_API_KEY" \
    "$N8N_URL/rest/workflows" 2>/dev/null || echo "000")
  
  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))
  
  if [ "$response" != "200" ]; then
    echo "API request failed with status: $response"
    return 1
  fi
  
  # Check if response time is reasonable (< 5 seconds)
  if [ $duration -gt 5000 ]; then
    echo "Response time too slow: ${duration}ms"
    return 1
  fi
  
  # Compare against baseline if exists
  if [ -n "$BASELINE_RESPONSE_TIME" ] && [ "$BASELINE_RESPONSE_TIME" != "null" ]; then
    local increase=$(awk "BEGIN {printf \"%.0f\", (($duration - $BASELINE_RESPONSE_TIME) / $BASELINE_RESPONSE_TIME) * 100}")
    
    if [ $increase -gt 50 ]; then
      echo "Response time increased by ${increase}% (${BASELINE_RESPONSE_TIME}ms -> ${duration}ms)"
      return 1
    fi
  fi
  
  return 0
}
