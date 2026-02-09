#!/bin/bash
# Web Interface Tests

test_web_003_healthcheck() {
  # Test from inside the container to bypass proxy
  # Try /healthz endpoint
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678/healthz > /dev/null 2>&1; then
    return 0
  fi
  
  # Try /healthcheck endpoint (alternative)
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678/healthcheck > /dev/null 2>&1; then
    return 0
  fi
  
  echo "Healthcheck endpoint not responding"
  return 1
}
