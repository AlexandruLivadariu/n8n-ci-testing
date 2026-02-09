# CI/CD Workflow Import Solution

## The Problem

Automated workflow import in CI/CD pipelines faces a fundamental challenge: **n8n's API key creation endpoint returns masked keys**.

When creating an API key programmatically:
```json
{
  "apiKey": "******saLM",    // Masked for security
  "rawApiKey": "***"          // Also masked
}
```

This prevents fully automated workflow import without manual intervention.

## The Solution

Use a **manually created API key** stored as a GitHub secret.

### Implementation Steps

1. **One-time manual setup:**
   - Start n8n locally
   - Create API key through UI (Settings > n8n API)
   - Copy the key (shown only once!)
   - Add to GitHub Secrets as `N8N_TEST_API_KEY`

2. **CI/CD pipeline uses the secret:**
   ```yaml
   env:
     N8N_TEST_API_KEY: ${{ secrets.N8N_TEST_API_KEY }}
   ```

3. **Import script checks for existing key:**
   ```bash
   if [ -n "$N8N_TEST_API_KEY" ]; then
     # Use provided key
   else
     # Attempt automated creation (will fail at import step)
   fi
   ```

### Why This Works

- API keys created through UI are shown unmasked (once)
- Keys persist across n8n restarts
- Same key works for all CI/CD runs
- No need to recreate keys for each pipeline run

## Current Script Behavior

`scripts/import-test-workflows.sh` now:

1. **Checks for `N8N_TEST_API_KEY`** environment variable
2. **If found:** Uses it directly for imports
3. **If not found:** Attempts automated setup (creates owner, logs in, creates key)
4. **Result:** Automated setup creates key but gets masked version, imports fail

### With API Key Set

```bash
export N8N_TEST_API_KEY="eyJ..."
./scripts/import-test-workflows.sh
```

Output:
```
✅ Using provided API key
   ✅ API key is valid
✅ Successfully imported 4 workflow(s)
```

### Without API Key

```bash
./scripts/import-test-workflows.sh
```

Output:
```
✅ Owner account created
✅ Got session cookie
✅ API key created
   Key: ******saLM...
❌ API key test failed (HTTP 401)
   Response: {"message":"unauthorized"}
❌ Received masked API key - cannot use for authentication
```

## Alternative Approaches Considered

### ❌ Database Seeding
- **Idea:** Insert workflows directly into PostgreSQL
- **Problem:** Fragile, breaks on schema changes, complex SQL

### ❌ n8n CLI
- **Idea:** Use `n8n import:workflow` command
- **Problem:** Doesn't activate workflows, requires container exec

### ❌ File System Copy
- **Idea:** Copy JSON files to `~/.n8n/workflows/`
- **Problem:** n8n doesn't auto-import from filesystem

### ❌ Custom Docker Image
- **Idea:** Pre-seed workflows in Docker image
- **Problem:** Workflows still need activation, adds build complexity

### ✅ Manual API Key (Chosen Solution)
- **Simple:** One-time setup
- **Reliable:** Works consistently
- **Secure:** Key stored as GitHub secret
- **Maintainable:** No complex workarounds

## For Production Use

For production CI/CD, consider:

1. **n8n Source Control (Enterprise):**
   - Built-in Git integration
   - Automatic workflow sync
   - Requires Enterprise license

2. **Separate Workflow Repository:**
   - Store workflows in Git
   - Use API key for deployment
   - Version control for workflows

3. **Infrastructure as Code:**
   - Terraform/Pulumi for n8n setup
   - API key in secrets manager
   - Automated but with manual key creation step

## Security Considerations

- **API keys are sensitive:** Store in GitHub Secrets, never commit to code
- **Scope appropriately:** Only grant workflow permissions needed
- **Rotate regularly:** Set expiration dates, update secrets
- **Audit access:** Monitor API key usage in n8n logs

## Documentation

See `docs/API-KEY-SETUP.md` for detailed instructions on creating and storing API keys.
