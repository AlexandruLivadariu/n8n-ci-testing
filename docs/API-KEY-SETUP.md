# API Key Setup Guide

## The Challenge: Masked API Keys

n8n's API key creation endpoint returns **masked keys** for security reasons. When you create an API key programmatically, the response looks like this:

```json
{
  "apiKey": "******saLM",
  "rawApiKey": "***"
}
```

This makes fully automated workflow import impossible in fresh CI/CD environments without manual intervention.

## Solution: Manual API Key Creation

For CI/CD pipelines, you need to create an API key manually once and store it as a secret.

### Step 1: Create API Key Through UI

1. **Start n8n locally:**
   ```bash
   cd docker
   docker-compose -f docker-compose.test.yml up -d
   ```

2. **Open n8n:** http://localhost:5679

3. **Complete owner setup** (if first time):
   - Email: `ci@test.local`
   - Password: `TestPassword123!`
   - First Name: `CI`
   - Last Name: `Test`

4. **Generate API Key:**
   - Click your user icon (bottom left)
   - Go to **Settings**
   - Click **n8n API** in the left menu
   - Click **Create an API key**
   - Label: "CI/CD Testing"
   - Scopes: Select all workflow scopes (or leave default for full access)
   - Expiration: 1 year or "Never"
   - **Copy the key immediately** - it's only shown once!

5. **Key Format:**
   - Modern n8n (v1.0+): JWT-style keys starting with `eyJ...`
   - Older versions: Keys starting with `n8n_api_...`

### Step 2: Store in GitHub Secrets

1. Go to your GitHub repository
2. **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `N8N_TEST_API_KEY`
5. Value: Paste your API key
6. Click **Add secret**

### Step 3: Use in CI/CD

The workflow import script will automatically use `N8N_TEST_API_KEY` if it's set:

```yaml
# .github/workflows/test-workflows.yml
env:
  N8N_TEST_API_KEY: ${{ secrets.N8N_TEST_API_KEY }}
```

## Testing Locally

```bash
# Set the API key
export N8N_TEST_API_KEY="eyJ..."  # Your actual key

# Test workflow import
cd scripts
./import-test-workflows.sh
```

Expected output:
```
✅ Using provided API key
   ✅ API key is valid
✅ Successfully imported 4 workflow(s)
```

## Why This Limitation Exists

n8n masks API keys in all API responses for security:
- Prevents key leakage through logs
- Prevents accidental exposure in API responses
- Keys are only shown once during UI creation

This is intentional security design, not a bug.

## Alternative Approaches

### Option 1: Manual Import (Simplest)

Import workflows once through the UI - they persist in the database:

1. Start n8n: `./scripts/start-test-env.sh`
2. Open: http://localhost:5679
3. Import each workflow from `/workflows` folder
4. Activate each workflow

### Option 2: Pre-seed Docker Image

Build a custom n8n image with workflows pre-loaded:

```dockerfile
FROM n8nio/n8n:latest
COPY workflows/*.json /home/node/.n8n/workflows/
```

### Option 3: n8n Source Control (Enterprise)

Use n8n's built-in Git integration for workflow management (requires Enterprise license).

## Troubleshooting

### "Unauthorized" (HTTP 401)
- API key is invalid, expired, or incorrectly copied
- Generate a new key and ensure you copy it completely
- Check for extra spaces or line breaks

### "API key test failed"
- n8n instance might not be fully started
- Wait 30 seconds and try again
- Check n8n logs: `docker logs n8n-test`

### Works locally but not in CI/CD
- Verify secret name matches exactly: `N8N_TEST_API_KEY`
- Check secret is set in repository settings (not organization)
- Re-run workflow after adding secret

### Key format issues
- Modern n8n uses JWT-style keys (`eyJ...`)
- Don't confuse with session tokens from browser
- Copy from the "API Key" field in n8n UI, not from network inspector

## For n8n-dev Instance

Same process but use:
- URL: `http://localhost:5678`
- Secret name: `N8N_DEV_API_KEY`
- Container: `n8n-dev`
