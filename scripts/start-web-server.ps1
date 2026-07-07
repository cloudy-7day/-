param(
  [int]$Port = 8787
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$public = Join-Path $root "public"
& (Join-Path $PSScriptRoot "sync-public.ps1")

try {
  $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 2
  if ($response.StatusCode -eq 200) {
    Write-Host "Web server is already running on port $Port."
    exit 0
  }
} catch {
  # No server answered, so start one below.
}

$knownPython = "D:\anaconda\python.exe"
if (Test-Path $knownPython) {
  $python = $knownPython
} else {
  $python = (Get-Command python -ErrorAction Stop).Source
}

Start-Process -FilePath $python -ArgumentList @("-m", "http.server", "$Port", "--bind", "0.0.0.0") -WorkingDirectory $public -WindowStyle Hidden
Start-Sleep -Seconds 2

try {
  $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 4
  if ($response.StatusCode -eq 200) {
    Write-Host "Started web server on port $Port."
    exit 0
  }
} catch {
  throw "Tried to start the web server, but it did not answer on port $Port."
}
