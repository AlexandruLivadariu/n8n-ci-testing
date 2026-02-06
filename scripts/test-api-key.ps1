# Test API key locally
param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey
)

Write-Host "Testing API key..." -ForegroundColor Yellow

try {
    $response = Invoke-RestMethod -Uri "http://localhost:5679/api/v1/workflows" -Headers @{"X-N8N-API-KEY"=$ApiKey}
    Write-Host "✅ API key works!" -ForegroundColor Green
    Write-Host "Found $($response.data.Count) workflows" -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "❌ API key failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure:" -ForegroundColor Yellow
    Write-Host "1. n8n-test is running (docker ps | grep n8n-test)" -ForegroundColor Yellow
    Write-Host "2. You created the API key at http://localhost:5679" -ForegroundColor Yellow
    Write-Host "3. You're using the correct API key" -ForegroundColor Yellow
    exit 1
}
