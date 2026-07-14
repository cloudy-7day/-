$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "daily-update-support.ps1")

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Assert-Equal {
  param($Actual, $Expected, [string]$Message)
  if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', got '$Actual'." }
}

$paperText = @"
Abstract. We introduce a neural decoder that corrects continuous cursor motion.
Method. The system learns residual kinematic corrections with reinforcement learning.
Results. It improves target acquisition in offline and closed-loop experiments.
Conclusion. The approach may support assistive brain-computer interfaces.
"@

$excerpt = Get-SourceExcerpt -Text $paperText -MaxSentences 3 -MaxCharacters 260
Assert-True ($excerpt -match "neural decoder") "The excerpt must contain source-specific content."
Assert-True ($excerpt.Length -le 260) "The excerpt must respect MaxCharacters."

$analysis = New-SourceExtractAnalysis -Category paper -Title "Residual decoding" -SourceText $paperText
Assert-Equal $analysis.summarySource "source_extract" "Fallback provenance must be explicit."
Assert-True ($analysis.summary -match "公开原文自动摘录") "Chinese fallback must disclose source extraction."
Assert-True ($analysis.translations.en.summary -match "neural decoder") "English fallback must preserve the source excerpt."
Assert-True (-not (Test-ForbiddenFallbackText -Text $analysis.summary)) "A real source extract must not match forbidden placeholders."
Assert-True (Test-ForbiddenFallbackText -Text "Local fallback: article collected automatically") "Legacy local fallback must be forbidden."
Assert-True (Test-ForbiddenFallbackText -Text "智能总结需要 DeepSeek key 和完整内容输入后生成。") "Legacy paper placeholder must be forbidden."

$a = @(
  [pscustomobject]@{ url = "HTTPS://EXAMPLE.COM/a/" },
  [pscustomobject]@{ url = "https://example.com/b?x=1" }
)
$b = @(
  [pscustomobject]@{ url = "https://example.com/a" },
  [pscustomobject]@{ url = "https://example.com/b?x=1" }
)
$c = @(
  [pscustomobject]@{ url = "https://example.com/a" },
  [pscustomobject]@{ url = "https://example.com/c" }
)
Assert-Equal (Get-ContentFingerprint $a) (Get-ContentFingerprint $b) "URL normalization must make equivalent batches stable."
Assert-True ((Get-ContentFingerprint $a) -ne (Get-ContentFingerprint $c)) "A changed URL batch must change the fingerprint."

Write-Host "Daily update support tests passed."


