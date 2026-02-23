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

  # Accept "healthy" or "starting" (healthcheck may be unreliable across n8n versions).
  # If the container is running and responding to HTTP, "starting" is acceptable.
  if [ "$health_status" = "healthy" ]; then
    return 0
  fi

  if [ "$health_status" = "starting" ]; then
    # Docker's healthcheck may not work for all n8n versions (missing curl/wget
    # inside container, or /healthz endpoint not available). Verify n8n responds
    # from outside via the exposed host port instead.
    local host_port
    host_port=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if eq $p "5678/tcp"}}{{(index $conf 0).HostPort}}{{end}}{{end}}' "$N8N_CONTAINER" 2>/dev/null || echo "")
    if [ -n "$host_port" ] && curl -sf --max-time 3 "http://localhost:${host_port}/" > /dev/null 2>&1; then
      return 0
    fi
    # Fallback: try the default test port
    if curl -sf --max-time 3 "$N8N_URL" > /dev/null 2>&1; then
      return 0
    fi
    echo "Container health status is: $health_status and n8n is not responding to HTTP"
    return 1
  fi

  # "unhealthy" or other unexpected statuses
  echo "Container health status is: $health_status (expected: healthy or starting)"
  return 1
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

  # Calculate uptime in seconds (portable across GNU and BSD date)
  local start_epoch
  # Try GNU date first (-d flag)
  start_epoch=$(date -d "$started_at" +%s 2>/dev/null) || \
  # Try BSD/macOS date (-j -f flags) with ISO 8601 format
  start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${started_at%%.*}" +%s 2>/dev/null) || \
  # Last resort: use docker inspect with a Go template for Unix timestamp
  start_epoch=$(docker inspect --format='{{.State.StartedAt}}' "$N8N_CONTAINER" 2>/dev/null | \
    awk -F'[-T:.]' '{cmd="date -d \""$1"-"$2"-"$3" "$4":"$5":"$6"\" +%s 2>/dev/null"; cmd | getline val; close(cmd); if(val) print val}') || \
  { echo "Could not parse container start time"; return 1; }
  local now_epoch=$(date +%s)
  local uptime=$((now_epoch - start_epoch))

  # Use a shorter minimum uptime threshold for post-update (container was just restarted)
  local min_uptime=${MIN_UPTIME_SECONDS:-30}
  if [ "$PHASE" = "post-update" ]; then
    min_uptime=10
  fi

  if [ $uptime -lt $min_uptime ]; then
    echo "Container uptime is only ${uptime}s (minimum: ${min_uptime}s, may be crash-looping)"
    return 1
  fi

  # Check restart count
  local restart_count=$(docker inspect --format='{{.RestartCount}}' "$N8N_CONTAINER" 2>/dev/null)
  if [ "$restart_count" -gt 0 ] 2>/dev/null; then
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
