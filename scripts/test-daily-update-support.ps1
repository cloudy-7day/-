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
$highlight = Get-SourceHighlight -Text $paperText
Assert-Equal $highlight "Abstract. We introduce a neural decoder that corrects continuous cursor motion." "The highlight must be one complete traceable source sentence."

$analysis = New-SourceExtractAnalysis -Category paper -Title "Residual decoding" -SourceText $paperText
Assert-Equal $analysis.summarySource "source_extract" "Fallback provenance must be explicit."
Assert-Equal $analysis.summary $analysis.sourceExcerpt "The summary field must contain only the source extract."
Assert-Equal $analysis.highlight $highlight "Fallback highlights must use the traceable source sentence."
Assert-Equal $analysis.translations.en.highlight $highlight "English fallback highlights must preserve the source sentence."
Assert-True ($analysis.summary -notmatch "公开原文自动摘录") "The frontend label must own the fallback disclosure."
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

function New-Payload {
  param([string]$Date, [string]$Status, [string]$UrlBase)

  $articles = @(0..6 | ForEach-Object {
    [pscustomobject]@{
      url = "$UrlBase-$_"
      category = if ($_ -lt 3) { "international" } else { "ai" }
    }
  })
  return [pscustomobject]@{
    issueDate = $Date
    updateStatus = $Status
    contentFingerprint = Get-ContentFingerprint $articles
    articles = $articles
  }
}

$today = "2026-07-14"
$current = New-Payload -Date $today -Status complete -UrlBase "https://example.com/today"
$previous = New-Payload -Date "2026-07-13" -Status complete -UrlBase "https://example.com/yesterday"
$degraded = New-Payload -Date $today -Status degraded -UrlBase "https://example.com/today"
$stale = New-Payload -Date $today -Status complete -UrlBase "https://example.com/yesterday"

Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T07:30:00") -CurrentPayload $null -TodayArchive $null -PreviousArchive $previous) "before_window" "Runs before 08:00 must skip."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T07:30:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $previous -ForceRefresh $true) "fresh_generation" "Explicit force must override the time window."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T08:07:00") -CurrentPayload $null -TodayArchive $null -PreviousArchive $previous) "fresh_generation" "Missing today data must generate."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $degraded -TodayArchive $degraded -PreviousArchive $previous) "summary_upgrade" "Degraded data must upgrade summaries."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $previous -TodayArchive $current -PreviousArchive $previous) "repair_publish" "A valid archive with stale current data must republish."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $stale -TodayArchive $stale -PreviousArchive $previous) "fresh_generation" "An unchanged whole-day URL fingerprint must regenerate."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $previous) "already_complete" "Valid complete data must skip."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $previous -ForceRefresh $true) "fresh_generation" "Explicit force must regenerate."
$invalidShape = $current | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$invalidShape.articles = @($invalidShape.articles | Select-Object -First 6)
$invalidShape.contentFingerprint = Get-ContentFingerprint $invalidShape.articles
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $invalidShape -TodayArchive $invalidShape -PreviousArchive $previous) "fresh_generation" "An invalid seven-item shape must regenerate."

$upgradePayload = [pscustomobject]@{
  issueDate = $today
  updateStatus = "degraded"
  contentFingerprint = Get-ContentFingerprint @([pscustomobject]@{ url = "https://example.com/paper" })
  articles = @([pscustomobject]@{
    id = "paper-1"
    category = "paper"
    title = "Paper"
    url = "https://example.com/paper"
    summarySource = "source_extract"
    highlight = "source highlight"
    summary = "extract"
    failureAnalysis = "pending"
    sourceExcerpt = "source"
    translations = [pscustomobject]@{ en = [pscustomobject]@{} }
  })
}
$beforeFingerprint = $upgradePayload.contentFingerprint
$upgraded = Update-DegradedPayload -Payload $upgradePayload -AnalyzeItem {
  param($item)
  [pscustomobject]@{
    summarySource = "deepseek"
    sourceExcerpt = $item.sourceExcerpt
    highlight = "upgraded highlight"
    summary = "analysis"
    failureAnalysis = "judgement"
    translations = [pscustomobject]@{
      en = [pscustomobject]@{ title = "Paper"; highlight = "Upgraded source highlight."; summary = "Analysis"; failureAnalysis = "Judgement" }
    }
  }
}
Assert-Equal $upgraded.updateStatus "complete" "A successful upgrade must become complete."
Assert-Equal $upgraded.contentFingerprint $beforeFingerprint "Summary upgrades must preserve the URL fingerprint."
Assert-Equal $upgraded.articles[0].id "paper-1" "Summary upgrades must preserve article identity."
Assert-Equal $upgraded.articles[0].highlight "upgraded highlight" "Summary upgrades must replace the list highlight."
Assert-Equal $upgraded.articles[0].translations.en.highlight "Upgraded source highlight." "Summary upgrades must replace the English highlight."

Write-Host "Daily update support tests passed."
