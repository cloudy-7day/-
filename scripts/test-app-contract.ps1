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

Write-Host "App contract tests passed."
