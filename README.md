# n8n CI/CD Testing Setup

Automated testing environment for n8n workflows with separate dev and test instances.

## Architecture

- **n8n-dev** (port 5678): Development environment for creating and testing workflows
- **n8n-test** (port 5679): Isolated test environment for CI/CD validation
- Separate PostgreSQL databases for each environment
- Persistent encryption keys to maintain API key validity across restarts

## Prerequisites

- Docker and Docker Compose
- `jq` for JSON parsing
  - **Windows (PowerShell)**: `choco install jq` or download from https://jqlang.github.io/jq/
  - **WSL/Linux**: `sudo apt-get install jq`
  - **macOS**: `brew install jq`
- `curl` (usually pre-installed)

## Quick Start

### 1. Start the environments

```bash
# Start dev environment
cd docker
docker-compose -f docker-compose.dev.yml up -d

# Start test environment
docker-compose -f docker-compose.test.yml up -d
```

### 2. Set up API keys

**Dev environment:**
1. Go to http://localhost:5678
2. Login with `admin` / `admin123`
3. Go to Settings → API → Create API key
4. Export the key:

**PowerShell:**
```powershell
$env:N8N_DEV_API_KEY='your-dev-api-key-here'
```

**Bash/WSL:**
```bash
export N8N_DEV_API_KEY='your-dev-api-key-here'
```

**Test environment:**
1. Go to http://localhost:5679
2. Set up owner account
3. Go to Settings → API → Create API key
4. Export the key:

**PowerShell:**
```powershell
$env:N8N_TEST_API_KEY='your-test-api-key-here'
```

**Bash/WSL:**
```bash
export N8N_TEST_API_KEY='your-test-api-key-here'
```

### 3. Export workflows from dev

**PowerShell:**
```powershell
cd scripts
.\export-workflows.ps1
```

**Bash/WSL:**
```bash
cd scripts
./export-workflows.sh
```

### 4. Import workflows to test

**PowerShell:**
```powershell
.\import-workflows.ps1 test
```

**Bash/WSL:**
```bash
./import-workflows.sh test
```

### 5. Run tests

**PowerShell:**
```powershell
.\run-tests.ps1
```

**Bash/WSL:**
```bash
./run-tests.sh
```

## CI/CD Workflow

1. **Develop**: Create workflows in n8n-dev (http://localhost:5678)
2. **Export**: Run `export-workflows.sh` to save workflows as JSON
3. **Commit**: Commit workflow JSON files to git
4. **Import**: CI pipeline imports workflows to n8n-test
5. **Test**: CI pipeline runs automated tests
6. **Deploy**: If tests pass, deploy to production

## Environment Variables

- `N8N_DEV_API_KEY`: API key for dev environment (port 5678)
- `N8N_TEST_API_KEY`: API key for test environment (port 5679)
- `N8N_DEV_HOST`: Dev host URL (default: http://localhost:5678)
- `N8N_TEST_HOST`: Test host URL (default: http://localhost:5679)

## Important Notes

- **Encryption keys are fixed** in docker-compose files to prevent API key invalidation on restart
- Each environment has its own database and API keys
- API keys are environment-specific and cannot be shared between dev and test
- The test environment is recreated fresh for each CI run

## Troubleshooting

**"unauthorized" error:**
- Make sure you've exported the correct API key for the environment
- Verify the API key was created in the correct instance (check the port)
- If you restart containers, API keys remain valid (encryption keys are fixed)

**"Cannot connect to n8n":**
- Check if containers are running: `docker ps`
- Check logs: `docker logs n8n-dev` or `docker logs n8n-test`
- Verify ports 5678 and 5679 are not in use by other applications

**Workflows not importing:**
- Ensure workflows were exported first: `ls ../workflows/`
- Check API key is set: `echo $N8N_TEST_API_KEY`
- Verify n8n-test is running and accessible
