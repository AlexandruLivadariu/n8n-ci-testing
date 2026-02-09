#!/bin/bash
# Database Tests

test_db_001_query() {
  # Execute count query using the POSTGRES_USER from environment
  # The postgres:15 image creates the user specified in POSTGRES_USER
  local count=$(docker exec "$POSTGRES_CONTAINER" sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB -t -c "SELECT COUNT(*) FROM workflow_entity;"' 2>&1 | tr -d ' \n\r')
  
  # Check if query succeeded and returned a number
  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    echo "Database query failed or returned invalid result: $count"
    return 1
  fi
  
  # Check for data loss (if baseline exists)
  if [ -n "$BASELINE_WORKFLOW_COUNT" ] && [ "$BASELINE_WORKFLOW_COUNT" != "null" ]; then
    if [ "$count" -lt "$BASELINE_WORKFLOW_COUNT" ]; then
      echo "Data loss detected: workflow count decreased from $BASELINE_WORKFLOW_COUNT to $count"
      return 1
    fi
  fi
  
  return 0
}
