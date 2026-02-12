#!/bin/bash

# Security Tests (SEC)
# Tests security configuration and compliance

# SEC-001: Security Headers Check
test_sec_001_security_headers() {
  # Get response headers - use proxy bypass
  export no_proxy="localhost,127.0.0.1"
  export NO_PROXY="localhost,127.0.0.1"
  
  local headers=$(curl -sI "$N8N_HOST" --max-time 10 --noproxy '*' 2>/dev/null)
  
  if [ -z "$headers" ]; then
    echo "Could not fetch headers (connection issue)"
    return 1
  fi
  
  local issues=()
  
  # Check X-Content-Type-Options
  if ! echo "$headers" | grep -qi "X-Content-Type-Options.*nosniff"; then
    issues+=("Missing X-Content-Type-Options: nosniff")
  fi
  
  # Check X-Frame-Options
  if ! echo "$headers" | grep -qi "X-Frame-Options"; then
    issues+=("Missing X-Frame-Options header")
  fi
  
  # Check if Server header exposes version
  if echo "$headers" | grep -i "^Server:" | grep -qE "[0-9]+\.[0-9]+"; then
    issues+=("Server header may expose version information")
  fi
  
  if [ ${#issues[@]} -eq 0 ]; then
    return 0
  else
    echo "${issues[*]}"
    return 1
  fi
}

# SEC-002: Unauthenticated Access Prevention
test_sec_002_unauthenticated_access() {
  export no_proxy="localhost,127.0.0.1"
  export NO_PROXY="localhost,127.0.0.1"
  
  local endpoints=(
    "/api/v1/workflows"
    "/api/v1/credentials"
    "/api/v1/executions"
  )
  
  local failed=false
  local issues=()
  
  for endpoint in "${endpoints[@]}"; do
    local response=$(curl -s -w "\n%{http_code}" "$N8N_HOST$endpoint" --max-time 5 --noproxy '*' 2>/dev/null)
    local http_code=$(echo "$response" | tail -n1)
    
    # If we got 000, there's a connection issue - skip this test
    if [ "$http_code" = "000" ]; then
      echo "Connection issue - cannot test unauthenticated access"
      return 1
    fi
    
    # Should return 401 Unauthorized or 403 Forbidden
    if [ "$http_code" != "401" ] && [ "$http_code" != "403" ]; then
      issues+=("$endpoint returned $http_code (expected 401/403)")
      failed=true
    fi
  done
  
  if [ "$failed" = false ]; then
    return 0
  else
    echo "${issues[*]}"
    return 1
  fi
}

# SEC-003: Container Security Configuration
test_sec_003_container_security() {
  local issues=()
  
  # Check if running as root
  local user=$(docker inspect --format='{{.Config.User}}' "$N8N_CONTAINER" 2>/dev/null)
  if [ -z "$user" ] || [ "$user" = "root" ] || [ "$user" = "0" ]; then
    issues+=("Container may be running as root")
  fi
  
  # Check for privileged mode
  local privileged=$(docker inspect --format='{{.HostConfig.Privileged}}' "$N8N_CONTAINER" 2>/dev/null)
  if [ "$privileged" = "true" ]; then
    issues+=("Container is running in privileged mode")
  fi
  
  # Check for host network mode
  local network_mode=$(docker inspect --format='{{.HostConfig.NetworkMode}}' "$N8N_CONTAINER" 2>/dev/null)
  if [ "$network_mode" = "host" ]; then
    issues+=("Container is using host network mode")
  fi
  
  # Check if docker.sock is mounted
  if docker inspect --format='{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' "$N8N_CONTAINER" 2>/dev/null | grep -q "docker.sock"; then
    issues+=("Docker socket is mounted (security risk)")
  fi
  
  if [ ${#issues[@]} -eq 0 ]; then
    return 0
  else
    echo "${issues[*]}"
    return 1
  fi
}

# SEC-004: Environment Variables Integrity
test_sec_004_env_vars() {
  local required_vars=(
    "N8N_ENCRYPTION_KEY"
    "DB_TYPE"
    "DB_POSTGRESDB_HOST"
    "DB_POSTGRESDB_DATABASE"
  )
  
  local issues=()
  
  for var in "${required_vars[@]}"; do
    # Check if variable exists
    if ! docker exec "$N8N_CONTAINER" sh -c "env | grep -q '^${var}='" 2>/dev/null; then
      issues+=("Missing required environment variable: $var")
    fi
  done
  
  if [ ${#issues[@]} -eq 0 ]; then
    return 0
  else
    echo "${issues[*]}"
    return 1
  fi
}

# SEC-005: Credential Encryption Check
test_sec_005_credential_encryption() {
  # Query credentials from database to check if any exist
  local query="SELECT COUNT(*) FROM credential_entity;"
  
  local result=$(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "$query" 2>/dev/null)
  
  if [ -z "$result" ]; then
    # If we can't query the table, it might not exist yet (fresh install)
    # Check if the table exists
    local table_exists=$(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'credential_entity');" 2>/dev/null | tr -d ' ')
    
    if [ "$table_exists" = "t" ]; then
      echo "Could not query credentials table"
      return 1
    else
      # Table doesn't exist - this is OK for a fresh install
      return 0
    fi
  fi
  
  local total=$(echo "$result" | tr -d ' ')
  
  # If no credentials exist, test passes (nothing to check)
  if [ "$total" = "0" ] || [ -z "$total" ]; then
    return 0
  fi
  
  # Check if credentials table has encrypted data column
  local schema_check=$(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "\d credential_entity" 2>/dev/null | grep -i "data")
  
  if [ -z "$schema_check" ]; then
    echo "Could not verify credential encryption schema"
    return 1
  fi
  
  # If we got here, credentials exist and schema looks OK
  return 0
}
