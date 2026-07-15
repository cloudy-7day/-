$ErrorActionPreference = "Stop"

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-Equal {
  param($Actual, $Expected, [string]$Message)
  if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

$resetScript = Join-Path $PSScriptRoot "reset-article-library.ps1"
if (-not (Test-Path -LiteralPath $resetScript)) {
  throw "Missing reset script: $resetScript"
}
. $resetScript

$fixture = Join-Path ([IO.Path]::GetTempPath()) "article-reset-$([guid]::NewGuid().ToString('N'))"
$archive = Join-Path $fixture "archive"
New-Item -ItemType Directory -Path $archive -Force | Out-Null
try {
  [ordered]@{
    issueDate = "2026-07-14"
    articles = @(
      [ordered]@{ title = "Used title"; url = "https://example.com/a?utm_source=test" }
    )
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $fixture "articles.json") -Encoding UTF8
  [ordered]@{
    issueDate = "2026-07-13"
    articles = @(
      [ordered]@{ title = "Used title"; url = "https://example.com/a" },
      [ordered]@{ title = "Second title"; url = "https://example.com/b" }
    )
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $archive "2026-07-13.json") -Encoding UTF8
  [ordered]@{ version = 1; urls = @("https://example.com/older"); titles = @("oldertitle") } |
    ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $fixture "seen-articles.json") -Encoding UTF8

  $null = Reset-ArticleLibrary -DataPath $fixture

  $ledger = Get-Content -Raw -Encoding UTF8 (Join-Path $fixture "seen-articles.json") | ConvertFrom-Json
  Assert-Equal @($ledger.urls).Count 3 "Reset must retain existing identities and add unique visible URLs."
  Assert-Equal @($ledger.titles).Count 3 "Reset must retain existing identities and add unique visible titles."
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixture "articles.json"))) "Reset must remove the visible current payload."
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $archive "2026-07-13.json"))) "Reset must remove dated archives."
  $index = Get-Content -Raw -Encoding UTF8 (Join-Path $archive "index.json") | ConvertFrom-Json
  Assert-Equal @($index.archives).Count 0 "Reset must publish an empty archive index."
} finally {
  if (Test-Path -LiteralPath $fixture) {
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}

Write-Host "Article library reset tests passed."
