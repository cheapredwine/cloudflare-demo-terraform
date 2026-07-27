#!/usr/bin/env pwsh

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$scriptDir/scripts/tests/test.ps1" @args
exit $LASTEXITCODE
