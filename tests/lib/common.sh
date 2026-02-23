#!/bin/bash
# Common functions for n8n testing

# Colors
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Test counters
export TOTAL_TESTS=0
export PASSED_TESTS=0
export FAILED_TESTS=0
export CRITICAL_FAILED=0

# Track whether this is first test result (for JSON comma handling)
export FIRST_TEST_RESULT=true

# Load shared library for config parsing (if available)
_TESTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SHARED_LIB="$_TESTS_LIB_DIR/../../scripts/lib/common-lib.sh"
if [ -f "$_SHARED_LIB" ]; then
  source "$_SHARED_LIB"
fi

# Load configuration
load_config() {
  local config_file="$1"

  if [ ! -f "$config_file" ]; then
    echo -e "${RED}ERROR: Config file not found: $config_file${NC}"
    exit 1
  fi

  # Use shared yaml_get if available, otherwise fall back to awk
  if type yaml_get &>/dev/null; then
    export N8N_URL=$(yaml_get "$config_file" "n8n" "url")
    export N8N_CONTAINER=$(yaml_get "$config_file" "n8n" "container_name")
    export POSTGRES_CONTAINER=$(yaml_get "$config_file" "postgres" "container_name")
    export DB_NAME=$(yaml_get "$config_file" "postgres" "db_name")
    export DB_USER=$(yaml_get "$config_file" "postgres" "db_user")
    export BACKUP_DIR=$(yaml_get "$config_file" "backup" "directory")
    export STATE_DIR=$(yaml_get "$config_file" "" "state_directory")
  else
    # Fallback: parse YAML using section-aware awk extraction
    export N8N_URL=$(awk '/^n8n:/{found=1} found && /url:/{print $2; exit}' "$config_file" | tr -d '"' | tr -d "'" | tr -d '\r')
    export N8N_CONTAINER=$(awk '/^n8n:/{found=1} found && /container_name:/{print $2; exit}' "$config_file" | tr -d '"' | tr -d "'" | tr -d '\r')
    export POSTGRES_CONTAINER=$(awk '/^postgres:/{found=1} found && /container_name:/{print $2; exit}' "$config_file" | tr -d '"' | tr -d "'" | tr -d '\r')
    export DB_NAME=$(awk '/^postgres:/{found=1} found && /db_name:/{print $2; exit}' "$config_file" | tr -d '"' | tr -d "'" | tr -d '\r')
    export DB_USER=$(awk '/^postgres:/{found=1} found && /db_user:/{print $2; exit}' "$config_file" | tr -d '"' | tr -d "'" | tr -d '\r')
    export BACKUP_DIR=$(awk '/^backup:/{found=1} found && /directory:/{print $2; exit}' "$config_file" | tr -d '"' | tr -d "'" | tr -d '\r')
    export STATE_DIR=$(awk '/^state_directory:/{print $2; exit}' "$config_file" | tr -d '"' | tr -d "'" | tr -d '\r')
  fi

  # Export N8N_HOST as alias for N8N_URL (used by security tests)
  export N8N_HOST="$N8N_URL"

  # Bypass proxy for localhost
  export no_proxy="localhost,127.0.0.1"
  export NO_PROXY="localhost,127.0.0.1"
}

# Escape a string for safe JSON embedding
json_escape() {
  local str="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$str" | jq -R -s '.'
  else
    # Fallback: escape backslashes, quotes, and newlines
    printf '"%s"' "$(printf '%s' "$str" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')"
  fi
}

# Run a test and record result
run_test() {
  local test_id="$1"
  local test_name="$2"
  local test_function="$3"
  local priority="$4"        # P0, P1, P2
  local criticality="$5"     # CRITICAL, HIGH, MEDIUM

  echo -e "${YELLOW}Running: $test_id - $test_name${NC}"
  TOTAL_TESTS=$((TOTAL_TESTS + 1))

  local start_time=$(date +%s%3N)
  local status="pass"
  local error_msg=""
  local temp_output="/tmp/n8n_test_output_$$_${test_id}.txt"
  local is_critical_fail=false

  # Run in subshell to avoid set -e issues in the caller
  (
    set +e
    $test_function > "$temp_output" 2>&1
    exit $?
  )
  local test_result=$?

  if [ $test_result -eq 0 ]; then
    status="pass"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "${GREEN}PASS${NC} - $test_name"
  else
    status="fail"
    error_msg=$(cat "$temp_output" 2>/dev/null || echo "Test failed with no output")
    FAILED_TESTS=$((FAILED_TESTS + 1))

    if [ "$criticality" == "CRITICAL" ]; then
      CRITICAL_FAILED=$((CRITICAL_FAILED + 1))
      is_critical_fail=true
      echo -e "${RED}FAIL (CRITICAL)${NC} - $test_name"
      echo -e "${RED}   Error: $error_msg${NC}"
      echo -e "${RED}   Stopping all tests due to CRITICAL failure${NC}"
    else
      echo -e "${RED}FAIL${NC} - $test_name"
      echo -e "${RED}   Error: $error_msg${NC}"
    fi
  fi

  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))

  # Build JSON error value with proper escaping
  local error_json="null"
  if [ -n "$error_msg" ]; then
    error_json=$(json_escape "$error_msg")
  fi

  # Write comma before entry (except the first one)
  if [ "$FIRST_TEST_RESULT" = true ]; then
    FIRST_TEST_RESULT=false
  else
    printf ',\n' >> "$RESULTS_FILE"
  fi

  # Record result in JSON format
  cat >> "$RESULTS_FILE" <<EOF
{
  "test_id": "$test_id",
  "name": "$test_name",
  "status": "$status",
  "priority": "$priority",
  "criticality": "$criticality",
  "duration_ms": $duration,
  "timestamp": "$(date -Iseconds)",
  "error": $error_json
}
EOF

  # Clean up temp file
  rm -f "$temp_output"

  echo ""

  if [ "$is_critical_fail" = true ]; then
    return 1
  fi
  return 0
}

# Initialize results file
init_results() {
  local mode="$1"

  # Get the script directory (tests/)
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  # Create results directory if it doesn't exist
  mkdir -p "$script_dir/results"

  export RESULTS_FILE="$script_dir/results/test_report_$(date +%Y%m%d_%H%M%S).json"

  cat > "$RESULTS_FILE" <<EOF
{
  "pipeline": "$mode",
  "timestamp": "$(date -Iseconds)",
  "n8n_version": "unknown",
  "tests": [
EOF
}

# Finalize results file
finalize_results() {
  # Calculate failure percentage (guard against division by zero)
  local failure_pct="0.00"
  if [ "$TOTAL_TESTS" -gt 0 ]; then
    failure_pct=$(awk "BEGIN {printf \"%.2f\", ($FAILED_TESTS / $TOTAL_TESTS) * 100}")
  fi

  cat >> "$RESULTS_FILE" <<EOF
  ],
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "critical_failed": $CRITICAL_FAILED,
    "failure_percentage": $failure_pct
  }
}
EOF

  # Create symlink to latest
  local results_dir
  results_dir="$(dirname "$RESULTS_FILE")"
  ln -sf "$(basename "$RESULTS_FILE")" "$results_dir/latest.json" 2>/dev/null || true
}

# Print summary
print_summary() {
  echo "================================"
  echo -e "${BLUE}Test Summary${NC}"
  echo "  Total:            $TOTAL_TESTS"
  echo -e "  ${GREEN}Passed:           $PASSED_TESTS${NC}"
  echo -e "  ${RED}Failed:           $FAILED_TESTS${NC}"
  echo -e "  ${RED}Critical Failed:  $CRITICAL_FAILED${NC}"
  echo ""

  if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}$FAILED_TESTS test(s) failed${NC}"
    return 1
  fi
}

# Save baseline
save_baseline() {
  local baseline_file="$STATE_DIR/baseline.json"

  # Get current metrics
  local workflow_count=$(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null | tr -d ' ' || echo "0")
  # Parse memory usage, handling both MiB and GiB units
  local raw_memory=$(docker stats --no-stream --format "{{.MemUsage}}" "$N8N_CONTAINER" | awk '{print $1}')
  local memory_mb
  if echo "$raw_memory" | grep -qi "GiB"; then
    memory_mb=$(echo "$raw_memory" | sed 's/[Gg][Ii][Bb]//' | awk '{printf "%.0f", $1 * 1024}')
  else
    memory_mb=$(echo "$raw_memory" | sed 's/[Mm][Ii][Bb]//')
  fi

  cat > "$baseline_file" <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "n8n_version": "$(docker exec "$N8N_CONTAINER" n8n --version 2>/dev/null || echo 'unknown')",
  "workflow_count": $workflow_count,
  "memory_usage_mb": ${memory_mb:-0},
  "test_results": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS
  }
}
EOF

  echo -e "${GREEN}Baseline saved to $baseline_file${NC}"
}

# Load baseline
load_baseline() {
  local baseline_file="$STATE_DIR/baseline.json"

  if [ ! -f "$baseline_file" ]; then
    echo -e "${YELLOW}No baseline found${NC}"
    return 1
  fi

  # Export baseline values for comparison
  export BASELINE_WORKFLOW_COUNT=$(jq -r '.workflow_count' "$baseline_file")
  export BASELINE_MEMORY_MB=$(jq -r '.memory_usage_mb' "$baseline_file")
  export BASELINE_PASSED=$(jq -r '.test_results.passed' "$baseline_file")

  echo -e "${GREEN}Baseline loaded from $baseline_file${NC}"
  return 0
}

# Make rollback decision
make_rollback_decision() {
  local needs_rollback=false
  local reasons=()

  # Check critical failures
  if [ $CRITICAL_FAILED -gt 0 ]; then
    needs_rollback=true
    reasons+=("Critical test failure")
  fi

  # Check failure percentage (guard against division by zero)
  if [ "$TOTAL_TESTS" -gt 0 ]; then
    local failure_pct=$(awk "BEGIN {printf \"%.0f\", ($FAILED_TESTS / $TOTAL_TESTS) * 100}")
    if [ "$failure_pct" -gt 30 ]; then
      needs_rollback=true
      reasons+=("Failure rate ${failure_pct}% > 30%")
    fi
  fi

  # Check memory increase (if baseline exists)
  if [ -n "$BASELINE_MEMORY_MB" ] && [ "$BASELINE_MEMORY_MB" != "null" ] && [ "$BASELINE_MEMORY_MB" != "0" ]; then
    # Parse memory usage, handling both MiB and GiB units
    local raw_mem=$(docker stats --no-stream --format "{{.MemUsage}}" "$N8N_CONTAINER" | awk '{print $1}')
    local current_memory
    if echo "$raw_mem" | grep -qi "GiB"; then
      current_memory=$(echo "$raw_mem" | sed 's/[Gg][Ii][Bb]//' | awk '{printf "%.0f", $1 * 1024}')
    else
      current_memory=$(echo "$raw_mem" | sed 's/[Mm][Ii][Bb]//')
    fi
    if [ -n "$current_memory" ]; then
      local memory_increase=$(awk "BEGIN {printf \"%.0f\", (($current_memory - $BASELINE_MEMORY_MB) / $BASELINE_MEMORY_MB) * 100}")
      if [ "$memory_increase" -gt 100 ]; then
        needs_rollback=true
        reasons+=("Memory increase ${memory_increase}% > 100%")
      fi
    fi
  fi

  # Output decision
  if [ "$needs_rollback" = true ]; then
    echo -e "${RED}ROLLBACK REQUIRED${NC}"
    echo -e "${RED}Reasons:${NC}"
    for reason in "${reasons[@]}"; do
      echo -e "${RED}  - $reason${NC}"
    done
    return 1
  else
    echo -e "${GREEN}UPDATE SUCCESSFUL - No rollback needed${NC}"
    return 0
  fi
}
