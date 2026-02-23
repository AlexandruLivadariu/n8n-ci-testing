#!/bin/bash
# Shared library for all n8n automation scripts
# Source this file from backup.sh, update.sh, rollback.sh, etc.

# --- Colors ---
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# --- Config Parsing ---
# Resolves the default config file path relative to this library
_COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG_FILE="${_COMMON_LIB_DIR}/../../tests/config.yaml"

# Parse a YAML value from a section.
# Usage: yaml_get <file> <section> <key>
#   yaml_get config.yaml postgres db_name  => "n8n"
# For top-level keys (no section), pass "" as section:
#   yaml_get config.yaml "" state_directory => "state"
yaml_get() {
  local file="$1" section="$2" key="$3"
  if [ -z "$section" ]; then
    awk -v k="$key" '
      /^[a-zA-Z]/ && /:/ { current_section=$1; gsub(/:/, "", current_section) }
      $1 == k":" && current_section == k { print $2; exit }
    ' "$file" | tr -d '"' | tr -d "'" | tr -d '\r' | tr -d '\n'
  else
    awk -v s="$section" -v k="$key" '
      /^[a-zA-Z]/ && /:/ { current_section=$1; gsub(/:/, "", current_section) }
      current_section == s && $1 == k":" { print $2; exit }
    ' "$file" | tr -d '"' | tr -d "'" | tr -d '\r' | tr -d '\n'
  fi
}

# Load all standard config variables from a config file.
# Usage: load_script_config [config_file]
load_script_config() {
  local config_file="${1:-$DEFAULT_CONFIG_FILE}"

  if [ ! -f "$config_file" ]; then
    echo -e "${RED}Config file not found: ${config_file}${NC}"
    exit 1
  fi

  export N8N_CONTAINER=$(yaml_get "$config_file" "n8n" "container_name")
  export N8N_URL=$(yaml_get "$config_file" "n8n" "url")
  export POSTGRES_CONTAINER=$(yaml_get "$config_file" "postgres" "container_name")
  export DB_NAME=$(yaml_get "$config_file" "postgres" "db_name")
  export DB_USER=$(yaml_get "$config_file" "postgres" "db_user")
  export BACKUP_DIR="${N8N_BACKUP_DIR:-$(yaml_get "$config_file" "backup" "directory")}"
  export BACKUP_RETENTION_DAYS=$(yaml_get "$config_file" "backup" "retention_days")
  export BACKUP_MIN_RETAINED=$(yaml_get "$config_file" "backup" "min_retained_count")
  export STARTUP_TIMEOUT=$(yaml_get "$config_file" "thresholds" "container_startup_timeout_seconds")
  export STATE_DIR=$(yaml_get "$config_file" "" "state_directory")

  # Alias for tests
  export N8N_HOST="$N8N_URL"

  # Bypass proxy for localhost
  export no_proxy="localhost,127.0.0.1"
  export NO_PROXY="localhost,127.0.0.1"
}

# --- Docker Environment ---
# Returns the standard n8n Docker env args as an array.
# Usage: local args; get_docker_env_args args; docker run "${args[@]}" ...
get_docker_env_args() {
  local -n _env_ref=$1
  _env_ref=(
    -e "DB_TYPE=postgresdb"
    -e "DB_POSTGRESDB_HOST=n8n-postgres-test"
    -e "DB_POSTGRESDB_DATABASE=n8n"
    -e "DB_POSTGRESDB_USER=n8n"
    -e "DB_POSTGRESDB_PASSWORD=${N8N_DB_PASSWORD:-n8n_test_password}"
    -e "N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY:-test_encryption_key_min_10_chars}"
    -e "N8N_JWT_SECRET=${N8N_JWT_SECRET:-test_jwt_secret_key_min_10_chars}"
    -e "N8N_HOST=localhost"
    -e "WEBHOOK_URL=http://localhost:5679/"
  )
}

# Warn if default (insecure) secrets are being used.
warn_default_secrets() {
  local warned=false
  if [ -z "$N8N_DB_PASSWORD" ]; then
    echo -e "${YELLOW}WARNING: N8N_DB_PASSWORD not set, using insecure default${NC}"
    warned=true
  fi
  if [ -z "$N8N_ENCRYPTION_KEY" ]; then
    echo -e "${YELLOW}WARNING: N8N_ENCRYPTION_KEY not set, using insecure default${NC}"
    warned=true
  fi
  if [ -z "$N8N_JWT_SECRET" ]; then
    echo -e "${YELLOW}WARNING: N8N_JWT_SECRET not set, using insecure default${NC}"
    warned=true
  fi
  if [ "$warned" = true ]; then
    echo -e "${YELLOW}Set these environment variables for production use${NC}"
    echo ""
  fi
}

# --- Lock File ---
LOCK_DIR="/tmp/n8n-automation-locks"

# Acquire a named lock. Exits with error if lock is already held.
# Usage: acquire_lock "backup"
acquire_lock() {
  local name="$1"
  mkdir -p "$LOCK_DIR"
  local lock_file="$LOCK_DIR/${name}.lock"

  if [ -f "$lock_file" ]; then
    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null)
    # Check if the process holding the lock is still running
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      echo -e "${RED}Another ${name} operation is already running (PID: ${lock_pid})${NC}"
      exit 1
    else
      # Stale lock file - remove it
      echo -e "${YELLOW}Removing stale lock file for ${name}${NC}"
      rm -f "$lock_file"
    fi
  fi

  echo $$ > "$lock_file"
}

# Release a named lock.
# Usage: release_lock "backup"
release_lock() {
  local name="$1"
  rm -f "$LOCK_DIR/${name}.lock"
}

# --- Backup Retention ---
# Enforces backup retention policy: removes backups older than retention_days,
# but always keeps at least min_retained_count backups.
# Usage: enforce_backup_retention
enforce_backup_retention() {
  local retention_days="${BACKUP_RETENTION_DAYS:-30}"
  local min_retained="${BACKUP_MIN_RETAINED:-3}"
  local backup_dir="${BACKUP_DIR}"

  if [ ! -d "$backup_dir" ]; then
    return 0
  fi

  # List backups sorted newest-first (format: YYYYMMDD_HHMMSS)
  local all_backups
  all_backups=$(ls -1 "$backup_dir" 2>/dev/null | grep -E '^[0-9]{8}_[0-9]{6}$' | sort -r)
  local total_count
  total_count=$(echo "$all_backups" | grep -c . 2>/dev/null || echo "0")

  if [ "$total_count" -le "$min_retained" ]; then
    return 0
  fi

  local removed=0
  local kept=0
  local cutoff_ts
  cutoff_ts=$(date -d "-${retention_days} days" +%Y%m%d_%H%M%S 2>/dev/null || \
              date -v-${retention_days}d +%Y%m%d_%H%M%S 2>/dev/null || \
              echo "00000000_000000")

  while IFS= read -r backup_name; do
    [ -z "$backup_name" ] && continue
    kept=$((kept + 1))

    # Always keep at least min_retained
    if [ "$kept" -le "$min_retained" ]; then
      continue
    fi

    # Remove if older than retention cutoff
    if [[ "$backup_name" < "$cutoff_ts" ]]; then
      echo -e "${YELLOW}Removing old backup: ${backup_name}${NC}"
      rm -rf "${backup_dir}/${backup_name}"
      removed=$((removed + 1))
    fi
  done <<< "$all_backups"

  if [ "$removed" -gt 0 ]; then
    echo -e "${GREEN}Cleaned up ${removed} old backup(s)${NC}"
  fi
}
