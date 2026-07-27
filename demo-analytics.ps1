#!/usr/bin/env pwsh

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir/scripts/demos/demo-analytics.ps1" @args
exit $LASTEXITCODE
