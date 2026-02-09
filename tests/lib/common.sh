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

# Load configuration
load_config() {
  local config_file="$1"
  
  if [ ! -f "$config_file" ]; then
    echo -e "${RED}ERROR: Config file not found: $config_file${NC}"
    exit 1
  fi
  
  # Parse YAML and export as environment variables
  # Simple parsing for Phase 1 - just extract key values
  export N8N_URL=$(grep "url:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"')
  export N8N_CONTAINER=$(grep "container_name:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"')
  export POSTGRES_CONTAINER=$(grep "container_name:" "$config_file" | sed -n '2p' | awk '{print $2}' | tr -d '"')
  export DB_NAME=$(grep "db_name:" "$config_file" | awk '{print $2}' | tr -d '"')
  export DB_USER=$(grep "db_user:" "$config_file" | awk '{print $2}' | tr -d '"')
  export BACKUP_DIR=$(grep "directory:" "$config_file" | awk '{print $2}' | tr -d '"')
  export STATE_DIR=$(grep "state_directory:" "$config_file" | awk '{print $2}' | tr -d '"')
  
  # Bypass proxy for localhost
  export no_proxy="localhost,127.0.0.1"
  export NO_PROXY="localhost,127.0.0.1"
}

# Run a test and record result
run_test() {
  local test_id="$1"
  local test_name="$2"
  local test_function="$3"
  local priority="$4"        # P0, P1, P2
  local criticality="$5"     # CRITICAL, HIGH, MEDIUM
  
  echo -e "${YELLOW}Running: $test_id - $test_name${NC}"
  ((TOTAL_TESTS++))
  
  local start_time=$(date +%s%3N)
  local status="pass"
  local error_msg=""
  local temp_output="/tmp/n8n_test_output_$$_${test_id}.txt"
  
  # Temporarily disable exit-on-error for test execution
  set +e
  
  # Run the test function and capture output to temp file
  $test_function > "$temp_output" 2>&1
  local test_result=$?
  
  if [ $test_result -eq 0 ]; then
    status="pass"
    ((PASSED_TESTS++))
    echo -e "${GREEN}✅ PASS${NC} - $test_name"
  else
    status="fail"
    error_msg=$(cat "$temp_output" 2>/dev/null || echo "Test failed with no output")
    ((FAILED_TESTS++))
    
    # Check if critical
    if [ "$criticality" == "CRITICAL" ]; then
      ((CRITICAL_FAILED++))
      echo -e "${RED}❌ FAIL (CRITICAL)${NC} - $test_name"
      echo -e "${RED}   Error: $error_msg${NC}"
      echo -e "${RED}   Stopping all tests due to CRITICAL failure${NC}"
      rm -f "$temp_output"
      set -e  # Re-enable before returning
      return 1
    else
      echo -e "${RED}❌ FAIL${NC} - $test_name"
      echo -e "${RED}   Error: $error_msg${NC}"
    fi
  fi
  
  # Clean up temp file
  rm -f "$temp_output"
  
  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))
  
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
  "error": $(if [ -n "$error_msg" ]; then echo "\"$error_msg\""; else echo "null"; fi)
},
EOF
  
  # Re-enable exit-on-error after all processing
  set -e
  
  echo ""
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
  # Remove trailing comma from last test
  sed -i '$ s/,$//' "$RESULTS_FILE" 2>/dev/null || sed -i '' '$ s/,$//' "$RESULTS_FILE"
  
  cat >> "$RESULTS_FILE" <<EOF
  ],
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "critical_failed": $CRITICAL_FAILED,
    "failure_percentage": $(awk "BEGIN {printf \"%.2f\", ($FAILED_TESTS / $TOTAL_TESTS) * 100}")
  }
}
EOF
  
  # Create symlink to latest
  ln -sf "$(basename "$RESULTS_FILE")" "$STATE_DIR/../results/latest.json"
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
    echo -e "${GREEN}✅ All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}❌ $FAILED_TESTS test(s) failed${NC}"
    return 1
  fi
}

# Save baseline
save_baseline() {
  local baseline_file="$STATE_DIR/baseline.json"
  
  # Get current metrics
  local workflow_count=$(docker exec "$POSTGRES_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM workflow_entity;" 2>/dev/null | tr -d ' ' || echo "0")
  local memory_mb=$(docker stats --no-stream --format "{{.MemUsage}}" "$N8N_CONTAINER" | awk '{print $1}' | sed 's/MiB//')
  
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
  
  echo -e "${GREEN}✅ Baseline saved to $baseline_file${NC}"
}

# Load baseline
load_baseline() {
  local baseline_file="$STATE_DIR/baseline.json"
  
  if [ ! -f "$baseline_file" ]; then
    echo -e "${YELLOW}⚠️  No baseline found${NC}"
    return 1
  fi
  
  # Export baseline values for comparison
  export BASELINE_WORKFLOW_COUNT=$(jq -r '.workflow_count' "$baseline_file")
  export BASELINE_MEMORY_MB=$(jq -r '.memory_usage_mb' "$baseline_file")
  export BASELINE_PASSED=$(jq -r '.test_results.passed' "$baseline_file")
  
  echo -e "${GREEN}✅ Baseline loaded from $baseline_file${NC}"
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
  
  # Check failure percentage
  local failure_pct=$(awk "BEGIN {printf \"%.0f\", ($FAILED_TESTS / $TOTAL_TESTS) * 100}")
  if [ $failure_pct -gt 30 ]; then
    needs_rollback=true
    reasons+=("Failure rate ${failure_pct}% > 30%")
  fi
  
  # Check memory increase (if baseline exists)
  if [ -n "$BASELINE_MEMORY_MB" ] && [ "$BASELINE_MEMORY_MB" != "null" ]; then
    local current_memory=$(docker stats --no-stream --format "{{.MemUsage}}" "$N8N_CONTAINER" | awk '{print $1}' | sed 's/MiB//')
    local memory_increase=$(awk "BEGIN {printf \"%.0f\", (($current_memory - $BASELINE_MEMORY_MB) / $BASELINE_MEMORY_MB) * 100}")
    
    if [ $memory_increase -gt 100 ]; then
      needs_rollback=true
      reasons+=("Memory increase ${memory_increase}% > 100%")
    fi
  fi
  
  # Output decision
  if [ "$needs_rollback" = true ]; then
    echo -e "${RED}🔄 ROLLBACK REQUIRED${NC}"
    echo -e "${RED}Reasons:${NC}"
    for reason in "${reasons[@]}"; do
      echo -e "${RED}  - $reason${NC}"
    done
    return 1
  else
    echo -e "${GREEN}✅ UPDATE SUCCESSFUL - No rollback needed${NC}"
    return 0
  fi
}
