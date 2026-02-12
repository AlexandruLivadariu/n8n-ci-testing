#!/bin/bash
# Web Interface Tests

test_web_003_healthcheck() {
  # Test from inside the container to bypass proxy
  # Try /healthz endpoint with curl first
  if docker exec "$N8N_CONTAINER" curl -sf http://localhost:5678/healthz > /dev/null 2>&1; then
    return 0
  fi
  
  # Try /healthcheck endpoint (alternative)
  if docker exec "$N8N_CONTAINER" curl -sf http://localhost:5678/healthcheck > /dev/null 2>&1; then
    return 0
  fi
  
  # Try with wget as fallback
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678/healthz > /dev/null 2>&1; then
    return 0
  fi
  
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678/healthcheck > /dev/null 2>&1; then
    return 0
  fi
  
  # If healthcheck endpoints don't exist, try from outside the container
  # Check if we can at least access the main page (means n8n is healthy)
  if curl -sf http://localhost:5679 > /dev/null 2>&1; then
    # n8n is accessible and responding, consider it healthy
    return 0
  fi
  
  echo "Healthcheck endpoint not responding"
  return 1
}
