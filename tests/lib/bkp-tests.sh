#!/bin/bash
# Backup Tests

test_bkp_001_verification() {
  # Check if backup directory exists
  if [ ! -d "$BACKUP_DIR" ]; then
    echo "Backup directory does not exist: $BACKUP_DIR"
    return 1
  fi
  
  # Find the most recent backup manifest
  local latest_manifest=$(ls -t "$BACKUP_DIR"/manifest_*.json 2>/dev/null | head -n1)
  
  if [ -z "$latest_manifest" ]; then
    echo "No backup manifest found in $BACKUP_DIR"
    return 1
  fi
  
  # Parse manifest
  local db_backup=$(jq -r '.database_backup' "$latest_manifest")
  local backup_tag=$(jq -r '.backup_tag' "$latest_manifest")
  
  # Verify database backup exists and is valid
  if [ ! -f "$BACKUP_DIR/$db_backup" ]; then
    echo "Database backup file not found: $db_backup"
    return 1
  fi
  
  # Verify it's a valid gzip file
  if ! gzip -t "$BACKUP_DIR/$db_backup" 2>/dev/null; then
    echo "Database backup is not a valid gzip file"
    return 1
  fi
  
  # Verify Docker image backup exists
  if ! docker image inspect "$backup_tag" > /dev/null 2>&1; then
    echo "Backup Docker image not found: $backup_tag"
    return 1
  fi
  
  return 0
}
