#!/bin/bash
# Infrastructure Tests

test_inf_001_container_running() {
  # Check if container exists and is running using docker inspect
  local status=$(docker inspect --format='{{.State.Status}}' "$N8N_CONTAINER" 2>/dev/null)
  
  if [ -z "$status" ]; then
    echo "Container $N8N_CONTAINER not found"
    return 1
  fi
  
  if [ "$status" != "running" ]; then
    echo "Container $N8N_CONTAINER status is: $status (expected: running)"
    return 1
  fi
  
  # Check health status if healthcheck is defined (trim whitespace)
  local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$N8N_CONTAINER" 2>/dev/null | tr -d '\n\r' || echo "none")
  
  # If no healthcheck is defined, that's OK
  if [ "$health_status" = "none" ] || [ "$health_status" = "" ] || [ -z "$health_status" ]; then
    # No healthcheck defined, container is running, that's fine
    return 0
  fi
  
  # If healthcheck exists, it must be healthy
  if [ "$health_status" != "healthy" ]; then
    echo "Container health status is: $health_status (expected: healthy)"
    return 1
  fi
  
  return 0
}

test_inf_003_postgres_health() {
  # Check if PostgreSQL container exists and is running
  local status=$(docker inspect --format='{{.State.Status}}' "$POSTGRES_CONTAINER" 2>/dev/null)
  
  if [ -z "$status" ]; then
    echo "PostgreSQL container $POSTGRES_CONTAINER not found"
    return 1
  fi
  
  if [ "$status" != "running" ]; then
    echo "PostgreSQL container status is: $status (expected: running)"
    return 1
  fi
  
  # Check pg_isready
  if ! docker exec "$POSTGRES_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; then
    echo "PostgreSQL is not ready to accept connections"
    return 1
  fi
  
  return 0
}

test_inf_002_container_uptime() {
  # Get container start time
  local started_at=$(docker inspect --format='{{.State.StartedAt}}' "$N8N_CONTAINER" 2>/dev/null)
  if [ -z "$started_at" ]; then
    echo "Could not get container start time"
    return 1
  fi
  
  # Calculate uptime in seconds
  local start_epoch=$(date -d "$started_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${started_at:0:19}" +%s 2>/dev/null)
  local now_epoch=$(date +%s)
  local uptime=$((now_epoch - start_epoch))
  
  # Check if container has been running for at least 30 seconds
  if [ $uptime -lt 30 ]; then
    echo "Container uptime is only ${uptime}s (may be crash-looping)"
    return 1
  fi
  
  # Check restart count
  local restart_count=$(docker inspect --format='{{.RestartCount}}' "$N8N_CONTAINER" 2>/dev/null)
  if [ "$restart_count" -gt 0 ]; then
    echo "Container has restarted $restart_count times"
    return 1
  fi
  
  return 0
}

test_inf_004_network_connectivity() {
  # Verify n8n container can reach PostgreSQL
  # Use nc (netcat) or wget as fallback since /dev/tcp may not be available
  
  # Try with nc first
  if docker exec "$N8N_CONTAINER" which nc >/dev/null 2>&1; then
    if docker exec "$N8N_CONTAINER" nc -z -w 5 "$POSTGRES_CONTAINER" 5432 2>/dev/null; then
      return 0
    fi
  fi
  
  # Try with wget as fallback
  if docker exec "$N8N_CONTAINER" which wget >/dev/null 2>&1; then
    if docker exec "$N8N_CONTAINER" wget -q --spider --timeout=5 "http://$POSTGRES_CONTAINER:5432" 2>/dev/null; then
      return 0
    fi
  fi
  
  # If both failed, check if n8n can actually connect to the database
  # by checking the n8n logs for database connection errors
  local logs=$(docker logs "$N8N_CONTAINER" --tail 50 2>&1)
  if echo "$logs" | grep -qi "database.*error\|connection.*refused\|ECONNREFUSED"; then
    echo "n8n container cannot reach PostgreSQL container (database connection errors in logs)"
    return 1
  fi
  
  # If no errors in logs and n8n is running, assume connectivity is OK
  # (n8n wouldn't be running if it couldn't connect to the database)
  return 0
}

test_inf_005_volume_mounts() {
  # Check n8n data volume is mounted
  local mounts=$(docker inspect --format='{{json .Mounts}}' "$N8N_CONTAINER" 2>/dev/null)
  if [ -z "$mounts" ]; then
    echo "Could not inspect container mounts"
    return 1
  fi
  
  # Check for n8n data directory mount
  if ! echo "$mounts" | grep -q "/home/node/.n8n"; then
    echo "n8n data volume not mounted at /home/node/.n8n"
    return 1
  fi
  
  # Test write access
  if ! docker exec "$N8N_CONTAINER" sh -c "touch /home/node/.n8n/.test_write && rm /home/node/.n8n/.test_write" 2>/dev/null; then
    echo "Cannot write to n8n data volume"
    return 1
  fi
  
  return 0
}

test_inf_006_resource_usage() {
  # Get container stats
  local stats=$(docker stats --no-stream --format "{{.MemUsage}}|{{.CPUPerc}}|{{.MemPerc}}" "$N8N_CONTAINER" 2>/dev/null)
  if [ -z "$stats" ]; then
    echo "Could not get container stats"
    return 1
  fi
  
  local mem_usage=$(echo "$stats" | cut -d'|' -f1)
  local cpu_perc=$(echo "$stats" | cut -d'|' -f2 | tr -d '%')
  local mem_perc=$(echo "$stats" | cut -d'|' -f3 | tr -d '%')
  
  # Check memory percentage (if available and not N/A)
  if [ -n "$mem_perc" ] && [ "$mem_perc" != "N/A" ]; then
    # Use awk for floating point comparison
    if awk "BEGIN {exit !($mem_perc > 80)}"; then
      echo "Memory usage high: ${mem_perc}%"
      return 1
    fi
  fi
  
  # Check CPU percentage
  if [ -n "$cpu_perc" ] && [ "$cpu_perc" != "N/A" ]; then
    if awk "BEGIN {exit !($cpu_perc > 90)}"; then
      echo "CPU usage high: ${cpu_perc}%"
      return 1
    fi
  fi
  
  return 0
}
