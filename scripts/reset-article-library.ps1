param(
  [string]$DataPath = "data"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "daily-update-support.ps1")

function Reset-ArticleLibrary {
  param([string]$DataPath = "data")

  $resolvedData = (Resolve-Path -LiteralPath $DataPath).Path
  $archiveFolder = Join-Path $resolvedData "archive"
  if (-not (Test-Path -LiteralPath $archiveFolder)) {
    New-Item -ItemType Directory -Path $archiveFolder | Out-Null
  }

  $ledgerPath = Join-Path $resolvedData "seen-articles.json"
  $existingLedger = Read-ArticleLedger -Path $ledgerPath
  $urls = @{}
  $titles = @{}
  foreach ($url in @($existingLedger.urls)) { $urls[[string]$url] = $true }
  foreach ($title in @($existingLedger.titles)) { $titles[[string]$title] = $true }

  $payloadFiles = @()
  $currentPath = Join-Path $resolvedData "articles.json"
  if (Test-Path -LiteralPath $currentPath) { $payloadFiles += Get-Item -LiteralPath $currentPath }
  $payloadFiles += @(Get-ChildItem -LiteralPath $archiveFolder -Filter "*.json" |
    Where-Object { $_.BaseName -match '^\d{4}-\d{2}-\d{2}$' })

  foreach ($file in $payloadFiles) {
    $payload = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName | ConvertFrom-Json
    foreach ($article in @($payload.articles)) {
      $url = Get-CanonicalArticleUrl -Url ([string]$article.url)
      $title = Get-NormalizedArticleTitle -Title ([string]$article.title)
      if ($url) { $urls[$url] = $true }
      if ($title) { $titles[$title] = $true }
    }
  }

  $ledger = [ordered]@{
    version = 1
    rebuiltAt = (Get-Date).ToUniversalTime().ToString("o")
    urls = @($urls.Keys | Sort-Object)
    titles = @($titles.Keys | Sort-Object)
  }
  $ledgerTemp = "$ledgerPath.$([guid]::NewGuid().ToString('N')).tmp"
  try {
    $ledger | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ledgerTemp -Encoding UTF8
    Move-Item -LiteralPath $ledgerTemp -Destination $ledgerPath -Force
  } finally {
    if (Test-Path -LiteralPath $ledgerTemp) { Remove-Item -LiteralPath $ledgerTemp -Force }
  }

  foreach ($file in $payloadFiles | Where-Object { $_.DirectoryName -eq $archiveFolder }) {
    Remove-Item -LiteralPath $file.FullName -Force
  }
  if (Test-Path -LiteralPath $currentPath) {
    Remove-Item -LiteralPath $currentPath -Force
  }

  $indexPath = Join-Path $archiveFolder "index.json"
  $indexTemp = "$indexPath.$([guid]::NewGuid().ToString('N')).tmp"
  try {
    [ordered]@{
      updatedAt = (Get-Date).ToUniversalTime().ToString("o")
      archives = @()
    } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $indexTemp -Encoding UTF8
    Move-Item -LiteralPath $indexTemp -Destination $indexPath -Force
  } finally {
    if (Test-Path -LiteralPath $indexTemp) { Remove-Item -LiteralPath $indexTemp -Force }
  }

  Write-Host "Article library reset: tombstoned $($urls.Count) URLs and $($titles.Count) titles."
  return $ledger
}

if ($MyInvocation.InvocationName -ne ".") {
  Reset-ArticleLibrary -DataPath $DataPath | Out-Null
}
