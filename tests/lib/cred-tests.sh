#!/bin/bash
# Credential Tests

test_cred_001_decryption() {
  # Test credential webhook by calling it from inside the n8n container
  # Use production webhook path (not test path)
  local webhook_path="/webhook/test/credential"
  
  # Debug: check if container name is set
  if [ -z "$N8N_CONTAINER" ]; then
    echo "ERROR: N8N_CONTAINER variable is not set"
    return 1
  fi
  
  # Simple approach: use timeout command directly
  local response=$(timeout 10 docker exec "$N8N_CONTAINER" wget -q -O- --timeout=5 "http://localhost:5678$webhook_path" 2>&1)
  local exit_code=$?
  
  # Check if timeout or other error
  if [ $exit_code -eq 124 ]; then
    echo "Credential test webhook timed out after 10 seconds"
    return 1
  fi
  
  # Check for 404 - workflow may not be active
  if echo "$response" | grep -q "404 Not Found"; then
    echo "Webhook returned 404 - workflow may not be active in n8n (check that 'Test: Credential Decryption' workflow is Active, not just imported)"
    return 1
  fi
  
  if [ $exit_code -ne 0 ] || [ -z "$response" ]; then
    echo "Credential test webhook failed (exit code: $exit_code, response: $response)"
    return 1
  fi
  
  # Check for decryption error
  if echo "$response" | grep -qi "could not be decrypted"; then
    echo "Credential decryption failed - encryption key may have changed"
    return 1
  fi
  
  # Verify success
  if echo "$response" | grep -q "success.*true"; then
    return 0
  fi
  
  echo "Credential test did not succeed: $response"
  return 1
}
