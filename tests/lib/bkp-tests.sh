#!/bin/bash
# Backup Tests

test_bkp_001_verification() {
  # Check if backup directory exists
  if [ ! -d "$BACKUP_DIR" ]; then
    echo "Backup directory does not exist: $BACKUP_DIR"
    return 1
  fi
  
  # Find the most recent backup directory (format: YYYYMMDD_HHMMSS)
  local latest_backup=$(ls -t "$BACKUP_DIR" 2>/dev/null | grep -E '^[0-9]{8}_[0-9]{6}$' | head -n1)
  
  if [ -z "$latest_backup" ]; then
    echo "No backup found in $BACKUP_DIR"
    return 1
  fi
  
  local backup_path="$BACKUP_DIR/$latest_backup"
  
  # Check if manifest exists
  if [ ! -f "$backup_path/manifest.json" ]; then
    echo "Backup manifest not found in $backup_path"
    return 1
  fi
  
  # Parse manifest
  local backup_tag=$(jq -r '.image_tag' "$backup_path/manifest.json" 2>/dev/null)
  
  # Verify database backup exists
  if [ ! -f "$backup_path/database.sql.gz" ]; then
    echo "Database backup file not found in $backup_path"
    return 1
  fi
  
  # Verify it's a valid gzip file
  if ! gzip -t "$backup_path/database.sql.gz" 2>/dev/null; then
    echo "Database backup is not a valid gzip file"
    return 1
  fi
  
  # Verify Docker image backup exists (if tag is available)
  if [ -n "$backup_tag" ] && [ "$backup_tag" != "null" ]; then
    if ! docker image inspect "$backup_tag" > /dev/null 2>&1; then
      echo "Backup Docker image not found: $backup_tag"
      return 1
    fi
  fi
  
  return 0
}
