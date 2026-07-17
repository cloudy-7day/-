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

$legacyFixture = @(1..7 | ForEach-Object { [pscustomobject]@{ category = if ($_ -le 3) { "international" } else { "ai" } } })
$newFixtureCategories = @("domestic", "domestic", "domestic", "international", "international", "ai", "ai", "paper", "paper")
$newFixture = @($newFixtureCategories | ForEach-Object { [pscustomobject]@{ category = $_ } })
Assert-True ((Get-PublishedArchiveShape -Articles $legacyFixture).isValid) "The pure archive-shape helper must accept a legacy seven-item fixture."
Assert-True ((Get-PublishedArchiveShape -Articles $newFixture).isValid) "The pure archive-shape helper must accept a new nine-item fixture."

$allArchivedArticles = @()
foreach ($file in $archiveFiles) {
  $payload = Get-Content -Raw -Encoding UTF8 $file.FullName | ConvertFrom-Json
  $articles = @($payload.articles)
  Assert-True ($payload.issueDate -eq $file.BaseName) "Archive filename and issueDate must match: $($file.Name)"
  $shape = Get-PublishedArchiveShape -Articles $articles
  Assert-True $shape.isValid "Archive composition is invalid for its legacy/new shape: $($file.Name)"
  foreach ($article in $articles) {
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
