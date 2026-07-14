$ErrorActionPreference = "Stop"
$source = Get-Content -Raw "app.js"
@("renderHome", "renderCategory", "renderArticle", "setDetailPage", "hashchange", "archive-select") | ForEach-Object {
  if ($source -notmatch [regex]::Escape($_)) { throw "Missing app contract: $_" }
}
if ($source -notmatch "SiteCore.getSafeArticleUrl") { throw "External links must use SiteCore safety filter" }
if ($source -notmatch "detail-page-toggle") { throw "Detail page must use a real button" }
if ($source -notmatch "summary-source-label") { throw "Source extracts must render a disclosure label." }
if ($source -notmatch "SiteCore.getSummarySourceLabel") { throw "Disclosure copy must use the tested SiteCore helper." }
Write-Host "App contract tests passed."
