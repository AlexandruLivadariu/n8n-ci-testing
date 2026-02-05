# Import workflows to n8n environment
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("dev", "test")]
    [string]$Environment
)

$ErrorActionPreference = "Stop"

if ($Environment -eq "dev") {
    $N8N_HOST = if ($env:N8N_DEV_HOST) { $env:N8N_DEV_HOST } else { "http://localhost:5678" }
    $N8N_API_KEY = $env:N8N_DEV_API_KEY
    Write-Host "📥 Importing workflows to n8n-dev..." -ForegroundColor Yellow
}
elseif ($Environment -eq "test") {
    $N8N_HOST = if ($env:N8N_TEST_HOST) { $env:N8N_TEST_HOST } else { "http://localhost:5679" }
    $N8N_API_KEY = $env:N8N_TEST_API_KEY
    Write-Host "📥 Importing workflows to n8n-test..." -ForegroundColor Yellow
}

if (-not $N8N_API_KEY) {
    Write-Host "❌ API key environment variable not set" -ForegroundColor Red
    Write-Host "For dev: `$env:N8N_DEV_API_KEY='your-api-key'"
    Write-Host "For test: `$env:N8N_TEST_API_KEY='your-api-key'"
    exit 1
}

# Test connection
try {
    Invoke-RestMethod -Uri "$N8N_HOST/api/v1/workflows" -Headers @{"X-N8N-API-KEY"=$N8N_API_KEY} | Out-Null
}
catch {
    Write-Host "❌ Cannot connect to n8n at $N8N_HOST" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

$workflowsDir = Join-Path $PSScriptRoot "..\workflows"
$workflowFiles = Get-ChildItem -Path $workflowsDir -Filter "*.json" -ErrorAction SilentlyContinue

if (-not $workflowFiles) {
    Write-Host "⚠️  No workflow files found" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($workflowFiles.Count) workflow files" -ForegroundColor Green

$success = 0
$failed = 0

foreach ($file in $workflowFiles) {
    Write-Host "  📄 Importing: $($file.Name)"
    
    try {
        $workflowData = Get-Content $file.FullName -Raw | ConvertFrom-Json
        
        # Remove id to create new workflow
        $workflowData.PSObject.Properties.Remove('id')
        
        $body = $workflowData | ConvertTo-Json -Depth 100
        
        $response = Invoke-RestMethod -Uri "$N8N_HOST/api/v1/workflows" `
            -Method Post `
            -Headers @{"X-N8N-API-KEY"=$N8N_API_KEY; "Content-Type"="application/json"} `
            -Body $body
        
        Write-Host "  ✅ Imported successfully" -ForegroundColor Green
        $success++
    }
    catch {
        Write-Host "  ❌ Failed: $_" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "✅ Import complete!" -ForegroundColor Green
Write-Host "  Success: $success"
Write-Host "  Failed: $failed"

if ($failed -gt 0) {
    exit 1
}
