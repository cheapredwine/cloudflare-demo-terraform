#!/usr/bin/env pwsh

# Production integration tests for Cloudflare Demo Platform (PowerShell)
# Sync with: test.sh

$ErrorActionPreference = "Stop"

# Load credentials from the gitignored secrets/ store (see secrets/README.md).
. (Join-Path $PSScriptRoot "../lib/env.ps1")

$script:Pass = 0
$script:Fail = 0
$script:Errors = New-Object System.Collections.Generic.List[string]

function Get-TfvarsValue {
    param([string]$Key)
    if (-not (Test-Path "terraform.tfvars")) { return "" }
    $line = Get-Content "terraform.tfvars" | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
    if ($line -and $line -match '"([^"]+)"') { return $matches[1] }
    return ""
}

function Pass([string]$Label) {
    Write-Host "  PASS  $Label"
    $script:Pass++
}

function Fail([string]$Label) {
    Write-Host "  FAIL  $Label"
    $script:Fail++
    $script:Errors.Add($Label)
}

function Assert-Status([string]$Label, [int]$Expected, [int]$Actual) {
    if ($Expected -eq $Actual) {
        Pass "$Label (HTTP $Actual)"
    } else {
        Fail "$Label (expected HTTP $Expected, got HTTP $Actual)"
    }
}

function Assert-Contains([string]$Label, [string]$Needle, [string]$Haystack) {
    if ($Haystack -match [regex]::Escape($Needle)) {
        Pass "$Label (contains '$Needle')"
    } else {
        Fail "$Label (expected '$Needle' in response)"
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
        [hashtable]$Form,
        [switch]$NoRedirect
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
    if ($NoRedirect) { $params.MaximumRedirection = 0 }
    if ($User) {
        $pair = "{0}:{1}" -f $User, $Password
        $token = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        if (-not $params.ContainsKey("Headers")) { $params.Headers = @{} }
        $params.Headers["Authorization"] = "Basic $token"
    }
    # A network error is recorded as status 0 (a FAIL), not a script crash.
    try {
        return Invoke-WebRequest @params
    } catch {
        return [pscustomobject]@{ StatusCode = 0; Content = ""; Headers = @{} }
    }
}

function Wait-ForOrderInAdmin([string]$AdminBase, [string]$OrderId) {
    for ($attempt = 1; $attempt -le 15; $attempt++) {
        $resp = Invoke-Http -Uri "$AdminBase/api/orders" -User "admin" -Password $script:AdminPassword
        if ($resp.Content -match [regex]::Escape($OrderId)) {
            return $true
        }
        Start-Sleep -Seconds 2
    }
    return $false
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

Write-Host "================================================"
Write-Host " Cloudflare Demo Platform - Integration Tests"
Write-Host " Zone: $zoneName"
Write-Host "================================================"
Write-Host ""

Write-Host "[ 1 ] API Gateway"
$status = (Invoke-Http -Uri "$api/api/nonexistent").StatusCode
Assert-Status "unknown route returns 404" 404 $status

$status = (Invoke-Http -Uri "$api/api/products" -Method "OPTIONS" -Headers @{
    Origin = "https://example.com"
    "Access-Control-Request-Method" = "GET"
}).StatusCode
Assert-Status "OPTIONS preflight returns 200" 200 $status

$body = (Invoke-Http -Uri "$api/api/nonexistent").Content
Assert-Contains "404 body returns error message" '"error"' $body
Write-Host ""

Write-Host "[ 2 ] Auth"
$login = Invoke-Http -Uri "$api/api/auth/login" -Method "POST" -ContentType "application/json" -Body '{"email":"test@example.com","password":"anypassword"}'
Assert-Status "login returns 200" 200 $login.StatusCode
Assert-Contains "login returns session_id" "session_id" $login.Content

$sessionMatch = [regex]::Match($login.Content, '"session_id":"([^"]+)"')
$sessionId = if ($sessionMatch.Success) { $sessionMatch.Groups[1].Value } else { "" }

$me = Invoke-Http -Uri "$api/api/auth/me" -Headers @{ Authorization = "Bearer $sessionId" }
Assert-Status "/me with valid token returns 200" 200 $me.StatusCode
Assert-Contains "/me returns email" "test@example.com" $me.Content

Assert-Status "/me with invalid token returns 401" 401 ((Invoke-Http -Uri "$api/api/auth/me" -Headers @{ Authorization = "Bearer invalid-token" }).StatusCode)
Assert-Status "/me with no token returns 401" 401 ((Invoke-Http -Uri "$api/api/auth/me").StatusCode)
Write-Host ""

Write-Host "[ 3 ] Products"
$seed = Invoke-Http -Uri "$api/api/products/seed" -Method "POST"
Assert-Status "seed returns 200" 200 $seed.StatusCode
Assert-Contains "seed confirms products created" "Seeded" $seed.Content

# Seeding again must not duplicate the catalog
$seedAgain = Invoke-Http -Uri "$api/api/products/seed" -Method "POST"
Assert-Status "second seed returns 200" 200 $seedAgain.StatusCode
Assert-Contains "second seed creates nothing" '"created":0' $seedAgain.Content

$list = Invoke-Http -Uri "$api/api/products"
Assert-Status "list products returns 200" 200 $list.StatusCode
Assert-Contains "list returns products array" "products" $list.Content
Assert-Contains "list includes seeded product" "Coffee" $list.Content

# Bad input is a 400, not a 500
$badJson = Invoke-Http -Uri "$api/api/products" -Method "POST" -ContentType "application/json" -Body '{not json'
Assert-Status "malformed JSON returns 400" 400 $badJson.StatusCode
$badPrice = Invoke-Http -Uri "$api/api/products" -Method "POST" -ContentType "application/json" -Body '{"name":"Bad","price":"9.99"}'
Assert-Status "string price returns 400" 400 $badPrice.StatusCode

# Unknown ids: 404 on every method, and non-numeric ids never reach the database
Assert-Status "update of unknown product returns 404" 404 ((Invoke-Http -Uri "$api/api/products/999999999" -Method "PUT" -ContentType "application/json" -Body '{"stock":1}').StatusCode)
Assert-Status "delete of unknown product returns 404" 404 ((Invoke-Http -Uri "$api/api/products/999999999" -Method "DELETE").StatusCode)
Assert-Status "non-numeric product id returns 404" 404 ((Invoke-Http -Uri "$api/api/products/12abc").StatusCode)

$headerKeys = @($list.Headers.Keys | ForEach-Object { $_.ToLowerInvariant() })
if ($headerKeys -contains "x-products-cache") {
    Pass "list response includes X-Products-Cache header"
} else {
    Fail "list response missing X-Products-Cache header"
}

$createProduct = Invoke-Http -Uri "$api/api/products" -Method "POST" -ContentType "application/json" -Body '{"name":"Test Widget","description":"A test product","price":9.99,"category":"test","stock":5}'
Assert-Status "create product returns 201" 201 $createProduct.StatusCode
Assert-Contains "create returns product id" '"id"' $createProduct.Content

$productIdMatch = [regex]::Match($createProduct.Content, '"id":(\d+)')
$productId = if ($productIdMatch.Success) { $productIdMatch.Groups[1].Value } else { "" }

$single = Invoke-Http -Uri "$api/api/products/$productId"
Assert-Status "get single product returns 200" 200 $single.StatusCode
Assert-Contains "get single returns correct product" "Test Widget" $single.Content

$update = Invoke-Http -Uri "$api/api/products/$productId" -Method "PUT" -ContentType "application/json" -Body '{"price":19.99,"stock":10}'
Assert-Status "update product returns 200" 200 $update.StatusCode
Assert-Contains "update confirms success" "updated" $update.Content

$verify = Invoke-Http -Uri "$api/api/products/$productId"
Assert-Contains "updated price reflected" "19.99" $verify.Content

$delete = Invoke-Http -Uri "$api/api/products/$productId" -Method "DELETE"
Assert-Status "delete product returns 200" 200 $delete.StatusCode
Assert-Contains "delete confirms success" "deleted" $delete.Content
Assert-Status "deleted product returns 404" 404 ((Invoke-Http -Uri "$api/api/products/$productId").StatusCode)
Write-Host ""

Write-Host "[ 4 ] Queue Consumer"
if (Get-Command wrangler -ErrorAction SilentlyContinue) {
    $queueInfo = (& wrangler queues info demo-order-processing 2>$null | Out-String)
    $m = [regex]::Match($queueInfo, 'Number of Consumers:\s*(\d+)')
    if ($m.Success -and [int]$m.Groups[1].Value -ge 1) {
        Pass "queue has active consumer(s): $($m.Groups[1].Value)"
    } else {
        Fail "queue has no consumers (orders will remain queued)"
    }
} else {
    Write-Host "  SKIP  wrangler not installed; queue consumer check skipped"
}
Write-Host ""

Write-Host "[ 5 ] Orders"
$products = (Invoke-Http -Uri "$api/api/products").Content
$firstIdMatch = [regex]::Match($products, '"id":(\d+)')
if ($firstIdMatch.Success) {
    $firstId = $firstIdMatch.Groups[1].Value
    $createOrder = Invoke-Http -Uri "$api/api/orders" -Method "POST" -ContentType "application/json" -Body "{`"customer_id`":`"test-customer`",`"items`": [{`"product_id`":$firstId,`"quantity`":1,`"unit_price`":24.99}],`"total`":24.99}"
    Assert-Status "create order returns 200" 200 $createOrder.StatusCode
    Assert-Contains "order returns order_id" "order_id" $createOrder.Content
    Assert-Contains "order status is queued" "queued" $createOrder.Content

    $orderIdMatch = [regex]::Match($createOrder.Content, '"order_id":"([^"]+)"')
    if ($orderIdMatch.Success) {
        if (Wait-ForOrderInAdmin -AdminBase $admin -OrderId $orderIdMatch.Groups[1].Value) {
            Pass "queued order appears in admin orders"
        } else {
            Fail "queued order did not appear in admin orders within 30s"
        }
    } else {
        Fail "could not parse order_id from create order response"
    }
} else {
    Fail "create order (no products available to order)"
}

Assert-Status "order missing items returns 400" 400 ((Invoke-Http -Uri "$api/api/orders" -Method "POST" -ContentType "application/json" -Body '{"customer_id":"test"}').StatusCode)
Write-Host ""

Write-Host "[ 6 ] Upload"
$tmpFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tmpFile -Value ("test file content " + (Get-Date)) -NoNewline

$upload = Invoke-Http -Uri "$api/api/upload" -Method "POST" -Form @{ file = Get-Item $tmpFile }
Assert-Status "file upload returns 200" 200 $upload.StatusCode
Assert-Contains "upload returns filename" "filename" $upload.Content
Assert-Contains "upload returns url" "api.$zoneName/api/upload/" $upload.Content

# The returned URL serves the same bytes back
$uploadUrl = try { ($upload.Content | ConvertFrom-Json).url } catch { "" }
$expected = Get-Content -Path $tmpFile -Raw
$downloaded = ""
if ($uploadUrl) {
    # application/octet-stream comes back as bytes
    $body = (Invoke-Http -Uri $uploadUrl).Content
    $downloaded = if ($body -is [byte[]]) { [Text.Encoding]::UTF8.GetString($body) } else { [string]$body }
}
if ($uploadUrl -and $downloaded -eq $expected) {
    Pass "uploaded file downloads from its url"
} else {
    Fail "uploaded file downloads from its url"
}
Remove-Item $tmpFile -Force

Assert-Status "upload with no file returns 400" 400 ((Invoke-Http -Uri "$api/api/upload" -Method "POST").StatusCode)
Write-Host ""

Write-Host "[ 6b ] AI Gateway"
$summary = Invoke-Http -Uri "$api/api/products/summary"
if ($summary.StatusCode -eq 200) {
    Pass "products summary returns 200"
    Assert-Contains "summary response includes gateway id" "demo-ai-gateway" $summary.Content
    Assert-Contains "summary response includes model" "llama" $summary.Content
} elseif ($summary.StatusCode -eq 503) {
    Write-Host "  SKIP  AI binding unavailable (503); Workers AI not enabled on account?"
} else {
    Fail "products summary returned unexpected HTTP $($summary.StatusCode)"
}
Write-Host ""

Write-Host "[ 7 ] Admin Panel"

# waf.tf challenges admin.<zone> for IPs outside admin_allowlist_cidr.
$probe = Invoke-Http -Uri "$admin/"
if ($probe.Headers["cf-mitigated"] -eq "challenge") {
    Write-Host "  FAIL  admin.$zoneName is challenged by the WAF: add your IP to admin_allowlist_cidr and re-apply"
    exit 1
}

Assert-Status "admin over plain HTTP redirects to HTTPS" 301 ((Invoke-Http -Uri "http://admin.$zoneName/" -NoRedirect).StatusCode)
Assert-Status "cross-site POST /reset is refused" 403 ((Invoke-Http -Uri "$admin/reset" -Method "POST" -User "admin" -Password $script:AdminPassword -Headers @{ Origin = "https://evil.example" }).StatusCode)
Assert-Status "admin without auth returns 401" 401 ((Invoke-Http -Uri "$admin/").StatusCode)
Assert-Status "admin with wrong password returns 401" 401 ((Invoke-Http -Uri "$admin/" -User "admin" -Password "wrongpassword").StatusCode)

$dash = Invoke-Http -Uri "$admin/" -User "admin" -Password $script:AdminPassword
Assert-Status "admin dashboard returns 200" 200 $dash.StatusCode
Assert-Contains "dashboard returns HTML" "Demo Platform Admin" $dash.Content

$stats = Invoke-Http -Uri "$admin/api/stats" -User "admin" -Password $script:AdminPassword
Assert-Status "admin stats returns 200" 200 $stats.StatusCode
Assert-Contains "stats returns products count" "products" $stats.Content
Assert-Contains "stats returns orders count" "orders" $stats.Content
Assert-Contains "stats returns revenue" "revenue" $stats.Content

$adminProducts = Invoke-Http -Uri "$admin/api/products" -User "admin" -Password $script:AdminPassword
Assert-Status "admin products returns 200" 200 $adminProducts.StatusCode
Assert-Contains "admin products returns array" "products" $adminProducts.Content

$adminOrders = Invoke-Http -Uri "$admin/api/orders" -User "admin" -Password $script:AdminPassword
Assert-Status "admin orders returns 200" 200 $adminOrders.StatusCode
Assert-Contains "admin orders returns array" "orders" $adminOrders.Content

Write-Host ""
$total = $script:Pass + $script:Fail
Write-Host "================================================"
Write-Host " Results: $($script:Pass)/$total passed"
Write-Host "================================================"

if ($script:Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:"
    foreach ($e in $script:Errors) {
        Write-Host "  - $e"
    }
    exit 1
} else {
    Write-Host ""
    Write-Host "All tests passed."
    exit 0
}
