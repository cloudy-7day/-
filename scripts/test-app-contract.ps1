$ErrorActionPreference = "Stop"
$source = Get-Content -Raw "app.js"
@("renderHome", "renderCategory", "renderArticle", "setDetailPage", "hashchange", "archive-select") | ForEach-Object {
  if ($source -notmatch [regex]::Escape($_)) { throw "Missing app contract: $_" }
}
if ($source -notmatch "SiteCore.getSafeArticleUrl") { throw "External links must use SiteCore safety filter" }
if ($source -notmatch "detail-page-toggle") { throw "Detail page must use a real button" }
Write-Host "App contract tests passed."
