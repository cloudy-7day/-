$ErrorActionPreference = "Stop"
$source = Get-Content -Raw -Encoding UTF8 "app.js"

@("renderHome", "renderCategory", "renderArticle", "hashchange", "archive-select") | ForEach-Object {
  if ($source -notmatch [regex]::Escape($_)) { throw "Missing app contract: $_" }
}

@("hero-subtitle", "setDetailPage", "detail-page-toggle", "data-detail-page", "detail-progress") | ForEach-Object {
  if ($source -match [regex]::Escape($_)) { throw "Removed interface copy or pagination remains: $_" }
}

if ($source -match 'config\.kicker' -or $source -match '<small>\$\{escapeHtml\(kicker\)\}</small>') {
  throw "Home and category kickers must be removed."
}
if ($source -notmatch "SiteCore.getSafeArticleUrl") { throw "External links must use SiteCore safety filter." }
if ($source -notmatch "SiteCore.getArticleHighlight") { throw "Index cards must use the dedicated highlight field." }
if ($source -notmatch "summary-source-label" -or $source -notmatch "SiteCore.getSummarySourceLabel") { throw "Traceable fallback disclosure must remain on detail pages." }
if ($source -notmatch 'class="detail-content"[\s\S]*detail-summary[\s\S]*association-list[\s\S]*source-actions') { throw "Summary, associations, and source actions must share one detail page." }
if ($source -notmatch "MotionCore.heroFrame" -or $source -notmatch "MotionCore.cardFrame") { throw "The app must consume the tested motion model." }
if ($source -notmatch "cancelAnimationFrame\(activeSceneAnimation\)") { throw "A new scene animation must cancel the previous controller." }
if ($source -notmatch "function animateHomeScene") { throw "The selected B scene controller is missing." }
$domesticNews = -join ([char[]](0x56FD, 0x5185, 0x8981, 0x95FB))
$internationalNews = -join ([char[]](0x56FD, 0x9645, 0x8981, 0x95FB))
@($domesticNews, $internationalNews, "China", "World") | ForEach-Object {
  if ($source -notmatch [regex]::Escape($_)) { throw "Missing combined news section label: $_" }
}
if ($source -notmatch 'filter\([\s\S]*SiteCore\.getDisplayCategory\(article\.category\)[\s\S]*=== category') {
  throw "Category filtering must use SiteCore.getDisplayCategory."
}
if ($source -notmatch 'const displayCategory = SiteCore\.getDisplayCategory\(article\.category\)') {
  throw "Article navigation/config resolution must use SiteCore.getDisplayCategory."
}
if ($source -notmatch 'CATEGORY_CONFIG\[displayCategory\]' -or $source -notmatch '#/category/\$\{displayCategory\}') {
  throw "News article config and back navigation must share the display category."
}
if ($source -notmatch '#/category/news') { throw "News articles must share the #/category/news back route." }

Write-Host "App contract tests passed."
