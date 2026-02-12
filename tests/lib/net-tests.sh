#!/bin/bash
# Network Tests

test_net_001_http_accessible() {
  # Test from inside the container to bypass proxy
  # Try curl first (most likely to be available in n8n container)
  if docker exec "$N8N_CONTAINER" curl -sf http://localhost:5678 > /dev/null 2>&1; then
    return 0
  fi
  
  # Try wget as fallback
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678 > /dev/null 2>&1; then
    return 0
  fi
  
  # If both failed, check if we can at least connect from outside
  # (this means n8n is running, just the tools aren't available in container)
  if curl -sf http://localhost:5679 > /dev/null 2>&1; then
    # n8n is accessible from outside, so it's working
    return 0
  fi
  
  echo "n8n web interface not responding inside container"
  return 1
}
