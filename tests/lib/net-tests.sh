#!/bin/bash
# Network Tests

test_net_001_http_accessible() {
  # Test from inside the container to bypass proxy
  if docker exec "$N8N_CONTAINER" wget -q -O- http://localhost:5678 > /dev/null 2>&1; then
    return 0
  fi
  
  echo "n8n web interface not responding inside container"
  return 1
}
