# Export workflows from n8n-dev
param()

$ErrorActionPreference = "Stop"

Write-Host "🔄 Exporting workflows from n8n-dev..." -ForegroundColor Yellow

$N8N_HOST = if ($env:N8N_DEV_HOST) { $env:N8N_DEV_HOST } else { "http://localhost:5678" }
$N8N_API_KEY = $env:N8N_DEV_API_KEY

if (-not $N8N_API_KEY) {
    Write-Host "❌ N8N_DEV_API_KEY environment variable not set" -ForegroundColor Red
    Write-Host "Set it with: `$env:N8N_DEV_API_KEY='your-api-key'"
    exit 1
}

# Create workflows directory
$workflowsDir = Join-Path $PSScriptRoot "..\workflows"
if (-not (Test-Path $workflowsDir)) {
    New-Item -ItemType Directory -Path $workflowsDir | Out-Null
}

try {
    $response = Invoke-RestMethod -Uri "$N8N_HOST/api/v1/workflows" -Headers @{"X-N8N-API-KEY"=$N8N_API_KEY}
    
    $workflowCount = $response.data.Count
    
    if ($workflowCount -eq 0) {
        Write-Host "⚠️  No workflows found" -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Found $workflowCount workflows" -ForegroundColor Green
    
    foreach ($workflow in $response.data) {
        $workflowName = $workflow.name
        $workflowId = $workflow.id
        $safeName = $workflowName -replace '[^a-zA-Z0-9_-]', '_'
        $filename = Join-Path $workflowsDir "$safeName.json"
        
        Write-Host "  📄 Exporting: $workflowName"
        
        $fullWorkflow = Invoke-RestMethod -Uri "$N8N_HOST/api/v1/workflows/$workflowId" -Headers @{"X-N8N-API-KEY"=$N8N_API_KEY}
        $fullWorkflow | ConvertTo-Json -Depth 100 | Set-Content -Path $filename
        
        Write-Host "  ✅ Saved to: $filename" -ForegroundColor Green
    }
    
    Write-Host "✅ Export complete!" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to connect to n8n-dev: $_" -ForegroundColor Red
    exit 1
}
