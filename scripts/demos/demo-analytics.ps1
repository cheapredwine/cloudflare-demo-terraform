#!/usr/bin/env pwsh

# Workers Analytics traffic generator (PowerShell)
# Sync with: demo-analytics.sh

$ErrorActionPreference = "Stop"

# Load credentials from the gitignored secrets/ store (see secrets/README.md).
. (Join-Path $PSScriptRoot "../lib/env.ps1")

function Get-TfvarsValue {
    param([string]$Key)
    if (-not (Test-Path "terraform.tfvars")) { return "" }
    $line = Get-Content "terraform.tfvars" | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
    if ($line -and $line -match '"([^"]+)"') { return $matches[1] }
    return ""
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
        $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        if (-not $params.ContainsKey("Headers")) { $params.Headers = @{} }
        $params.Headers["Authorization"] = "Basic $token"
    }
    return Invoke-WebRequest @params
}

function Invoke-Q {
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
    [void](Invoke-Http -Uri $Uri -Method $Method -Headers $Headers -Body $Body -ContentType $ContentType -User $User -Password $Password -Form $Form)
}

$zoneName = Get-TfvarsValue "zone_name"
if ([string]::IsNullOrWhiteSpace($zoneName)) {
    Write-Host "ERROR: zone_name not found in terraform.tfvars"
    exit 1
}

$api = "https://api.$zoneName"
$admin = "https://admin.$zoneName"

# Admin password comes from TF_VAR_admin_password (filled from
# secrets/admin_password by scripts/lib/env.ps1).
$script:AdminPassword = $env:TF_VAR_admin_password
if ([string]::IsNullOrWhiteSpace($script:AdminPassword)) {
    Write-Host "ERROR: put the admin password in secrets/admin_password (or set TF_VAR_admin_password)"
    exit 1
}
$rounds = if ($args.Count -gt 0) { [int]$args[0] } else { 3 }

Write-Host "================================================"
Write-Host " Workers Analytics Traffic Generator"
Write-Host " Zone: $zoneName"
Write-Host "================================================"
Write-Host ""
Write-Host "This script generates traffic across all workers."
Write-Host "Open Cloudflare dashboard to see live metrics:"
Write-Host ""
# ?to=/:account/... links let the dashboard pick the account, so the
# account ID never appears on screen.
Write-Host "  Workers & Pages:"
Write-Host "  https://dash.cloudflare.com/?to=/:account/workers-and-pages"
Write-Host ""
Write-Host "  Per-worker (API Gateway):"
Write-Host "  https://dash.cloudflare.com/?to=/:account/workers/services/view/demo-api-gateway/production"
Write-Host ""
Write-Host "  Per-worker (Products API):"
Write-Host "  https://dash.cloudflare.com/?to=/:account/workers/services/view/demo-products-api/production"
Write-Host ""
Write-Host "  Zone Analytics:"
Write-Host "  https://dash.cloudflare.com/?to=/:account/$zoneName/analytics/traffic"
Write-Host ""
Write-Host "Rounds are 10 s apart: waf.tf rate-limits /api/* to 50 requests per"
Write-Host "10 s per IP, and blocked requests wouldn't reach the Workers."
Write-Host ""
Write-Host "Generating traffic... ($rounds rounds)"
Write-Host ""

for ($i = 1; $i -le $rounds; $i++) {
    if ($i -gt 1) { Start-Sleep -Seconds 10 }
    Write-Host "Round $i/$rounds"

    # A real product ID (IDs aren't reused, so after a reset 1 may not exist)
    $idMatch = [regex]::Match([string](Invoke-Http -Uri "$api/api/products").Content, '"id":(\d+)')
    $productId = if ($idMatch.Success) { $idMatch.Groups[1].Value } else { "1" }

    Write-Host -NoNewline "  Auth... "
    $login = Invoke-Http -Uri "$api/api/auth/login" -Method "POST" -ContentType "application/json" -Body '{"email":"demo@example.com","password":"demo"}'
    $sessionMatch = [regex]::Match($login.Content, '"session_id":"([^"]+)"')
    $session = if ($sessionMatch.Success) { $sessionMatch.Groups[1].Value } else { "invalid" }
    Invoke-Q -Uri "$api/api/auth/me" -Headers @{ Authorization = "Bearer $session" }
    Invoke-Q -Uri "$api/api/auth/me" -Headers @{ Authorization = "Bearer invalid" }
    Write-Host "done"

    Write-Host -NoNewline "  Products (MISS then HITs)... "
    Invoke-Q -Uri "$api/api/products" -Method "POST" -ContentType "application/json" -Body "{`"name`":`"Demo Product $i`",`"price`":$i.99,`"stock`":$($i * 5)}"
    Invoke-Q -Uri "$api/api/products"
    Invoke-Q -Uri "$api/api/products"
    Invoke-Q -Uri "$api/api/products"
    Invoke-Q -Uri "$api/api/products/$productId"
    Invoke-Q -Uri "$api/api/products/999999" # 404
    Write-Host "done"

    Write-Host -NoNewline "  Orders... "
    Invoke-Q -Uri "$api/api/orders" -Method "POST" -ContentType "application/json" -Body "{`"customer_id`":`"demo-$i`",`"items`": [{`"product_id`":$productId,`"quantity`":1}]}"
    Invoke-Q -Uri "$api/api/orders" -Method "POST" -ContentType "application/json" -Body '{"customer_id":"missing-items"}'
    Write-Host "done"

    Write-Host -NoNewline "  Upload... "
    $tmpFile = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tmpFile -Value "demo file $i $(Get-Date -Format o)" -NoNewline
    Invoke-Q -Uri "$api/api/upload" -Method "POST" -Form @{ file = Get-Item $tmpFile }
    Invoke-Q -Uri "$api/api/upload" -Method "POST"
    Remove-Item $tmpFile -Force
    Write-Host "done"

    Write-Host -NoNewline "  404s... "
    Invoke-Q -Uri "$api/api/nonexistent"
    Invoke-Q -Uri "$api/api/nonexistent2"
    Write-Host "done"

    Write-Host -NoNewline "  Admin... "
    Invoke-Q -Uri "$admin/" -User "admin" -Password $script:AdminPassword
    Invoke-Q -Uri "$admin/api/stats" -User "admin" -Password $script:AdminPassword
    Invoke-Q -Uri "$admin/api/products" -User "admin" -Password $script:AdminPassword
    Invoke-Q -Uri "$admin/api/orders" -User "admin" -Password $script:AdminPassword
    Invoke-Q -Uri "$admin/" -User "admin" -Password "wrongpassword"
    Write-Host "done"

    Write-Host ""
}

Write-Host "================================================"
Write-Host " Traffic generation complete"
Write-Host " ~$($rounds * 25) requests sent across all workers"
Write-Host "================================================"
Write-Host ""
Write-Host "Dashboard links (may take ~1 min to show data):"
Write-Host "  Workers: https://dash.cloudflare.com/?to=/:account/workers-and-pages"
Write-Host "  Zone:    https://dash.cloudflare.com/?to=/:account/$zoneName/analytics/traffic"
Write-Host ""
