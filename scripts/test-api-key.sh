#!/bin/bash

# Test API key locally

if [ -z "$1" ]; then
    echo "Usage: ./test-api-key.sh YOUR_API_KEY"
    exit 1
fi

API_KEY=$1

echo "Testing API key..."

# Bypass proxy
export no_proxy="localhost,127.0.0.1"
export NO_PROXY="localhost,127.0.0.1"

# Test the API
RESPONSE=$(curl -s -H "X-N8N-API-KEY: $API_KEY" http://localhost:5679/rest/workflows)

if echo "$RESPONSE" | grep -q "data"; then
    echo "✅ API key works!"
    echo "Response: $RESPONSE"
    exit 0
elif echo "$RESPONSE" | grep -q "Unauthorized"; then
    echo "❌ API key is unauthorized"
    echo "Response: $RESPONSE"
    exit 1
else
    echo "❌ Unexpected response"
    echo "Response: $RESPONSE"
    exit 1
fi
