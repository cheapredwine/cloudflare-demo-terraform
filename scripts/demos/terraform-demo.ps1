#!/usr/bin/env pwsh

# Terraform Demo Script for Cloudflare Demo Platform (PowerShell)
# Sync with: terraform-demo.sh

$ErrorActionPreference = "Stop"

# Load credentials from the gitignored secrets/ store (see secrets/README.md).
. (Join-Path $PSScriptRoot "../lib/env.ps1")

function Show-Help {
@"
Terraform Demo Script
=====================

Usage: ./terraform-demo.ps1 [ACTION] [OPTIONS]

Actions:
  idempotency     Show declarative idempotency (apply twice, 0 changes second time)
  drift-detect    Detect manual changes in dashboard and reconcile
  state-inspect   Show state list, show resource details, output values
  targeted        Deploy only one resource using -target
  plan-file       Save plan to file and apply exact plan
  workspaces      Create staging workspace and switch between them
  refresh-only    Detect drift without making changes
  taint-replace   Force recreation of a single resource with -replace
  var-override    Override a variable on the command line (LB failover toggle)
  graph           Generate visual dependency graph
  all             Run all demos sequentially
  help            Show this help

Examples:
  ./terraform-demo.ps1 idempotency
  ./terraform-demo.ps1 drift-detect
  ./terraform-demo.ps1 all
"@ | Write-Host
}

function Get-TfvarsValue {
    param([string]$Key)
    if (-not (Test-Path "terraform.tfvars")) { return "" }
    $line = Get-Content "terraform.tfvars" | Where-Object { $_ -match "^\s*$Key\s*=" } | Select-Object -First 1
    if ($line -and $line -match '"([^"]+)"') { return $matches[1] }
    return ""
}

function Check-Prereqs {
    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        throw "Terraform required. Install: https://terraform.io/downloads"
    }
    if (-not (Test-Path "terraform.tfvars")) {
        throw "terraform.tfvars not found. Create from terraform.tfvars.example"
    }
    $script:ZoneName = Get-TfvarsValue "zone_name"
    Write-Host "Zone: $script:ZoneName"
    Write-Host ""
}

function Print-Header([string]$Title) {
    Write-Host ""
    Write-Host "==============================================================="
    Write-Host "  $Title"
    Write-Host "==============================================================="
    Write-Host ""
}

function Press-Enter {
    Write-Host ""
    [void](Read-Host "Press Enter to continue")
    Write-Host ""
}

function Run-Cmd([string]$Cmd) {
    Write-Host "`$ $Cmd"
    Invoke-Expression $Cmd
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $Cmd"
    }
    Write-Host ""
}

function Demo-Idempotency {
    Print-Header "DEMO: Idempotency"
    Write-Host "Terraform is declarative. Running apply twice should produce"
    Write-Host "zero changes the second time."
    Press-Enter
    Write-Host "First apply (creates infrastructure):"
    Run-Cmd "terraform apply -auto-approve"
    Press-Enter
    Write-Host "Second apply (should show 0 changes):"
    Run-Cmd "terraform apply -auto-approve"
}

function Demo-DriftDetect {
    Print-Header "DEMO: Drift Detection"
    Write-Host "Deploying baseline infrastructure..."
    Press-Enter
    Run-Cmd "terraform apply -auto-approve"
    Write-Host ""
    Write-Host "ACTION REQUIRED:"
    Write-Host "Go to https://dash.cloudflare.com and manually change something"
    Write-Host "in the $script:ZoneName zone, then continue."
    Press-Enter
    Write-Host "Detecting drift:"
    Run-Cmd "terraform plan"
    Write-Host "Reconciling back to desired state:"
    Run-Cmd "terraform apply -auto-approve"
}

function Demo-StateInspect {
    Print-Header "DEMO: State Inspection"
    Press-Enter
    Run-Cmd "terraform state list"
    Press-Enter
    Run-Cmd "terraform state show cloudflare_d1_database.products"
    Press-Enter
    Run-Cmd "terraform output"
    Press-Enter
    Run-Cmd "terraform output api_gateway_url"
    Press-Enter
    Run-Cmd "terraform output -json"
}

function Demo-Targeted {
    Print-Header "DEMO: Targeted Operations"
    Press-Enter
    Run-Cmd "terraform plan -target=cloudflare_worker_version.products_api"
    Press-Enter
    Run-Cmd "terraform apply -target=cloudflare_worker_version.products_api -auto-approve"
}

function Demo-PlanFile {
    Print-Header "DEMO: Plan Files"
    Press-Enter
    Run-Cmd "terraform plan -out=tfplan"
    Press-Enter
    Run-Cmd "terraform show tfplan"
    Press-Enter
    Run-Cmd "terraform apply tfplan"
    Press-Enter
    Run-Cmd "Remove-Item -Force tfplan"
}

function Demo-Workspaces {
    Print-Header "DEMO: Workspace Isolation"
    Press-Enter
    Run-Cmd "terraform workspace show"
    Press-Enter
    Run-Cmd "terraform workspace new staging; if (`$LASTEXITCODE -ne 0) { terraform workspace select staging }"
    Press-Enter
    Run-Cmd "terraform workspace list"
    Press-Enter
    Run-Cmd "terraform plan"
    Write-Host "Don't apply it: the resource names are fixed (demo-products, ...), so"
    Write-Host "staging would collide with default. Real projects put"
    Write-Host "terraform.workspace into names, or use one directory per environment."
    Press-Enter
    Run-Cmd "terraform workspace select default"
    Run-Cmd "terraform workspace delete staging"
}

function Demo-RefreshOnly {
    Print-Header "DEMO: Refresh-Only"
    Press-Enter
    Run-Cmd "terraform apply -refresh-only -auto-approve"
}

function Demo-TaintReplace {
    Print-Header "DEMO: Taint & Force Replace"
    Press-Enter
    Write-Host "-replace=<address> plans a destroy + create for that one resource."
    Write-Host "(It replaces the older 'terraform taint', which edits state first.)"
    Press-Enter
    Run-Cmd "terraform plan -replace=cloudflare_worker_version.products_api"
    Press-Enter
    Run-Cmd "terraform apply -replace=cloudflare_worker_version.products_api -auto-approve"
}

function Demo-VarOverride {
    Print-Header "DEMO: Variable Overrides"
    Write-Host "Variables can be set in terraform.tfvars, as TF_VAR_<name> environment"
    Write-Host "variables, or with -var. -var wins over the other two."
    Write-Host ""
    Write-Host "primary_origin_enabled defaults to true. Override it to drain the"
    Write-Host "primary load-balancer pool (see load_balancer.tf):"
    Press-Enter
    Run-Cmd "terraform plan -var=primary_origin_enabled=false"
    Write-Host "Notice: only the primary pool's origin changes (enabled: true -> false)."
    Write-Host "Apply it to watch app.$script:ZoneName fail over to the secondary pool."
}

function Demo-Graph {
    Print-Header "DEMO: Resource Dependency Graph"
    Press-Enter
    if (Get-Command dot -ErrorAction SilentlyContinue) {
        Run-Cmd "terraform graph | dot -Tpng > terraform-graph.png"
        Run-Cmd "Get-Item terraform-graph.png"
    } else {
        Run-Cmd "terraform graph"
    }
}

function Run-All {
    Write-Host ""
    Write-Host "RUNNING ALL TERRAFORM DEMOS"
    Write-Host "Estimated time: 10-15 minutes"
    $reply = Read-Host "Continue? (y/N)"
    if ($reply -notmatch '^[Yy]$') {
        Write-Host "Cancelled"
        exit 0
    }
    Check-Prereqs
    Demo-Idempotency
    Demo-StateInspect
    Demo-Targeted
    Demo-PlanFile
    Demo-RefreshOnly
    Demo-VarOverride
    Demo-Graph
    Demo-Workspaces
}

$action = if ($args.Count -gt 0) { $args[0] } else { "help" }

switch ($action) {
    "idempotency" { Check-Prereqs; Demo-Idempotency }
    "drift-detect" { Check-Prereqs; Demo-DriftDetect }
    "state-inspect" { Check-Prereqs; Demo-StateInspect }
    "targeted" { Check-Prereqs; Demo-Targeted }
    "plan-file" { Check-Prereqs; Demo-PlanFile }
    "workspaces" { Check-Prereqs; Demo-Workspaces }
    "refresh-only" { Check-Prereqs; Demo-RefreshOnly }
    "taint-replace" { Check-Prereqs; Demo-TaintReplace }
    "var-override" { Check-Prereqs; Demo-VarOverride }
    "graph" { Check-Prereqs; Demo-Graph }
    "all" { Run-All }
    "help" { Show-Help }
    "--help" { Show-Help }
    "-h" { Show-Help }
    default { Show-Help }
}
