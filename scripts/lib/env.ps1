# Dot-sourced by the demo scripts. Loads credentials into the environment from
# the gitignored secrets/ store, unless they are already set. Never echoes values.
#   secrets/cloudflare_api_token -> CLOUDFLARE_API_TOKEN   (provider, wrangler, R2 cleanup)
#   secrets/admin_password       -> TF_VAR_admin_password  (admin panel Worker secret)
# Sync with: env.sh

$secretsDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "secrets"

$tokenFile = Join-Path $secretsDir "cloudflare_api_token"
if (-not $env:CLOUDFLARE_API_TOKEN -and (Test-Path $tokenFile)) {
    $env:CLOUDFLARE_API_TOKEN = (Get-Content $tokenFile -Raw).Trim()
}

$passwordFile = Join-Path $secretsDir "admin_password"
if (-not $env:TF_VAR_admin_password -and (Test-Path $passwordFile)) {
    $env:TF_VAR_admin_password = (Get-Content $passwordFile -Raw).Trim()
}
