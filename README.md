# n8n Automated Testing & Update System

Automated testing, update management, and rollback system for n8n enterprise deployments. Runs 15 tests across 10 categories, with automatic rollback on failure and email notifications.

## Quick Start

```bash
# Run all tests (starts environment, imports workflows, runs tests)
./test.sh
```

## Prerequisites

- Docker and Docker Compose
- `curl` and `jq`
- Git (for CI/CD pipelines)
- A self-hosted GitHub Actions runner (for CI/CD pipelines)

## Project Structure

```
.
├── test.sh                        # One-command entry point
├── docker/
│   ├── docker-compose.test.yml    # Test environment (port 5679)
│   ├── docker-compose.dev.yml     # Dev environment (port 5678)
│   └── .env.test                  # Test env vars (gitignored secrets)
├── scripts/                       # Automation scripts
│   ├── run-full-test.sh           # Full automated test run
│   ├── quick-test.sh              # Quick health check
│   ├── start-test-env.sh          # Start Docker containers
│   ├── stop-test-env.sh           # Stop Docker containers
│   ├── import-test-workflows.sh   # Import workflows via API
│   ├── backup.sh                  # Create backup
│   ├── update.sh                  # Apply n8n update
│   ├── rollback.sh                # Restore from backup
│   └── ...                        # See scripts/README.md
├── tests/
│   ├── runner.sh                  # Main test runner
│   ├── config.yaml                # Test configuration
│   └── lib/                       # Test libraries (10 categories)
├── workflows/                     # n8n test workflow JSON files
│   ├── test-health-webhook.json
│   ├── test-echo-webhook.json
│   ├── test-http-request.json
│   └── test-credential.json
├── .github/workflows/             # CI/CD pipelines
│   ├── update-pipeline.yml        # Automated update with rollback
│   ├── health-check-pipeline.yml  # Scheduled health monitoring
│   └── test-workflows.yml         # CI testing on push/PR
├── docs/                          # Additional documentation
└── n8n_testing_requirements.md    # Full requirements spec (65 tests)
```

## Environments

| Environment | Port  | Container      | Database            | Purpose                    |
|-------------|-------|----------------|---------------------|----------------------------|
| Test        | 5679  | `n8n-test`     | `n8n-postgres-test` | Automated testing          |
| Dev         | 5678  | `n8n-dev`      | `n8n-postgres-dev`  | Workflow development       |

Both use PostgreSQL 15 and persistent encryption keys for credential stability.

## Tests

15 tests across 10 categories. Tests run in phases; critical failures stop subsequent phases.

| ID       | Category       | Test                        | Priority   |
|----------|----------------|-----------------------------|------------|
| INF-001  | Infrastructure | Container running            | P0 CRITICAL |
| INF-002  | Infrastructure | Container uptime stability   | P0 CRITICAL |
| INF-003  | Infrastructure | PostgreSQL health            | P0 CRITICAL |
| INF-004  | Infrastructure | Docker network connectivity  | P0 CRITICAL |
| INF-005  | Infrastructure | Volume mounts                | P1 HIGH    |
| INF-006  | Infrastructure | Resource usage               | P2 MEDIUM  |
| NET-001  | Network        | HTTP port accessible         | P0 CRITICAL |
| WEB-003  | Web            | Healthcheck endpoint         | P0 CRITICAL |
| DB-001   | Database       | Database query               | P0 CRITICAL |
| API-001  | API            | List workflows               | P0 CRITICAL |
| WF-001   | Workflow       | Webhook execution            | P0 CRITICAL |
| CRED-001 | Credential     | Credential decryption        | P0 CRITICAL |
| PERF-001 | Performance    | Response time                | P1 HIGH    |
| SEC-001  | Security       | Security headers/config      | P1 HIGH    |
| BKP-001  | Backup         | Backup verification          | P0 CRITICAL |

### Running Tests

```bash
# Full automated test (starts env, imports workflows, runs tests)
./test.sh

# Or step by step:
cd scripts
./start-test-env.sh
./import-test-workflows.sh    # requires N8N_TEST_API_KEY
cd ../tests
./runner.sh --mode=health-check

# Quick test (environment already running)
cd scripts && ./quick-test.sh
```

### Test Results

Results are saved to `tests/results/`:

```bash
cat tests/results/test_report_*.json | jq '.summary'
```

## Backup, Update & Rollback

```bash
cd scripts

# Create backup (saves Docker image tag, database dump, volume tarball)
./backup.sh
# Note the timestamp, e.g. 20260216_143000

# Update n8n
./update.sh latest          # or a specific version like 1.30.0

# Rollback if needed
./rollback.sh 20260216_143000
```

### Rollback Triggers

Automatic rollback occurs when any of these conditions are met:
- Any P0 (CRITICAL) test fails
- More than 30% of tests fail
- Average response time increases >50%
- Memory usage increases >100%

## CI/CD Pipelines (GitHub Actions)

All pipelines require a self-hosted runner with Docker access on the same machine as n8n.

### Update Pipeline (`update-pipeline.yml`)

Trigger manually from **Actions > n8n Update Pipeline > Run workflow**. Enter a target version (`latest` or `1.30.0`).

Flow: backup > pre-update tests > update > post-update tests > rollback if failed > email notification.

### Health Check Pipeline (`health-check-pipeline.yml`)

Trigger manually or enable scheduled runs by uncommenting the cron schedule:

```yaml
on:
  schedule:
    - cron: '0 8 * * *'  # Daily at 8 AM UTC
```

### Test Workflows Pipeline (`test-workflows.yml`)

Runs automatically on push/PR to `main`.

### Required GitHub Secrets

| Secret                     | Purpose                      |
|----------------------------|------------------------------|
| `N8N_TEST_API_KEY`         | n8n API key (for workflow import) |
| `N8N_DB_PASSWORD`          | PostgreSQL password           |
| `SMTP_HOST`                | Email server hostname         |
| `SMTP_USER`                | Email username                |
| `SMTP_PASSWORD`            | Email password                |
| `NOTIFICATION_RECIPIENTS`  | Comma-separated email list    |

## Configuration

Edit `tests/config.yaml` for:
- n8n URL and container names
- PostgreSQL connection details
- Rollback thresholds
- Backup directory and retention
- Feature flags (HTTPS, proxy, etc.)
- Notification settings

## Troubleshooting

### Container not starting

```bash
docker logs n8n-test --tail 50
docker restart n8n-test

# Full reset
cd docker
docker-compose -f docker-compose.test.yml down -v
docker-compose -f docker-compose.test.yml up -d
```

### Tests failing

```bash
docker ps | grep n8n
docker exec n8n-postgres-test pg_isready -U n8n
docker logs n8n-test --tail 100
```

### Workflow import not working

Import manually through the n8n UI at `http://localhost:5679` using files from the `workflows/` directory. See `docs/API-KEY-SETUP.md` for API key configuration.

### Corporate proxy

```bash
export NO_PROXY="localhost,127.0.0.1"
```

## Documentation

| File | Description |
|------|-------------|
| `n8n_testing_requirements.md` | Full requirements spec (65 planned tests) |
| `docs/API-KEY-SETUP.md` | API key configuration guide |
| `docs/UPDATE-PIPELINE-TESTING.md` | How to test the update pipeline |
| `docs/UPDATE-ROLLBACK-TEST-SCENARIOS.md` | Rollback test scenarios |
| `scripts/README.md` | Script reference |
| `tests/README.md` | Test framework reference |
