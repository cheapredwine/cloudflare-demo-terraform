#!/usr/bin/env pwsh

# Cloudflare Demo Platform - Management Script (PowerShell)
# Sync with: run-demo.sh

param(
    [string[]]$CliArgs = $args
)

$ErrorActionPreference = "Stop"

function Show-Help {
    Write-Host "🚀 Cloudflare Demo Platform Management"
    Write-Host "====================================="
    Write-Host ""
    Write-Host "Usage: ./run-demo.ps1 [ACTION] [OPTIONS]"
    Write-Host ""
    Write-Host "Actions:"
    Write-Host "  deploy      Deploy fresh infrastructure (default)"
    Write-Host "  reset       Reset data but keep infrastructure"
    Write-Host "  destroy     Tear down all infrastructure"
    Write-Host "  fresh       Destroy and redeploy everything"
    Write-Host "  test        Test existing deployment"
    Write-Host "  help        Show this help"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --demo      Run demo commands after deployment"
    Write-Host "  --zone NAME Override zone name from terraform.tfvars"
    Write-Host "  --zone=NAME Override zone name from terraform.tfvars"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  ./run-demo.ps1 deploy --demo"
    Write-Host "  ./run-demo.ps1 reset"
    Write-Host "  ./run-demo.ps1 fresh --zone demo2.example.com"
    Write-Host ""
}

function Get-TfvarsValue {
    param([string]$Key)
    if (-not (Test-Path "terraform.tfvars")) {
        return ""
    }
    $line = Get-Content "terraform.tfvars" | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
    if ($line -and $line -match '"([^"]+)"') {
        return $matches[1]
    }
    return ""
}

function Invoke-CheckedCommand {
    param(
        [string]$Command,
        [string[]]$Arguments
    )
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Http {
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [hashtable]$Headers,
        [string]$Body,
        [string]$ContentType,
        [string]$User,
        [string]$Password,
        [hashtable]$Form
    )

    $params = @{
        Uri                = $Uri
        Method             = $Method
        TimeoutSec         = 15
        SkipHttpErrorCheck = $true
    }
    if ($Headers) { $params.Headers = $Headers }
    if ($Body) { $params.Body = $Body }
    if ($ContentType) { $params.ContentType = $ContentType }
    if ($Form) { $params.Form = $Form }
    if ($User) {
        $pair = "{0}:{1}" -f $User, $Password
        $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
        if (-not $params.ContainsKey("Headers")) { $params.Headers = @{} }
        $params.Headers["Authorization"] = "Basic $token"
    }

    return Invoke-WebRequest @params
}

function Parse-JsonOrRaw {
    param([string]$Text)
    try {
        return ($Text | ConvertFrom-Json | ConvertTo-Json -Depth 10)
    } catch {
        return $Text
    }
}

function Test-EndpointsSilent {
    $apiUrl = "https://api.$script:ZoneName/api/products"
    $response = Invoke-Http -Uri $apiUrl
    return ($response.StatusCode -eq 200)
}

function Check-QueueConsumer {
    Write-Host "Testing Queue consumer..."
    if (-not (Get-Command wrangler -ErrorAction SilentlyContinue)) {
        Write-Host "⚠️  Wrangler not installed; skipping queue consumer check"
        return
    }

    $queueInfo = (& wrangler queues info demo-order-processing 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  Could not query queue info; check Wrangler auth and account access"
        return
    }

    $match = [regex]::Match($queueInfo, "Number of Consumers:\s*(\d+)")
    if ($match.Success -and [int]$match.Groups[1].Value -ge 1) {
        Write-Host "✅ Queue consumer attached (consumers: $($match.Groups[1].Value))"
    } else {
        Write-Host "❌ Queue consumer missing: demo-order-processing has no consumers"
        Write-Host "   Orders will stay queued and not show in admin"
        Write-Host "   Fix: wrangler queues consumer worker add demo-order-processing demo-order-processor"
        exit 1
    }
}

function Test-Endpoints {
    Write-Host "🧪 Testing endpoints..."

    Write-Host "Testing API Gateway..."
    $apiUrl = "https://api.$script:ZoneName/api/products"
    $apiStatus = (Invoke-Http -Uri $apiUrl).StatusCode
    if ($apiStatus -eq 200) {
        Write-Host "✅ API Gateway: $apiUrl"
    } else {
        Write-Host "⚠️  API Gateway: $apiUrl (HTTP $apiStatus)"
    }

    Write-Host "Testing Admin Panel..."
    $adminUrl = "https://admin.$script:ZoneName"
    $adminStatus = (Invoke-Http -Uri $adminUrl).StatusCode
    if ($adminStatus -eq 401) {
        Write-Host "✅ Admin Panel: $adminUrl (Auth required)"
    } else {
        Write-Host "⚠️  Admin Panel: $adminUrl (HTTP $adminStatus)"
    }

    Check-QueueConsumer
}

function Show-QuickStart {
    Write-Host "📚 Quick Start:"
    Write-Host "   1. Visit the admin panel"
    Write-Host "   2. Load sample data using the 'Load Sample Data' button"
    Write-Host "   3. Test the API endpoints:"
    Write-Host ""
    Write-Host "   # Get products"
    Write-Host "   curl https://api.$script:ZoneName/api/products"
    Write-Host ""
    Write-Host "   # Create order"
    Write-Host "   curl -X POST https://api.$script:ZoneName/api/orders \"
    Write-Host "     -H 'Content-Type: application/json' \"
    Write-Host "     -d '{\"customer_id\":\"demo\",\"items\":[{\"product_id\":1,\"quantity\":1,\"unit_price\":24.99}],\"total\":24.99}'"
    Write-Host ""
    Write-Host "🧹 Management:"
    Write-Host "   ./run-demo.ps1 reset"
    Write-Host "   ./run-demo.ps1 destroy"
    Write-Host ""
}

function Show-SuccessMessage {
    Write-Host ""
    Write-Host "🎉 Demo Platform Ready!"
    Write-Host "======================="
    Write-Host ""
    Write-Host "📱 Web Interface:"
    Write-Host "   API Gateway:  https://api.$script:ZoneName"
    Write-Host "   Admin Panel:  https://admin.$script:ZoneName"
    Write-Host ""
    Write-Host "🔑 Admin Access:"
    Write-Host "   URL:      https://admin.$script:ZoneName"
    Write-Host "   Username: admin"
    Write-Host "   Password: demo123"
    Write-Host ""
    Show-QuickStart
}

function Deploy-Infrastructure {
    Write-Host "🏗️  Deploying infrastructure..."
    Invoke-CheckedCommand -Command terraform -Arguments @("init")
    Invoke-CheckedCommand -Command terraform -Arguments @("apply", "-auto-approve")

    Write-Host "✅ Infrastructure deployed successfully!"
    Write-Host ""
    Write-Host "⏳ Waiting for DNS propagation..."
    Start-Sleep -Seconds 30
    Test-Endpoints
    Show-SuccessMessage
}

function Reset-Data {
    Write-Host "🔄 Resetting demo data..."
    if (-not (Test-EndpointsSilent)) {
        Write-Host "❌ Infrastructure not found. Deploy first with: ./run-demo.ps1 deploy"
        exit 1
    }

    Write-Host "Clearing database and cache..."
    $setupResp = Invoke-Http -Uri "https://admin.$script:ZoneName/setup" -Method "POST" -User "admin" -Password "demo123"
    if ($setupResp.StatusCode -eq 200) {
        Write-Host "✅ Database reset"
    } else {
        Write-Host "⚠️  Database reset may have failed (HTTP $($setupResp.StatusCode))"
    }

    Write-Host "Loading sample data..."
    $seedResp = Invoke-Http -Uri "https://api.$script:ZoneName/api/products/seed" -Method "POST"
    if ($seedResp.StatusCode -eq 200) {
        Write-Host "✅ Sample data loaded"
    } else {
        Write-Host "⚠️  Sample data load may have failed (HTTP $($seedResp.StatusCode))"
    }

    Write-Host ""
    Write-Host "🎯 Demo environment reset and ready!"
    Show-QuickStart
}

function Destroy-Infrastructure {
    Write-Host "🧨 Destroying infrastructure..."
    Write-Host "⚠️  This will delete all data and stop all costs"
    $reply = Read-Host "Are you sure? (y/N)"
    if ($reply -notmatch '^[Yy]$') {
        Write-Host "Cancelled"
        exit 0
    }

    Invoke-CheckedCommand -Command terraform -Arguments @("destroy", "-auto-approve")
    Write-Host "✅ Infrastructure destroyed successfully"
    Write-Host "💰 All costs stopped"
}

function Run-DemoCommands {
    Write-Host "🎬 Running demo commands..."
    Start-Sleep -Seconds 10

    Write-Host "Creating sample product..."
    $createProduct = Invoke-Http -Uri "https://api.$script:ZoneName/api/products" -Method "POST" -ContentType "application/json" -Body '{"name":"Demo Product","description":"Created by script","price":99.99,"category":"demo","stock":10}'
    Write-Host (Parse-JsonOrRaw $createProduct.Content)

    Write-Host ""
    Write-Host "Getting all products..."
    $products = Invoke-Http -Uri "https://api.$script:ZoneName/api/products"
    Write-Host (Parse-JsonOrRaw $products.Content)

    Write-Host ""
    Write-Host "Creating sample order..."
    $createOrder = Invoke-Http -Uri "https://api.$script:ZoneName/api/orders" -Method "POST" -ContentType "application/json" -Body '{"customer_id":"script-demo","items":[{"product_id":1,"quantity":1,"unit_price":99.99}],"total":99.99}'
    Write-Host (Parse-JsonOrRaw $createOrder.Content)

    Write-Host ""
    Write-Host "🎯 Demo commands completed!"
}

function Needs-ZoneName {
    return @("deploy", "reset", "fresh", "test") -contains $script:Action
}

function Parse-Args {
    param([string[]]$InputArgs)

    $argv = @($InputArgs)
    $script:Action = "deploy"
    $script:RunDemo = $false
    $script:ZoneName = ""

    if ($argv.Count -gt 0 -and $argv[0] -notmatch '^--') {
        $script:Action = $argv[0]
        if ($argv.Count -gt 1) {
            $argv = $argv[1..($argv.Count - 1)]
        } else {
            $argv = @()
        }
    }

    for ($i = 0; $i -lt $argv.Count; $i++) {
        $arg = $argv[$i]
        if ($arg -eq "--demo") {
            $script:RunDemo = $true
        } elseif ($arg -like "--zone=*") {
            $script:ZoneName = $arg.Substring(7)
        } elseif ($arg -eq "--zone") {
            if ($i + 1 -ge $argv.Count -or $argv[$i + 1].StartsWith("--")) {
                Write-Host "❌ Missing value for --zone"
                exit 1
            }
            $i++
            $script:ZoneName = $argv[$i]
        }
    }
}

function Check-Prerequisites {
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Terraform is required but not installed."
        Write-Host "Install from: https://www.terraform.io/downloads"
        exit 1
    }
    if (-not (Test-Path "terraform.tfvars") -and $script:Action -ne "destroy") {
        Write-Host "❌ terraform.tfvars not found"
        Write-Host "Copy terraform.tfvars.example to terraform.tfvars and configure your settings"
        exit 1
    }
}

Parse-Args -InputArgs $CliArgs

if ($script:Action -in @("help", "--help", "-h")) {
    Show-Help
    exit 0
}

Write-Host "🚀 Cloudflare Demo Platform - $($script:Action)"
Write-Host "====================================="

Check-Prerequisites

if ((Needs-ZoneName) -and [string]::IsNullOrWhiteSpace($script:ZoneName)) {
    $script:ZoneName = Get-TfvarsValue "zone_name"
    if ([string]::IsNullOrWhiteSpace($script:ZoneName)) {
        Write-Host "❌ zone_name not found. Use --zone=domain.com or set in terraform.tfvars"
        exit 1
    }
}

Write-Host "📋 Configuration:"
if (Needs-ZoneName) {
    Write-Host "   Zone: $script:ZoneName"
}
Write-Host "   Action: $script:Action"
Write-Host ""

switch ($script:Action) {
    "deploy" { Deploy-Infrastructure }
    "reset" { Reset-Data }
    "destroy" { Destroy-Infrastructure }
    "fresh" { Destroy-Infrastructure; Write-Host ""; Deploy-Infrastructure }
    "test" { Test-Endpoints }
    default {
        Write-Host "❌ Unknown action: $($script:Action)"
        Show-Help
        exit 1
    }
}

if ($script:RunDemo) {
    Run-DemoCommands
}

Write-Host "✨ Operation complete!"
