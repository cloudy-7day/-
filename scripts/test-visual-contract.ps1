$ErrorActionPreference = "Stop"
$css = Get-Content -Raw -Encoding UTF8 "styles.css"
$js = Get-Content -Raw -Encoding UTF8 "app.js"
$motion = Get-Content -Raw -Encoding UTF8 "motion-core.js"

if ($css -notmatch '--display-font:\s*"Source Han Serif SC Heavy Local"') { throw "Display headings must use the bundled Source Han Serif Heavy face." }
if ($css -notmatch '--body-font:\s*"LXGW WenKai Screen"') { throw "Body copy must use the local LXGW screen font." }
if ($css -notmatch '\.favorite-toggle\[aria-pressed="true"\][\s\S]*?color:\s*var\(--seal\)') { throw "Saved items must use the seal-color state." }
if ($css -notmatch '\.index-entry\s*\{[\s\S]*?position:\s*relative' -or $css -notmatch '\.index-favorite\s*\{[\s\S]*?position:\s*absolute') {
  throw "Index favorite controls must have an independent non-nested layout."
}
if ($css -notmatch 'height:\s*142vh') { throw "The B intro journey must finish within one normal wheel gesture." }
if ($css -match 'scroll-snap') { throw "CSS scroll snap must not compete with the scene controller." }
if ($motion -notmatch 'durationMs\s*=\s*1150') { throw "The selected B duration must remain 1150ms." }
if ($motion -notmatch 'yVh:\s*clean\(-38' -or $motion -notmatch 'yVh:\s*clean\(34') { throw "Approved title exit and card entry distances are missing." }
if ($motion -notmatch 'saturation:\s*clean\(0\.08\s*\+\s*0\.92') { throw "Cards must regain full color while entering." }
if ($css -notmatch '\.index-highlight[\s\S]*-webkit-line-clamp:\s*2') { throw "Index highlights must render in at most two lines." }
if ($css -notmatch 'prefers-reduced-motion:\s*reduce') { throw "Missing reduced-motion fallback." }
if ($css -notmatch 'word-break:\s*break-all' -or $css -notmatch 'max-width:\s*4\.5em') { throw "Mobile hero title must wrap within the viewport." }
if ($js -notmatch 'prefers-reduced-motion' -or $js -notmatch 'animateHomeScene') { throw "Motion preference and B controller wiring are missing." }
if ($css -notmatch '\.hero-title\s*\{[\s\S]*?letter-spacing:\s*0\.08em') { throw "Desktop hero title spacing must be 0.08em." }
if ($css -notmatch '\.category-heading\s*\{[\s\S]*?min-height:\s*210px[\s\S]*?padding-bottom:\s*46px') {
  throw "Category heading must use the balanced title band."
}
if ($css -notmatch '\.category-heading h1\s*\{[\s\S]*?font-size:\s*clamp\(72px,\s*7vw,\s*140px\)') {
  throw "Category title must use the balanced scale."
}
if ($css -notmatch '\.category-index\s*\{[\s\S]*?max-width:\s*1400px[\s\S]*?position:\s*relative') {
  throw "Category index must restore the full-width frame."
}
if ($css -notmatch '\.category-index-archive\s*\{[\s\S]*?position:\s*absolute[\s\S]*?right:\s*12px') {
  throw "Category archive selector must occupy the former favorite column."
}
if ($css -notmatch '\.category-index \.index-copy small\s*\{[\s\S]*?font-size:\s*13px') {
  throw "Category metadata must use the balanced scale."
}
if ($css -notmatch '\.category-index \.index-copy strong\s*\{[\s\S]*?font-size:\s*clamp\(30px,\s*2\.8vw,\s*52px\)') {
  throw "Category headlines must use the balanced scale."
}
if ($css -notmatch '\.category-index \.index-highlight\s*\{[\s\S]*?font-size:\s*clamp\(15px,\s*1\.05vw,\s*17px\)') {
  throw "Category summaries must use the balanced scale."
}
if ($css -notmatch '\.theme-card img\s*\{[\s\S]*?top:\s*4%[\s\S]*?right:\s*2%[\s\S]*?width:\s*min\(62%,\s*280px\)[\s\S]*?height:\s*58%') {
  throw "Volume illustrations must use one fixed desktop frame."
}
if ($css -match '\.theme-card:hover img\s*\{[^}]*transform:') { throw "Hover must not move or rotate volume illustrations." }
if ($css -notmatch '\.source-actions a:first-child\s*\{[\s\S]*?background:\s*transparent[\s\S]*?color:\s*var\(--ink\)') {
  throw "The source link must use the transparent outlined treatment."
}
if ($css -notmatch '\.theme-card-copy strong\s*\{[^}]*font-weight:\s*900') { throw "Volume titles must use the heavy display face." }
if ($css -notmatch '\.category-heading h1\s*\{[^}]*font-weight:\s*900[^}]*text-align:\s*center') {
  throw "Category titles must be centered and bold."
}
if ($css -notmatch '\.detail-hero h1\s*\{[^}]*font-weight:\s*900') { throw "Detail article titles must use the heavy display face." }
if ($css -notmatch '\.detail-primary h2,[\s\S]*?\.detail-secondary h2\s*\{[^}]*font-weight:\s*900') {
  throw "Detail section headings must be bold."
}

Write-Host "Visual contract tests passed."
