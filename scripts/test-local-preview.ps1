$ErrorActionPreference = "Stop"
$utf8 = [System.Text.Encoding]::UTF8
$siteName = -join ([char[]](0x5c71,0x6d77,0x7ecf,0x7684,0x6f0f,0x7f51,0x4e4b,0x9c7c))
$rootHtml = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\index.html"), $utf8)
$publicHtml = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\public\index.html"), $utf8)
$publicCss = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "..\public\styles.css"), $utf8)
if ($rootHtml -notmatch $siteName -or $publicHtml -notmatch $siteName) {
  throw "Final name must be synced"
}
if (-not (Test-Path (Join-Path $PSScriptRoot "..\public\assets\hero-four-seasons.webp"))) {
  throw "Hero asset must be synced"
}
if ($publicCss -notmatch "prefers-reduced-motion") {
  throw "Reduced-motion CSS must be published"
}
if (-not (Test-Path (Join-Path $PSScriptRoot "..\public\site-core.js"))) {
  throw "Site core must be published"
}
Write-Host "Local preview tests passed."
