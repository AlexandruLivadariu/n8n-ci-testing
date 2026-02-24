# Scripts Reference

## Automated Test Scripts

| Script | Description |
|--------|-------------|
| `run-full-test.sh` | Full automated test: starts environment, imports workflows, runs all tests |
| `quick-test.sh` | Quick health check against an already-running environment |

## Environment Management

| Script | Description |
|--------|-------------|
| `start-test-env.sh` | Start test containers (n8n + PostgreSQL) and wait until healthy |
| `stop-test-env.sh` | Stop test containers |
| `reset-n8n.sh` | Reset n8n to a clean state |

## Workflow Management

| Script | Description |
|--------|-------------|
| `import-test-workflows.sh` | Import test workflows via n8n API (requires `N8N_TEST_API_KEY`) |
| `import-workflows.sh` | Alternative workflow import |
| `import-workflows-cli.sh` | Import workflows via CLI |
| `export-workflows.sh` | Export workflows from n8n |
| `cleanup-workflows.sh` | Remove test workflows from n8n |
| `seed-workflows.sh` | Seed workflows into n8n |

## Update & Maintenance

| Script | Description |
|--------|-------------|
| `backup.sh` | Create backup (Docker image tag + DB dump + volume tarball) |
| `update.sh` | Update n8n to a specified version |
| `rollback.sh` | Restore from a timestamped backup |

## Testing & Debugging

| Script | Description |
|--------|-------------|
| `run-tests.sh` | Run test suite directly |
| `test-webhooks.sh` | Test webhook endpoints (works without API key) |
| `test-api.sh` | Test API endpoints |
| `test-api-key.sh` | Verify API key is working |
| `test-update-pipeline.sh` | Test the update pipeline locally |
| `manual-update-test.sh` | Interactive update testing |
| `demo-update-rollback.sh` | Demo the update/rollback cycle |

## Shared Libraries

| File | Description |
|------|-------------|
| `lib/common-lib.sh` | Shared utility functions |

## Usage

```bash
# Full automated test (recommended starting point)
cd scripts
./run-full-test.sh

# Quick health check
./quick-test.sh

# Manual update cycle
./backup.sh
./update.sh latest
./rollback.sh 20260216_143000   # if needed
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `N8N_TEST_API_KEY` | For workflow import | n8n API key |
| `N8N_HOST` | No (default: `http://localhost:5679`) | n8n URL |
| `N8N_DB_PASSWORD` | No (default in compose) | PostgreSQL password |
| `NO_PROXY` | Corporate environments | Set to `localhost,127.0.0.1` |
