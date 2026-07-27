#!/usr/bin/env pwsh

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir/scripts/lifecycle/run-demo.ps1" @args
exit $LASTEXITCODE
