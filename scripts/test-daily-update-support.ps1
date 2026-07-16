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
Assert-True (Test-ChineseDisplayTitle -Title "Chipotle 首进墨西哥，当地人先泼冷水") "Chinese titles may preserve a proper noun when the display title is predominantly Chinese."
Assert-True (-not (Test-ChineseDisplayTitle -Title "English title only 中文")) "A token amount of Chinese must not make an English title valid in Chinese mode."

$canonical = Get-CanonicalArticleUrl -Url "HTTPS://EXAMPLE.COM/a/?utm_source=newsletter&b=2&a=1#section"
Assert-Equal $canonical "https://example.com/a?a=1&b=2" "Canonical URLs must strip tracking data, fragments, and normalize query order."
Assert-Equal (Get-NormalizedArticleTitle -Title " Codex: Usage UP! ") "codexusageup" "Title identity must ignore punctuation and case."
$ledger = [pscustomobject]@{
  urls = @("https://example.com/a?a=1&b=2")
  titles = @("alreadyused")
}
Assert-True (Test-ArticleSeen -Article ([pscustomobject]@{ url = "https://example.com/a/?b=2&utm_medium=email&a=1"; title = "Fresh wording" }) -Ledger $ledger) "A canonical ledger URL must reject a candidate."
Assert-True (Test-ArticleSeen -Article ([pscustomobject]@{ url = "https://example.com/new"; title = "Already Used" }) -Ledger $ledger) "A normalized ledger title must reject a candidate."
Assert-True (-not (Test-ArticleSeen -Article ([pscustomobject]@{ url = "https://example.com/fresh"; title = "Fresh title" }) -Ledger $ledger)) "A new identity must remain eligible."

$published = [pscustomobject]@{ url = "https://example.com/published/?utm_source=rss"; title = "Already in the archive" }
$candidateLedger = Add-ArticlesToLedger -Ledger $ledger -Articles @($published)
Assert-True (Test-ArticleSeen -Article ([pscustomobject]@{ url = "https://example.com/published"; title = "Different title" }) -Ledger $candidateLedger) "Published archive URLs must join the generation ledger."
Assert-True (Test-ArticleSeen -Article ([pscustomobject]@{ url = "https://example.com/other"; title = "Already in the archive" }) -Ledger $candidateLedger) "Published archive titles must join the generation ledger."
Assert-Equal @($candidateLedger.urls).Count 2 "The merged generation ledger must retain tombstones and published URLs."

$natoA = [pscustomobject]@{ url = "https://source-a.example/nato"; title = "What happened on the opening day of the NATO summit in Ankara" }
$natoB = [pscustomobject]@{ url = "https://source-b.example/stakes"; title = "What's at stake at the NATO summit in Ankara" }
$sameTopicRejected = $false
try {
  Assert-ArticleSetUnique -Articles @($natoA, $natoB) -Ledger ([pscustomobject]@{ urls = @(); titles = @() })
} catch {
  $sameTopicRejected = $true
}
Assert-True $sameTopicRejected "Different URLs covering the same event must be rejected."

$distinctArticles = @(
  [pscustomobject]@{ url = "https://example.com/battery"; title = "Solid-state battery reaches a new cycle-life milestone" },
  [pscustomobject]@{ url = "https://example.com/robot"; title = "Warehouse robot learns safer grasp planning" }
)
Assert-ArticleSetUnique -Articles $distinctArticles -Ledger ([pscustomobject]@{ urls = @(); titles = @() })
$selected = @(Select-UniqueArticleCandidates -Articles @($natoA, $natoB, $distinctArticles[0]) -Ledger ([pscustomobject]@{ urls = @(); titles = @() }))
Assert-Equal $selected.Count 2 "Candidate selection must skip a same-topic duplicate and refill with a distinct item."
Assert-Equal $selected[1].title $distinctArticles[0].title "Candidate selection must retain the next distinct item."

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

  $categories = @("domestic", "domestic", "domestic", "international", "international", "ai", "ai", "paper", "paper")
  $articles = @(0..8 | ForEach-Object {
    [pscustomobject]@{
      url = "$UrlBase-$_"
      category = $categories[$_]
    }
  })
  return [pscustomobject]@{
    issueDate = $Date
    updateStatus = $Status
    contentFingerprint = Get-ContentFingerprint $articles
    articles = $articles
  }
}

function New-LegacyPayload {
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
$previous = New-LegacyPayload -Date "2026-07-13" -Status complete -UrlBase "https://example.com/yesterday"
$degraded = New-Payload -Date $today -Status degraded -UrlBase "https://example.com/today"
$legacyBaseCurrent = New-Payload -Date $today -Status complete -UrlBase "https://example.com/yesterday"

Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T07:30:00") -CurrentPayload $null -TodayArchive $null -PreviousArchive $previous) "before_window" "Runs before 08:00 must skip."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T07:30:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $previous -ForceRefresh $true) "fresh_generation" "Explicit force must override the time window."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T08:07:00") -CurrentPayload $null -TodayArchive $null -PreviousArchive $previous) "fresh_generation" "Missing today data must generate."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $degraded -TodayArchive $degraded -PreviousArchive $previous) "summary_upgrade" "Degraded data must upgrade summaries."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $previous -TodayArchive $current -PreviousArchive $previous) "repair_publish" "A valid archive with stale current data must republish."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $legacyBaseCurrent -TodayArchive $legacyBaseCurrent -PreviousArchive $previous) "already_complete" "A legacy seven-item previous archive must not make a valid nine-item current payload stale when fingerprints differ."
$equalFingerprintPrevious = New-LegacyPayload -Date "2026-07-13" -Status complete -UrlBase "https://example.com/equal-probe"
$equalFingerprintPrevious.contentFingerprint = $current.contentFingerprint
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $equalFingerprintPrevious) "fresh_generation" "Actually equal previous and current fingerprints must regenerate."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $previous) "already_complete" "Valid complete data must skip."
$todayLedger = [pscustomobject]@{ urls = @("https://example.com/today-0"); titles = @() }
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $previous -Ledger $todayLedger) "fresh_generation" "A current issue colliding with the historical ledger must regenerate."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $previous -ForceRefresh $true) "fresh_generation" "Explicit force must regenerate."
$missingDomestic = $current | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$missingDomestic.articles = @($missingDomestic.articles | Select-Object -Skip 1)
$missingDomestic.contentFingerprint = Get-ContentFingerprint $missingDomestic.articles
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $missingDomestic -TodayArchive $missingDomestic -PreviousArchive $previous) "fresh_generation" "Removing one domestic item must regenerate."

$wrongNewsSplit = $current | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$wrongNewsSplit.articles[0].category = "international"
$wrongNewsSplit.contentFingerprint = Get-ContentFingerprint $wrongNewsSplit.articles
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $wrongNewsSplit -TodayArchive $wrongNewsSplit -PreviousArchive $previous) "fresh_generation" "Changing a domestic item to international must regenerate."

$wrongReadingCount = $current | ConvertTo-Json -Depth 20 | ConvertFrom-Json
$wrongReadingCount.articles[5].category = "international"
$wrongReadingCount.contentFingerprint = Get-ContentFingerprint $wrongReadingCount.articles
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $wrongReadingCount -TodayArchive $wrongReadingCount -PreviousArchive $previous) "fresh_generation" "Changing the reading count must regenerate."

$legacyCurrent = New-LegacyPayload -Date $today -Status complete -UrlBase "https://example.com/legacy-current"
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $legacyCurrent -TodayArchive $legacyCurrent -PreviousArchive $previous) "fresh_generation" "A seven-item payload must never be accepted as current complete data."

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
