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
