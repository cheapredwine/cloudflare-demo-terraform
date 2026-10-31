#!/usr/bin/env pwsh

# Cache latency comparison demo (PowerShell)
# Sync with: demo-latency.sh

$ErrorActionPreference = "Stop"

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
        [string]$Body,
        [string]$ContentType
    )
    $params = @{
        Uri                = $Uri
        Method             = $Method
        TimeoutSec         = 15
        SkipHttpErrorCheck = $true
    }
    if ($Body) { $params.Body = $Body }
    if ($ContentType) { $params.ContentType = $ContentType }
    return Invoke-WebRequest @params
}

$zoneName = Get-TfvarsValue "zone_name"
if ([string]::IsNullOrWhiteSpace($zoneName)) {
    Write-Host "ERROR: zone_name not found in terraform.tfvars"
    exit 1
}

$api = "https://api.$zoneName"
$rounds = if ($args.Count -gt 0) { [int]$args[0] } else { 5 }

Write-Host "================================================"
Write-Host " Cache Latency Comparison"
Write-Host " Zone: $zoneName"
Write-Host " Rounds: $rounds"
Write-Host "================================================"
Write-Host ""

# Clear the products API's KV cache. Any write clears it, so create a
# throwaway product and delete it again by the id the POST returned (never
# touching a real product).
function Clear-Cache {
    $created = Invoke-Http -Uri "$api/api/products" -Method "POST" -ContentType "application/json" -Body '{"name":"__cache_bust__","price":0.01}'
    $idMatch = [regex]::Match([string]$created.Content, '"id":(\d+)')
    if ($idMatch.Success) {
        [void](Invoke-Http -Uri "$api/api/products/$($idMatch.Groups[1].Value)" -Method "DELETE")
    }
}

# Time one GET; return its milliseconds and cache header from that same request.
function Get-Timed {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $resp = Invoke-Http -Uri "$api/api/products"
    $sw.Stop()
    $cache = if ($resp.Headers["x-products-cache"]) { [string]$resp.Headers["x-products-cache"] } else { "?" }
    return [pscustomobject]@{ Ms = [int][Math]::Round($sw.Elapsed.TotalMilliseconds); Cache = $cache }
}

$missTimes = @()
Write-Host "[ MISS ] Cache cleared before each request: querying D1..."
for ($i = 1; $i -le $rounds; $i++) {
    Clear-Cache
    $t = Get-Timed
    $missTimes += $t.Ms
    Write-Host "  Round $i`: $($t.Ms)ms  [$($t.Cache)]"
}

$hitTimes = @()
Write-Host ""
Write-Host "[ HIT ] Cache left alone: served from KV..."
for ($i = 1; $i -le $rounds; $i++) {
    $t = Get-Timed
    $hitTimes += $t.Ms
    Write-Host "  Round $i`: $($t.Ms)ms  [$($t.Cache)]"
}

$missAvg = [int][Math]::Round((($missTimes | Measure-Object -Average).Average))
$hitAvg = [int][Math]::Round((($hitTimes | Measure-Object -Average).Average))
$speedup = if ($hitAvg -gt 0) { "{0:N1}" -f ($missAvg / $hitAvg) } else { "N/A" }

Write-Host ""
Write-Host "================================================"
Write-Host " Results"
Write-Host "================================================"
Write-Host ""
Write-Host "  Average MISS (D1 query):  ${missAvg}ms"
Write-Host "  Average HIT  (KV cache):  ${hitAvg}ms"
Write-Host "  Cache speedup:            ${speedup}x faster"
Write-Host ""
Write-Host "  KV cache TTL: 10 minutes (workers/products-api.js)"
Write-Host "  api.<zone> is served by a Worker, so cdn.tf's cache rules don't apply here."
Write-Host ""
