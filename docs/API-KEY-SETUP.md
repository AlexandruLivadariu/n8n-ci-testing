# API Key Setup Guide

## Why You Need an API Key

The automated workflow import requires an n8n API key to import test workflows via the REST API. Without it, workflows must be imported manually through the UI.

## Getting Your API Key

### For n8n-test Instance

1. **Start the test environment:**
   ```bash
   cd scripts
   ./start-test-env.sh
   ```

2. **Open n8n in your browser:**
   ```
   http://localhost:5679
   ```

3. **Complete initial setup (if first time):**
   - Create owner account
   - Set username and password

4. **Generate API Key:**
   - Click your user icon (bottom left)
   - Go to **Settings**
   - Click **n8n API** in the left menu (NOT just "API")
   - Click **Create an API key**
   - Give it a name like "CI/CD Testing"
   - Set expiration (or leave as "Never")
   - Copy the generated key - **it should start with `n8n_api_`**
   
   ⚠️ **Important:** Make sure you copy the actual API key, not a JWT token from your browser session!

5. **Set the API key:**

   **For local testing:**
   ```bash
   export N8N_TEST_API_KEY="n8n_api_xxxxxxxxxxxxx"
   ```

   **For GitHub Actions:**
   - Go to your repository on GitHub
   - Settings → Secrets and variables → Actions
   - Click "New repository secret"
   - Name: `N8N_TEST_API_KEY`
   - Value: Your API key (starts with `n8n_api_`)
   - Click "Add secret"

### For n8n-dev Instance

Same process but:
- URL: `http://localhost:5678`
- Secret name: `N8N_DEV_API_KEY`

## Testing the API Key

```bash
# Set the key
export N8N_TEST_API_KEY="your-key-here"

# Test it
cd scripts
./import-test-workflows.sh
```

If successful, you'll see:
```
✅ Imported successfully
```

## Troubleshooting

### "Unauthorized" (HTTP 401)
- API key is invalid or expired
- Generate a new key from n8n UI

### "Not Found" (HTTP 404)
- Wrong n8n URL
- Check if n8n is running: `docker ps | grep n8n`

### API key works locally but not in GitHub Actions
- Make sure you added the secret to GitHub repository settings
- Secret name must match exactly: `N8N_TEST_API_KEY`
- Re-run the workflow after adding the secret

## Alternative: Manual Workflow Import

If you don't want to use API keys, you can import workflows manually:

1. Start n8n: `cd scripts && ./start-test-env.sh`
2. Open: http://localhost:5679
3. For each workflow in `/workflows` folder:
   - Click "Add workflow" → "Import from file"
   - Select the workflow JSON file
   - Click "Save" and "Activate"

The test workflows you need:
- `test-health-webhook.json`
- `test-echo-webhook.json`
- `test-http-request.json`
- `test-credential.json`

After manual import, the tests will work without an API key.
