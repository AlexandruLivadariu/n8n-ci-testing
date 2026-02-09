# n8n Automated Testing - Phase 1 MVP

## Directory Structure

```
tests/
├── config.yaml          # Configuration file
├── runner.sh            # Main test runner script
├── lib/                 # Test library scripts
│   ├── common.sh        # Common functions
│   ├── inf-tests.sh     # Infrastructure tests
│   ├── net-tests.sh     # Network tests
│   ├── web-tests.sh     # Web tests
│   ├── db-tests.sh      # Database tests
│   ├── api-tests.sh     # API tests
│   ├── wf-tests.sh      # Workflow tests
│   ├── cred-tests.sh    # Credential tests
│   ├── perf-tests.sh    # Performance tests
│   └── bkp-tests.sh     # Backup tests
├── state/               # Baseline and state files
│   ├── baseline.json    # Pre-update baseline
│   └── last_run.json    # Last test run results
├── results/             # Test results and reports
│   └── test_report.json # Latest test report
└── test-cases/          # Test case definitions
    └── webhook-tests.json
```

## Phase 1 Tests (10 tests)

1. **INF-001**: n8n Container Running
2. **INF-003**: PostgreSQL Health
3. **NET-001**: HTTP Port Accessible
4. **WEB-003**: Healthcheck Endpoint
5. **DB-001**: Database Query
6. **API-001**: List Workflows
7. **WF-001**: Basic Webhook Test
8. **CRED-001**: Credential Decryption
9. **PERF-001**: Response Time Check
10. **BKP-001**: Backup Verification

## Usage

```bash
# Run all tests
./runner.sh --mode=update

# Run health check subset
./runner.sh --mode=health-check

# Run with baseline comparison
./runner.sh --mode=update --phase=post-update
```

## Configuration

Edit `config.yaml` to set:
- n8n URL and container names
- PostgreSQL connection details
- Rollback thresholds
- Backup directory
- Notification settings

## Environment Variables Required

```bash
export N8N_TEST_API_KEY="your-api-key"
export N8N_DB_PASSWORD="your-db-password"
export SMTP_HOST="smtp.example.com"
export SMTP_USER="notifications@example.com"
export SMTP_PASSWORD="your-smtp-password"
export NOTIFICATION_RECIPIENTS="devops@example.com,oncall@example.com"
```
