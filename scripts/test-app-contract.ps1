$ErrorActionPreference = "Stop"
$source = Get-Content -Raw -Encoding UTF8 "app.js"

@("renderHome", "renderCategory", "renderArticle", "renderFavorites", "renderFavoriteArticle", "hashchange", "archive-select") | ForEach-Object {
  if ($source -notmatch [regex]::Escape($_)) { throw "Missing app contract: $_" }
}

@("hero-subtitle", "setDetailPage", "detail-page-toggle", "data-detail-page", "detail-progress") | ForEach-Object {
  if ($source -match [regex]::Escape($_)) { throw "Removed interface copy or pagination remains: $_" }
}

@("shanhaijing:favorites:v1", "data-favorite-id", "data-export-favorites", "data-import-favorites", "SiteCore.createFavoriteSnapshot", "SiteCore.parseFavoriteStore", "SiteCore.mergeFavoriteStores", "showSaveFilePicker", "createWritable", "navigator.locks", "data-connect-favorites-file", "data-sync-favorites-file", "data-disconnect-favorites-file") | ForEach-Object {
  if ($source -notmatch [regex]::Escape($_)) { throw "Missing favorites contract: $_" }
}
if ($source -match 'function updateClock' -or $source -match 'America/Los_Angeles') {
  throw "The Los Angeles clock must not remain in the app."
}
if ($source -notmatch 'class="home-favorites-link"\s+href="#/favorites"' -or $source -notmatch 'querySelectorAll\("\[data-favorites-count\]"\)') {
  throw "The home volume gate must expose a live favorites entry and count."
}
if ($source -match '<a[^>]*class="index-card"[\s\S]*?<button[^>]*data-favorite-id[\s\S]*?</a>') {
  throw "Favorite buttons must not be nested inside article links."
}
if ($source -notmatch 'renderIndexCard\(article, index, position, \{ showFavorite: false \}\)') {
  throw "Category rows must suppress row-level favorite controls."
}
if ($source -notmatch 'class="category-index-archive"[\s\S]*?renderArchiveControls') {
  throw "Category archive controls must occupy the former favorite action column."
}
if ($source -notmatch 'state\.favorites\.map\(\(article, position\) => renderIndexCard\(article, position, position, \{') {
  throw "Favorites rows must retain their row-level favorite controls."
}

$dailyNine = -join ([char[]](0x6BCF, 0x65E5, 0x4E5D, 0x95FB))
$enterDailyNine = -join ([char[]](0x8FDB, 0x5165, 0x6BCF, 0x65E5, 0x4E5D, 0x95FB))
$dailySeven = -join ([char[]](0x6BCF, 0x65E5, 0x4E03, 0x95FB))
$enterDailySeven = -join ([char[]](0x8FDB, 0x5165, 0x6BCF, 0x65E5, 0x4E03, 0x95FB))
foreach ($requiredLabel in @($dailyNine, $enterDailyNine, 'Nine Daily Notes', "Enter today's nine notes")) {
  if ($source -notmatch [regex]::Escape($requiredLabel)) { throw "Missing nine-item brand label: $requiredLabel" }
}
foreach ($staleLabel in @($dailySeven, $enterDailySeven, 'Seven Daily Notes', "Enter today's seven notes")) {
  if ($source -match [regex]::Escape($staleLabel)) { throw "Stale seven-item brand label remains: $staleLabel" }
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
@($domesticNews, $internationalNews) | ForEach-Object {
  if ($source -match [regex]::Escape($_)) { throw "News subsection label must not be rendered: $_" }
}
if ($source -match 'newsSectionCopy|category-section') {
  throw "Domestic and international news must render as one continuous index."
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
if ($source -notmatch 'data-back-gate' -or $source -notmatch 'state\.returnToGate\s*=\s*true') {
  throw "Returning from a category must target the three-volume gate."
}
if ($source -notmatch 'returnToGate[\s\S]*renderHomeScene\(1\)') {
  throw "Home rendering must restore the completed gate scene."
}
if ($source -match '<p class="theme-date">\$\{t\("daily"\)\}') {
  throw "The volume gate must not repeat the daily-nine label."
}
if ($source -notmatch '<p class="theme-date">\$\{escapeHtml\(formatDate\(state\.issueDate\)\)\}</p>') {
  throw "The volume gate must retain the issue date without the daily-nine label."
}

Write-Host "App contract tests passed."
