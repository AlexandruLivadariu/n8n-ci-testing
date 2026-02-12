#!/bin/bash
# Workflow Tests

test_wf_001_webhook() {
  # Test webhook - try from outside container first (more reliable)
  local webhook_path="/webhook/test/health"
  
  # Debug: check if container name is set
  if [ -z "$N8N_CONTAINER" ]; then
    echo "ERROR: N8N_CONTAINER variable is not set"
    return 1
  fi
  
  # Try from outside the container first (using host port)
  local response=$(curl -s --max-time 10 "http://localhost:5679$webhook_path" 2>&1)
  local exit_code=$?
  
  # Check if workflow is not registered (404)
  if echo "$response" | grep -q "is not registered"; then
    echo "Workflow not active - please activate 'Test: Health Check' workflow in n8n UI"
    return 1
  fi
  
  if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
    # Verify response contains status:ok
    if echo "$response" | grep -q "status.*ok"; then
      return 0
    fi
  fi
  
  # If outside test failed, try from inside container with curl
  response=$(docker exec "$N8N_CONTAINER" curl -sf --max-time 5 "http://localhost:5678$webhook_path" 2>&1)
  exit_code=$?
  
  if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
    if echo "$response" | grep -q "status.*ok"; then
      return 0
    fi
  fi
  
  # All methods failed
  echo "Workflow not active or not responding (activate it in n8n UI)"
  return 1
}
