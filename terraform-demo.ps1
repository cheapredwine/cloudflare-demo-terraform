#!/usr/bin/env pwsh

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir/scripts/demos/terraform-demo.ps1" @args
exit $LASTEXITCODE
