#!/bin/bash
# n8n Test Runner - Phase 1 MVP

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load common functions
source lib/common.sh

# Parse arguments
MODE="update"
PHASE="pre-update"

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    --phase=*)
      PHASE="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 --mode=<update|health-check> [--phase=<pre-update|post-update>]"
      exit 1
      ;;
  esac
done

# Load configuration
CONFIG_FILE="${TEST_CONFIG:-config.yaml}"
load_config "$CONFIG_FILE"

# Create state and results directories if they don't exist
mkdir -p "$STATE_DIR" results

# Initialize results
init_results "$MODE"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         n8n Automated Testing - Phase 1 MVP               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Mode:${NC}  $MODE"
echo -e "${BLUE}Phase:${NC} $PHASE"
echo -e "${BLUE}n8n URL:${NC} $N8N_URL"
echo ""

# Load test libraries
source lib/inf-tests.sh
source lib/net-tests.sh
source lib/web-tests.sh
source lib/db-tests.sh
source lib/api-tests.sh
source lib/wf-tests.sh
source lib/cred-tests.sh
source lib/perf-tests.sh
source lib/bkp-tests.sh
source lib/sec-tests.sh

# Phase 1: Infrastructure Tests (CRITICAL - stop if any fail)
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 1: Infrastructure Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

run_test "INF-001" "n8n Container Running" "test_inf_001_container_running" "P0" "CRITICAL" || exit 1
run_test "INF-002" "Container Uptime Stability" "test_inf_002_container_uptime" "P0" "CRITICAL"
run_test "INF-003" "PostgreSQL Health" "test_inf_003_postgres_health" "P0" "CRITICAL" || exit 1
run_test "INF-004" "Network Connectivity" "test_inf_004_network_connectivity" "P0" "CRITICAL" || exit 1
run_test "INF-005" "Volume Mounts" "test_inf_005_volume_mounts" "P1" "HIGH"
run_test "INF-006" "Resource Usage" "test_inf_006_resource_usage" "P2" "MEDIUM"

# Phase 2: Network & Web Tests
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 2: Network & Web Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

run_test "NET-001" "HTTP Port Accessible" "test_net_001_http_accessible" "P0" "CRITICAL" || exit 1
run_test "WEB-003" "Healthcheck Endpoint" "test_web_003_healthcheck" "P0" "CRITICAL" || exit 1

# Phase 3: Database & API Tests
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 3: Database & API Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

run_test "DB-001" "Database Query" "test_db_001_query" "P0" "CRITICAL" || exit 1

run_test "API-001" "List Workflows" "test_api_001_list_workflows" "P0" "CRITICAL" || exit 1

# Phase 4: Workflow Tests (non-critical - workflows may not be imported yet)
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 4: Workflow Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

run_test "WF-001" "Basic Webhook Test" "test_wf_001_webhook" "P1" "HIGH"

# Phase 5: Credential Tests (non-critical - workflows may not be imported yet)
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 5: Credential Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

run_test "CRED-001" "Credential Decryption" "test_cred_001_decryption" "P1" "HIGH"

# Phase 6: Performance Tests (non-critical)
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 6: Performance Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

run_test "PERF-001" "Response Time Check" "test_perf_001_response_time" "P1" "HIGH"

# Phase 7: Security Tests
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}Phase 7: Security Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""

run_test "SEC-001" "Security Headers" "test_sec_001_security_headers" "P1" "HIGH"
run_test "SEC-002" "Unauthenticated Access Prevention" "test_sec_002_unauthenticated_access" "P1" "HIGH"
run_test "SEC-003" "Container Security Configuration" "test_sec_003_container_security" "P1" "HIGH"
run_test "SEC-004" "Environment Variables Integrity" "test_sec_004_env_vars" "P1" "HIGH"
run_test "SEC-005" "Credential Encryption Check" "test_sec_005_credential_encryption" "P0" "CRITICAL"

# Phase 8: Backup Tests (only in update mode, pre-update phase)
if [ "$MODE" == "update" ] && [ "$PHASE" == "pre-update" ]; then
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}Phase 8: Backup Tests${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
  echo ""
  
  run_test "BKP-001" "Backup Verification" "test_bkp_001_verification" "P0" "CRITICAL" || exit 1
fi

# Finalize results
finalize_results

# Print summary
echo ""
print_summary
TEST_EXIT_CODE=$?

# Save or load baseline
if [ "$PHASE" == "pre-update" ]; then
  echo ""
  save_baseline
elif [ "$PHASE" == "post-update" ]; then
  echo ""
  if load_baseline; then
    echo ""
    make_rollback_decision
    ROLLBACK_EXIT_CODE=$?
    
    # If rollback needed, exit with code 2
    if [ $ROLLBACK_EXIT_CODE -ne 0 ]; then
      exit 2
    fi
  fi
fi

# Exit with test result code
exit $TEST_EXIT_CODE
