$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$archiveName = -join ([char[]](0x4e2a,0x4eba,0x4fe1,0x606f,0x6536,0x96c6,0x5e93))
$archiveRoot = Join-Path $root $archiveName
$paths = @(
  (Join-Path $root "public/index.html"),
  (Join-Path (Join-Path $archiveRoot "public") "index.html"),
  (Join-Path (Join-Path $archiveRoot "website") "index.html")
)
$utf8 = [System.Text.Encoding]::UTF8
$styles = [System.IO.File]::ReadAllText((Join-Path $root "public/styles.css"), $utf8)

foreach ($path in $paths) {
  $html = [System.IO.File]::ReadAllText($path, $utf8)
  if ($html -notmatch "language-toggle" -or $html -notmatch "data-language=`"en`"") {
    throw "Preview index should include the language toggle: $path"
  }
}

if ($styles -notmatch "position:\s*sticky") {
  throw "Language/archive controls should stay visible while reading."
}

Write-Host "Local preview tests passed."
