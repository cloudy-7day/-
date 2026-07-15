$ErrorActionPreference = "Stop"
$utf8 = [System.Text.Encoding]::UTF8
$html = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\index.html"), $utf8)
$sync = Get-Content -Raw "scripts/sync-public.ps1"
$siteName = -join ([char[]](0x5c71,0x6d77,0x7ecf,0x7684,0x6f0f,0x7f51,0x4e4b,0x9c7c))
if ($html -notmatch $siteName) { throw "Missing final site name" }
if ($html -notmatch 'id="app"') { throw "Missing app mount" }
if ($html -notmatch 'site-core.js') { throw "Missing site core script" }
if ($html -notmatch 'motion-core.js') { throw "Missing motion core script" }
if ($html.IndexOf('motion-core.js') -gt $html.IndexOf('app.js')) { throw "Motion core must load before app.js" }
if ($html -notmatch 'assets/fonts/lxgw-wenkai-screen.css') { throw "Missing local font stylesheet" }
if ($html -match 'site-motto') { throw "The redundant centered motto must be removed" }
if ($sync -notmatch 'site-core.js' -or $sync -notmatch 'motion-core.js' -or $sync -notmatch 'assets') { throw "Public sync must include core, motion, and assets" }
@("hero-four-seasons.webp", "feifei-transparent.png", "tiangou-transparent.png", "nine-tailed-fox-transparent.png") | ForEach-Object {
  if (-not (Test-Path (Join-Path "assets" $_))) { throw "Missing asset: $_" }
}
Write-Host "Site shell tests passed."
