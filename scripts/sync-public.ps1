$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$public = Join-Path $root "public"
$publicData = Join-Path $public "data"
$publicArchive = Join-Path $publicData "archive"

if (-not (Test-Path $public)) {
  New-Item -ItemType Directory -Path $public | Out-Null
}
if (-not (Test-Path $publicData)) {
  New-Item -ItemType Directory -Path $publicData | Out-Null
}
if (-not (Test-Path $publicArchive)) {
  New-Item -ItemType Directory -Path $publicArchive | Out-Null
}

Copy-Item -Path (Join-Path $root "index.html") -Destination (Join-Path $public "index.html") -Force
Copy-Item -Path (Join-Path $root "styles.css") -Destination (Join-Path $public "styles.css") -Force
Copy-Item -Path (Join-Path $root "app.js") -Destination (Join-Path $public "app.js") -Force
Copy-Item -Path (Join-Path $root "data/articles.json") -Destination (Join-Path $publicData "articles.json") -Force

if (Test-Path (Join-Path $root "data/archive")) {
  Copy-Item -Path (Join-Path $root "data/archive/*.json") -Destination $publicArchive -Force
}

Write-Host "Synced public website folder."
