$ErrorActionPreference = "Stop"
$css = Get-Content -Raw -Encoding UTF8 "styles.css"
$js = Get-Content -Raw -Encoding UTF8 "app.js"
$motion = Get-Content -Raw -Encoding UTF8 "motion-core.js"

if ($css -notmatch '--display-font') { throw "Missing display font stack." }
if ($css -notmatch '--body-font:\s*"LXGW WenKai Screen"') { throw "Body copy must use the local LXGW screen font." }
if ($css -notmatch 'height:\s*142vh') { throw "The B intro journey must finish within one normal wheel gesture." }
if ($css -match 'scroll-snap') { throw "CSS scroll snap must not compete with the scene controller." }
if ($motion -notmatch 'durationMs\s*=\s*1150') { throw "The selected B duration must remain 1150ms." }
if ($motion -notmatch 'yVh:\s*clean\(-38' -or $motion -notmatch 'yVh:\s*clean\(34') { throw "Approved title exit and card entry distances are missing." }
if ($motion -notmatch 'saturation:\s*clean\(0\.08\s*\+\s*0\.92') { throw "Cards must regain full color while entering." }
if ($css -notmatch '\.index-highlight[\s\S]*-webkit-line-clamp:\s*2') { throw "Index highlights must render in at most two lines." }
if ($css -notmatch 'prefers-reduced-motion:\s*reduce') { throw "Missing reduced-motion fallback." }
if ($css -notmatch 'word-break:\s*break-all' -or $css -notmatch 'max-width:\s*4\.5em') { throw "Mobile hero title must wrap within the viewport." }
if ($js -notmatch 'prefers-reduced-motion' -or $js -notmatch 'animateHomeScene') { throw "Motion preference and B controller wiring are missing." }

Write-Host "Visual contract tests passed."
