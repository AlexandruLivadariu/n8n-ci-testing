# Zscaler Proxy Fix

## Problem

Your corporate Zscaler proxy is blocking localhost connections. You see this error:
```
Your organization has selected Zscaler to protect you from internet threats.
```

## Solution

Add proxy bypass for localhost to your shell session.

### Quick Fix (Temporary - Current Session Only)

```bash
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"
```

Then run your tests:
```bash
cd /mnt/c/n8n-ci-testing/tests
./runner.sh --mode=health-check
```

### Permanent Fix (Add to ~/.bashrc)

```bash
# Add to end of ~/.bashrc
echo 'export no_proxy="localhost,127.0.0.1"' >> ~/.bashrc
echo 'export NO_PROXY="localhost,127.0.0.1"' >> ~/.bashrc

# Reload
source ~/.bashrc
```

### Test the Fix

```bash
# Should return HTML (not Zscaler page)
curl http://localhost:5679

# Should show n8n login or dashboard
curl -s http://localhost:5679 | head -20
```

## Why This Happens

- Zscaler intercepts ALL HTTP/HTTPS traffic
- Even localhost connections go through the proxy
- The proxy blocks localhost for security
- We need to tell curl/bash to bypass proxy for localhost

## Verification

### Before Fix:
```bash
curl http://localhost:5679
# Shows: "Your organization has selected Zscaler..."
```

### After Fix:
```bash
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"
curl http://localhost:5679
# Shows: HTML with n8n content
```

## For GitHub Actions

The GitHub Actions workflows already have this fix:
```yaml
env:
  no_proxy: localhost,127.0.0.1
  NO_PROXY: localhost,127.0.0.1
```

So GitHub Actions will work fine!

## Alternative: Use Docker Exec

If proxy bypass doesn't work, you can test from inside the container:

```bash
# Test from inside n8n container (bypasses proxy)
docker exec n8n-test wget -q -O- http://localhost:5678

# Test database from inside postgres container
docker exec n8n-postgres-test psql -U n8n -d n8n -c "SELECT COUNT(*) FROM workflow_entity;"
```

---

**Quick Start After Fix:**
```bash
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"
cd /mnt/c/n8n-ci-testing/tests
./runner.sh --mode=health-check
```
