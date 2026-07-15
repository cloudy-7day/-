$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "daily-update-support.ps1")

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$dataPath = Join-Path $root "data"
$archivePath = Join-Path $dataPath "archive"
$current = Get-Content -Raw -Encoding UTF8 (Join-Path $dataPath "articles.json") | ConvertFrom-Json
$ledger = Read-ArticleLedger -Path (Join-Path $dataPath "seen-articles.json")
$archiveFiles = @(Get-ChildItem -LiteralPath $archivePath -Filter "*.json" |
  Where-Object { $_.BaseName -match '^\d{4}-\d{2}-\d{2}$' } |
  Sort-Object BaseName)
Assert-True ($archiveFiles.Count -gt 0) "At least one rebuilt archive must exist."

$allArchivedArticles = @()
foreach ($file in $archiveFiles) {
  $payload = Get-Content -Raw -Encoding UTF8 $file.FullName | ConvertFrom-Json
  Assert-True ($payload.issueDate -eq $file.BaseName) "Archive filename and issueDate must match: $($file.Name)"
  Assert-True (@($payload.articles).Count -eq 7) "Every archive must contain exactly seven articles: $($file.Name)"
  Assert-True (@($payload.articles | Where-Object category -eq "international").Count -eq 3) "Every archive must contain three international articles."
  Assert-True (@($payload.articles | Where-Object { $_.category -in @("ai", "paper") }).Count -eq 4) "Every archive must contain four deep-reading articles."
  foreach ($article in @($payload.articles)) {
    Assert-True (Test-ChineseDisplayTitle -Title ([string]$article.translations.zh.title)) "Chinese mode title is missing or predominantly English: $($article.id)"
    Assert-True ($article.translations.zh.highlight -and $article.translations.zh.summary -and $article.translations.zh.failureAnalysis) "Chinese translation is incomplete: $($article.id)"
    Assert-True ($article.translations.en.title -and $article.translations.en.highlight -and $article.translations.en.summary -and $article.translations.en.failureAnalysis) "English translation is incomplete: $($article.id)"
    Assert-True (-not (Test-ForbiddenHighlightOpening -Text ([string]$article.translations.zh.highlight))) "Chinese highlight is template-styled: $($article.id)"
  }
  $allArchivedArticles += @($payload.articles)
}

Assert-ArticleSetUnique -Articles $allArchivedArticles -Ledger $ledger
$todayArchive = Get-Content -Raw -Encoding UTF8 (Join-Path $archivePath "$($current.issueDate).json") | ConvertFrom-Json
Assert-True (($current | ConvertTo-Json -Compress -Depth 20) -eq ($todayArchive | ConvertTo-Json -Compress -Depth 20)) "Current data must match its archive."
$index = Get-Content -Raw -Encoding UTF8 (Join-Path $archivePath "index.json") | ConvertFrom-Json
Assert-True (@($index.archives).Count -eq $archiveFiles.Count) "Archive index must list every valid archive exactly once."

Write-Host "Published article data tests passed."
