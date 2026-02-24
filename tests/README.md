# Test Framework Reference

## Directory Structure

```
tests/
├── runner.sh          # Main test runner
├── config.yaml        # Test configuration
├── lib/
│   ├── common.sh      # Shared test utilities
│   ├── inf-tests.sh   # Infrastructure tests (INF-001 through INF-006)
│   ├── net-tests.sh   # Network tests (NET-001)
│   ├── web-tests.sh   # Web tests (WEB-003)
│   ├── db-tests.sh    # Database tests (DB-001)
│   ├── api-tests.sh   # API tests (API-001)
│   ├── wf-tests.sh    # Workflow tests (WF-001)
│   ├── cred-tests.sh  # Credential tests (CRED-001)
│   ├── perf-tests.sh  # Performance tests (PERF-001)
│   ├── sec-tests.sh   # Security tests (SEC-001)
│   └── bkp-tests.sh   # Backup tests (BKP-001)
├── results/           # Test reports (JSON)
└── state/             # Baseline and state files
```

## Tests (15 total)

| ID       | Category       | Test                        | Priority    |
|----------|----------------|-----------------------------|-------------|
| INF-001  | Infrastructure | Container running            | P0 CRITICAL |
| INF-002  | Infrastructure | Container uptime stability   | P0 CRITICAL |
| INF-003  | Infrastructure | PostgreSQL health            | P0 CRITICAL |
| INF-004  | Infrastructure | Docker network connectivity  | P0 CRITICAL |
| INF-005  | Infrastructure | Volume mounts                | P1 HIGH     |
| INF-006  | Infrastructure | Resource usage               | P2 MEDIUM   |
| NET-001  | Network        | HTTP port accessible         | P0 CRITICAL |
| WEB-003  | Web            | Healthcheck endpoint         | P0 CRITICAL |
| DB-001   | Database       | Database query               | P0 CRITICAL |
| API-001  | API            | List workflows               | P0 CRITICAL |
| WF-001   | Workflow       | Webhook execution            | P0 CRITICAL |
| CRED-001 | Credential     | Credential decryption        | P0 CRITICAL |
| PERF-001 | Performance    | Response time                | P1 HIGH     |
| SEC-001  | Security       | Security headers/config      | P1 HIGH     |
| BKP-001  | Backup         | Backup verification          | P0 CRITICAL |

## Usage

```bash
# Health check mode (runs all tests)
./runner.sh --mode=health-check

# Update mode - pre-update baseline
./runner.sh --mode=update --phase=pre-update

# Update mode - post-update validation
./runner.sh --mode=update --phase=post-update
```

## Configuration

Edit `config.yaml` to set:

- **n8n connection**: URL (`http://localhost:5679`), container name (`n8n-test`)
- **PostgreSQL**: container name, database, user
- **Rollback thresholds**: critical failure, failure %, response time %, memory %
- **Backup**: directory, retention days
- **Feature flags**: HTTPS, proxy, multi-instance
- **Test workflows**: names, webhook paths, source files

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `N8N_TEST_API_KEY` | API key for n8n API calls |
| `N8N_DB_PASSWORD` | PostgreSQL password |
| `NO_PROXY` | Bypass proxy for localhost |
