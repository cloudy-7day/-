$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "update-daily.ps1"
$source = Get-Content -Raw -Encoding UTF8 $scriptPath

if ($source -match "news-api\.ap\.org|apikey=demo") {
  throw "Default news feeds should not include API-gated AP demo endpoints."
}

if ($source -match 'Invoke-WebRequest\s+-Uri\s+\$link') {
  throw "News collection should not fetch each selected RSS article page during candidate collection."
}

Write-Host "Daily update rule tests passed."
