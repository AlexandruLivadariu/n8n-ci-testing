#!/bin/bash
# Quick test script - bypasses proxy and runs health check

# Bypass Zscaler proxy for localhost
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Create directories
mkdir -p results state

echo "🚀 Running n8n health check..."
echo "   (Proxy bypass enabled for localhost)"
echo ""

# Run health check
./runner.sh --mode=health-check

# Show results
if [ $? -eq 0 ]; then
  echo ""
  echo "✅ Tests completed! Check results:"
  echo "   ls -la results/"
else
  echo ""
  echo "⚠️  Some tests may have failed. Check results:"
  echo "   ls -la results/"
fi
