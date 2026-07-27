#!/usr/bin/env pwsh

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir/scripts/demos/demo-latency.ps1" @args
exit $LASTEXITCODE
