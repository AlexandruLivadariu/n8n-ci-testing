# Run n8n workflow tests
param()

$ErrorActionPreference = "Stop"

Write-Host "🧪 Running n8n Workflow Tests" -ForegroundColor Blue
Write-Host "================================"

$N8N_TEST_HOST = if ($env:N8N_TEST_HOST) { $env:N8N_TEST_HOST } else { "http://localhost:5679" }
$N8N_API_KEY = $env:N8N_TEST_API_KEY

if (-not $N8N_API_KEY) {
    Write-Host "❌ N8N_TEST_API_KEY environment variable not set" -ForegroundColor Red
    exit 1
}

$totalTests = 0
$passedTests = 0
$failedTests = 0

function Test-ApiHealth {
    Write-Host "Testing: n8n API Health" -ForegroundColor Yellow
    $script:totalTests++
    
    try {
        Invoke-RestMethod -Uri "$N8N_TEST_HOST/api/v1/workflows" -Headers @{"X-N8N-API-KEY"=$N8N_API_KEY} | Out-Null
        Write-Host "✅ PASS" -ForegroundColor Green
        $script:passedTests++
        return $true
    }
    catch {
        Write-Host "❌ FAIL" -ForegroundColor Red
        $script:failedTests++
        return $false
    }
}

function Test-WorkflowsLoaded {
    Write-Host "Testing: Workflows Loaded" -ForegroundColor Yellow
    $script:totalTests++
    
    try {
        $response = Invoke-RestMethod -Uri "$N8N_TEST_HOST/api/v1/workflows" -Headers @{"X-N8N-API-KEY"=$N8N_API_KEY}
        $workflowCount = $response.data.Count
        
        if ($workflowCount -gt 0) {
            Write-Host "✅ PASS - $workflowCount workflows loaded" -ForegroundColor Green
            $script:passedTests++
            return $true
        }
        else {
            Write-Host "❌ FAIL - No workflows loaded" -ForegroundColor Red
            $script:failedTests++
            return $false
        }
    }
    catch {
        Write-Host "❌ FAIL" -ForegroundColor Red
        $script:failedTests++
        return $false
    }
}

function Test-Webhook {
    param(
        [string]$WebhookPath,
        [string]$TestName,
        [object]$TestData,
        [int]$ExpectedStatus
    )
    
    Write-Host "Testing: $TestName" -ForegroundColor Yellow
    $script:totalTests++
    
    try {
        $body = $TestData | ConvertTo-Json -Depth 10
        $response = Invoke-WebRequest -Uri "$N8N_TEST_HOST$WebhookPath" `
            -Method Post `
            -Headers @{"Content-Type"="application/json"} `
            -Body $body `
            -UseBasicParsing
        
        if ($response.StatusCode -eq $ExpectedStatus) {
            Write-Host "✅ PASS" -ForegroundColor Green
            $script:passedTests++
            return $true
        }
        else {
            Write-Host "❌ FAIL (Expected $ExpectedStatus, got $($response.StatusCode))" -ForegroundColor Red
            $script:failedTests++
            return $false
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq $ExpectedStatus) {
            Write-Host "✅ PASS" -ForegroundColor Green
            $script:passedTests++
            return $true
        }
        else {
            Write-Host "❌ FAIL (Expected $ExpectedStatus, got $statusCode)" -ForegroundColor Red
            $script:failedTests++
            return $false
        }
    }
}

Write-Host "Step 1: API Health Check"
Test-ApiHealth
Write-Host ""

Write-Host "Step 2: Workflow Load Check"
Test-WorkflowsLoaded
Write-Host ""

$testCasesFile = Join-Path $PSScriptRoot "..\tests\test-cases\webhook-tests.json"
if (Test-Path $testCasesFile) {
    Write-Host "Step 3: Webhook Tests"
    
    $testCases = Get-Content $testCasesFile -Raw | ConvertFrom-Json
    
    foreach ($test in $testCases.tests) {
        Test-Webhook -WebhookPath $test.webhook `
            -TestName $test.name `
            -TestData $test.data `
            -ExpectedStatus $test.expectedStatus
        Write-Host ""
    }
}

Write-Host "================================"
Write-Host "Test Summary" -ForegroundColor Blue
Write-Host "  Total:  $totalTests"
Write-Host "  Passed: $passedTests" -ForegroundColor Green
Write-Host "  Failed: $failedTests" -ForegroundColor Red

if ($failedTests -eq 0) {
    Write-Host "✅ All tests passed!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "❌ Some tests failed" -ForegroundColor Red
    exit 1
}
