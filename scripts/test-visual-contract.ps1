$ErrorActionPreference = "Stop"
$css = Get-Content -Raw "styles.css"
$js = Get-Content -Raw "app.js"
if ($css -notmatch '--display-font') { throw "Missing display font stack" }
if ($css -notmatch 'height:\s*220vh') { throw "Intro must have a 120vh scroll journey" }
if ($css -notmatch 'translateY\(calc\(var\(--intro-progress\).*?-24vh') { throw "Hero must move upward" }
if ($css -notmatch 'prefers-reduced-motion:\s*reduce') { throw "Missing reduced motion fallback" }
if ($css -notmatch 'detail-page.*tabindex.*focus') { throw "Programmatic detail heading focus must not draw a box" }
if ($css -notmatch 'word-break:\s*break-all') { throw "Mobile hero title must wrap within the viewport" }
if ($css -notmatch 'max-width:\s*4\.5em') { throw "Mobile hero title must use a stable four-character line" }
if ($js -notmatch 'updateIntroProgress' -or $js -notmatch '--intro-progress') { throw "Missing scroll progress controller" }
Write-Host "Visual contract tests passed."
