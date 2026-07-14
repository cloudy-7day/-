# Paper Summary and Daily Update Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make daily publication truthfully distinguish DeepSeek summaries from source extracts, publish near 08:07 Los Angeles time, and repair or regenerate stale content near 09:07.

**Architecture:** Add a pure PowerShell support module for source extraction, fingerprints, and update decisions; keep network collection and DeepSeek calls in `update-daily.ps1`. The workflow invokes the script at DST-safe UTC times, while the script owns Los Angeles time gating, content-state inspection, idempotency, summary-only upgrades, validation, and atomic publication. The frontend renders a bilingual disclosure for source extracts.

**Tech Stack:** PowerShell 7, GitHub Actions, SHA-256 from .NET, static JSON, vanilla JavaScript, Node.js contract tests.

## Global Constraints

- Continue to use DeepSeek only; do not call GPT or another model provider.
- Preserve the existing daily mix: exactly 3 international items and 4 AI/paper items, with 0-2 eligible papers and AI filling paper shortfall.
- Papers must retain the open-full-text and usable-PDF-text gates.
- Do not bypass paywalls, login, CAPTCHA, robots restrictions, or anti-crawling controls.
- Do not edit or commit the user's existing `scripts/start-web-server.ps1` or `scripts/edit_template.py` changes.
- Use `summarySource` values `deepseek` and `source_extract`; use root `updateStatus` values `complete` and `degraded`.
- Target 08:07 and 09:07 in `America/Los_Angeles`; never generate before local 08:00.
- Never publish `Local fallback` or `智能总结需要 DeepSeek key` placeholder text.
- Follow RED-GREEN-REFACTOR for every production change.

---

## File Structure

- Create `scripts/daily-update-support.ps1`: pure helpers for bounded source excerpts, SHA-256 fingerprints, payload comparison, and update-action selection.
- Create `scripts/test-daily-update-support.ps1`: executable behavior tests for the pure support module.
- Modify `scripts/update-daily.ps1`: analysis provenance, upgrade path, validation, state decision, and safe publication.
- Modify `scripts/test-update-daily-rules.ps1`: integration/static contract tests for workflow, validation, and publication behavior.
- Modify `.github/workflows/daily-update.yml`: DST-safe 08:07/09:07 schedules, force input, and script-owned gating.
- Modify `site-core.js`: bilingual summary-source label helper.
- Modify `app.js`: render the disclosure on index and detail summaries.
- Modify `styles.css`: style the disclosure without changing the established layout.
- Modify `scripts/test-site-core.js` and `scripts/test-app-contract.ps1`: frontend regression coverage.
- Modify `README.md`, `PROJECT_CONTEXT.md`, and `CHANGELOG.md`: document recovery semantics and operational checks.

---

### Task 1: Source excerpts and stable content fingerprints

**Files:**
- Create: `scripts/daily-update-support.ps1`
- Create: `scripts/test-daily-update-support.ps1`

**Interfaces:**
- Produces: `Get-SourceExcerpt([string]$Text, [int]$MaxSentences = 3, [int]$MaxCharacters = 1800) -> string`
- Produces: `New-SourceExtractAnalysis([string]$Category, [string]$Title, [string]$SourceText, [bool]$RequiresRiskAnalysis = $false) -> ordered dictionary`
- Produces: `Get-ContentFingerprint([object[]]$Articles) -> lowercase SHA-256 hex string`
- Produces: `Test-ForbiddenFallbackText([string]$Text) -> bool`

- [ ] **Step 1: Write failing support-module tests**

Create `scripts/test-daily-update-support.ps1` with assertions that demand real excerpts, bounded output, provenance, stable fingerprints, and forbidden-placeholder detection:

```powershell
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "daily-update-support.ps1")

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}
function Assert-Equal($Actual, $Expected, [string]$Message) {
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
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
pwsh -NoProfile -File scripts/test-daily-update-support.ps1
```

Expected: FAIL because `scripts/daily-update-support.ps1` or `Get-SourceExcerpt` does not exist.

- [ ] **Step 3: Implement the pure support module**

Create `scripts/daily-update-support.ps1` with these minimal implementations:

```powershell
function Get-SourceExcerpt {
  param([string]$Text, [int]$MaxSentences = 3, [int]$MaxCharacters = 1800)
  $clean = (($Text -replace '\s+', ' ').Trim())
  if (-not $clean) { return "" }
  $sentences = @([regex]::Split($clean, '(?<=[.!?。！？])\s+') | Where-Object { $_.Trim().Length -ge 24 })
  $excerpt = (@($sentences | Select-Object -First $MaxSentences) -join ' ').Trim()
  if (-not $excerpt) { $excerpt = $clean }
  return $excerpt.Substring(0, [Math]::Min($MaxCharacters, $excerpt.Length)).Trim()
}

function Test-ForbiddenFallbackText {
  param([string]$Text)
  return [bool]($Text -match 'Local fallback|智能总结需要\s+DeepSeek\s+key|candidate collected automatically')
}

function New-SourceExtractAnalysis {
  param([string]$Category, [string]$Title, [string]$SourceText, [bool]$RequiresRiskAnalysis = $false)
  $excerpt = Get-SourceExcerpt -Text $SourceText
  if (-not $excerpt) { throw "Cannot build a source extract from empty content: $Title" }
  [ordered]@{
    summarySource = 'source_extract'
    sourceExcerpt = $excerpt
    summary = "DeepSeek 暂不可用，当前为公开原文自动摘录：$excerpt"
    failureAnalysis = "当前条目仅提供可追溯原文摘录；待 DeepSeek 恢复后自动补充分析。"
    translations = [ordered]@{
      en = [ordered]@{
        title = $Title
        summary = $excerpt
        failureAnalysis = 'This is a traceable source extract pending DeepSeek analysis.'
      }
    }
  }
}

function Get-ContentFingerprint {
  param([object[]]$Articles)
  $urls = @($Articles | ForEach-Object {
    $uri = [uri]([string]$_.url)
    $builder = [System.UriBuilder]::new($uri)
    $builder.Host = $builder.Host.ToLowerInvariant()
    $builder.Scheme = $builder.Scheme.ToLowerInvariant()
    $builder.Path = $builder.Path.TrimEnd('/')
    $builder.Uri.AbsoluteUri
  })
  $bytes = [Text.Encoding]::UTF8.GetBytes(($urls -join "`n"))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
  return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}
```

- [ ] **Step 4: Run the support test and verify GREEN**

Run: `pwsh -NoProfile -File scripts/test-daily-update-support.ps1`

Expected: `Daily update support tests passed.`

- [ ] **Step 5: Commit Task 1**

```powershell
git add scripts/daily-update-support.ps1 scripts/test-daily-update-support.ps1
git commit -m "test: define daily update recovery primitives"
```

---

### Task 2: Analysis provenance and publish-time validation

**Files:**
- Modify: `scripts/update-daily.ps1:1-8,83-158,202-234,398-560,599-675,739-840,1146-1157`
- Modify: `scripts/test-update-daily-rules.ps1`

**Interfaces:**
- Consumes: Task 1 `New-SourceExtractAnalysis`, `Get-ContentFingerprint`, and `Test-ForbiddenFallbackText`.
- Changes: `New-ArticleAnalysis(...)` always returns `summarySource` and `sourceExcerpt`.
- Changes: every published item has `summarySource`; root payload has `updateStatus` and `contentFingerprint`.

- [ ] **Step 1: Add failing validation and provenance tests**

Extend `scripts/test-update-daily-rules.ps1` after `New-TestArticle` so test articles default to DeepSeek provenance:

```powershell
$article.summarySource = "deepseek"
$article.sourceExcerpt = "Source-specific material for $Id."
```

Add root metadata to the valid payload:

```powershell
$validPayload = [ordered]@{
  issueDate = $laDate
  updateStatus = "complete"
  contentFingerprint = Get-ContentFingerprint -Articles $validArticles
  articles = $validArticles
}
Assert-DailyPayload -Payload $validPayload
```

Add negative assertions:

```powershell
$placeholderPayload = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$placeholderPayload.articles[5].summary = "智能总结需要 DeepSeek key 和完整内容输入后生成。"
$rejected = $false
try { Assert-DailyPayload -Payload $placeholderPayload } catch { $rejected = $true }
if (-not $rejected) { throw "Published payloads must reject legacy fallback text." }

$wrongFingerprint = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$wrongFingerprint.contentFingerprint = "deadbeef"
$rejected = $false
try { Assert-DailyPayload -Payload $wrongFingerprint } catch { $rejected = $true }
if (-not $rejected) { throw "Published payloads must reject an incorrect fingerprint." }
```

- [ ] **Step 2: Run the rules test and verify RED**

Run: `pwsh -NoProfile -File scripts/test-update-daily-rules.ps1`

Expected: FAIL because `Assert-DailyPayload` does not require provenance or verify the fingerprint.

- [ ] **Step 3: Dot-source support and replace generic fallback**

At the top of `scripts/update-daily.ps1`, add:

```powershell
. (Join-Path $PSScriptRoot "daily-update-support.ps1")
```

Remove `New-LocalAnalysis`. In both the missing-key branch and the catch branch of `New-ArticleAnalysis`, return:

```powershell
return New-SourceExtractAnalysis `
  -Category $Category `
  -Title $Title `
  -SourceText $SourceText `
  -RequiresRiskAnalysis $RequiresRiskAnalysis
```

Before returning a successful DeepSeek result, add:

```powershell
$result.summarySource = "deepseek"
$result.sourceExcerpt = Get-SourceExcerpt -Text $SourceText
```

Every item constructor (`New-PaperItem`, news item construction, and `Add-AiArticleAnalysis`) must copy:

```powershell
summarySource = [string]$analysis.summarySource
sourceExcerpt = [string]$analysis.sourceExcerpt
```

- [ ] **Step 4: Add root state and strengthen `Assert-DailyPayload`**

After the existing item checks, enforce:

```powershell
if ($Payload.updateStatus -notin @("complete", "degraded")) {
  throw "Daily payload updateStatus must be complete or degraded."
}
$expectedFingerprint = Get-ContentFingerprint -Articles $items
if ($Payload.contentFingerprint -ne $expectedFingerprint) {
  throw "Daily payload fingerprint does not match its article URLs."
}
foreach ($item in $items) {
  if ($item.summarySource -notin @("deepseek", "source_extract")) {
    throw "Every article must declare summarySource: $($item.id)"
  }
  if (Test-ForbiddenFallbackText -Text "$($item.summary) $($item.failureAnalysis)") {
    throw "Forbidden fallback text cannot be published: $($item.id)"
  }
  if ($item.summarySource -eq "source_extract" -and -not $item.sourceExcerpt) {
    throw "Source extracts must include sourceExcerpt: $($item.id)"
  }
}
$hasExtract = @($items | Where-Object summarySource -eq "source_extract").Count -gt 0
if (($hasExtract -and $Payload.updateStatus -ne "degraded") -or (-not $hasExtract -and $Payload.updateStatus -ne "complete")) {
  throw "updateStatus must agree with article summarySource values."
}
```

Build payload metadata only after `$articles` is final:

```powershell
$updateStatus = if (@($articles | Where-Object summarySource -eq "source_extract").Count) { "degraded" } else { "complete" }
$payload = [ordered]@{
  issueDate = Get-LosAngelesDate
  updateStatus = $updateStatus
  contentFingerprint = Get-ContentFingerprint -Articles $articles
  notes = @( ...existing notes... )
  articles = $articles
}
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```powershell
pwsh -NoProfile -File scripts/test-daily-update-support.ps1
pwsh -NoProfile -File scripts/test-update-daily-rules.ps1
pwsh -NoProfile -File scripts/test-paper-selection.ps1
pwsh -NoProfile -File scripts/test-ai-selection.ps1
pwsh -NoProfile -File scripts/test-translation.ps1
```

Expected: all five scripts print their `passed` messages.

- [ ] **Step 6: Commit Task 2**

```powershell
git add scripts/update-daily.ps1 scripts/test-update-daily-rules.ps1
git commit -m "fix: publish traceable summary fallbacks"
```

---

### Task 3: Content-state decisions and summary-only upgrades

**Files:**
- Modify: `scripts/daily-update-support.ps1`
- Modify: `scripts/test-daily-update-support.ps1`

**Interfaces:**
- Produces: `Get-DailyUpdateAction([datetime]$LocalNow, $CurrentPayload, $TodayArchive, $PreviousArchive, [bool]$ForceRefresh = $false) -> string`
- Produces: action values `before_window`, `fresh_generation`, `repair_publish`, `summary_upgrade`, `already_complete`.
- Produces: `Update-DegradedPayload($Payload, [scriptblock]$AnalyzeItem) -> payload` with unchanged article IDs, URLs, and fingerprint.

- [ ] **Step 1: Add failing action-decision tests**

Append to `scripts/test-daily-update-support.ps1`:

```powershell
function New-Payload([string]$Date, [string]$Status, [string[]]$Urls) {
  $base = $Urls[0]
  $articles = @(0..6 | ForEach-Object {
    [pscustomobject]@{ url = "$base-$_"; category = if ($_ -lt 3) { "international" } else { "ai" } }
  })
  [pscustomobject]@{
    issueDate = $Date
    updateStatus = $Status
    contentFingerprint = Get-ContentFingerprint $articles
    articles = $articles
  }
}

$today = "2026-07-14"
$current = New-Payload $today complete @("https://example.com/today-a")
$previous = New-Payload "2026-07-13" complete @("https://example.com/yesterday-a")
$degraded = New-Payload $today degraded @("https://example.com/today-a")
$stale = New-Payload $today complete @("https://example.com/yesterday-a")

Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T07:30:00") -CurrentPayload $null -TodayArchive $null -PreviousArchive $previous) "before_window" "Runs before 08:00 must skip."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T08:07:00") -CurrentPayload $null -TodayArchive $null -PreviousArchive $previous) "fresh_generation" "Missing today data must generate."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $degraded -TodayArchive $degraded -PreviousArchive $previous) "summary_upgrade" "Degraded data must upgrade summaries."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $previous -TodayArchive $current -PreviousArchive $previous) "repair_publish" "A valid archive with stale current data must republish."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $stale -TodayArchive $stale -PreviousArchive $previous) "fresh_generation" "An unchanged whole-day URL fingerprint must regenerate."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $previous) "already_complete" "Valid complete data must skip."
Assert-Equal (Get-DailyUpdateAction -LocalNow ([datetime]"2026-07-14T09:07:00") -CurrentPayload $current -TodayArchive $current -PreviousArchive $previous -ForceRefresh $true) "fresh_generation" "Explicit force must regenerate."

$upgradePayload = [pscustomobject]@{
  issueDate = $today
  updateStatus = "degraded"
  contentFingerprint = Get-ContentFingerprint @([pscustomobject]@{ url = "https://example.com/paper" })
  articles = @([pscustomobject]@{
    id = "paper-1"; category = "paper"; title = "Paper"; url = "https://example.com/paper"
    summarySource = "source_extract"; summary = "extract"; failureAnalysis = "pending"
    sourceExcerpt = "source"; translations = [pscustomobject]@{ en = [pscustomobject]@{} }
  })
}
$beforeFingerprint = $upgradePayload.contentFingerprint
$upgraded = Update-DegradedPayload -Payload $upgradePayload -AnalyzeItem {
  param($item)
  [pscustomobject]@{
    summarySource = "deepseek"; sourceExcerpt = $item.sourceExcerpt; summary = "正式总结"; failureAnalysis = "正式判断"
    translations = [pscustomobject]@{ en = [pscustomobject]@{ title = "Paper"; summary = "Analysis"; failureAnalysis = "Judgement" } }
  }
}
Assert-Equal $upgraded.updateStatus "complete" "A successful upgrade must become complete."
Assert-Equal $upgraded.contentFingerprint $beforeFingerprint "Summary upgrades must preserve the URL fingerprint."
Assert-Equal $upgraded.articles[0].id "paper-1" "Summary upgrades must preserve article identity."
```

- [ ] **Step 2: Run the support test and verify RED**

Run: `pwsh -NoProfile -File scripts/test-daily-update-support.ps1`

Expected: FAIL because `Get-DailyUpdateAction` is undefined.

- [ ] **Step 3: Implement pure state decision**

Add to `scripts/daily-update-support.ps1`:

```powershell
function Get-DailyUpdateAction {
  param([datetime]$LocalNow, $CurrentPayload, $TodayArchive, $PreviousArchive, [bool]$ForceRefresh = $false)
  if ($LocalNow.Hour -lt 8) { return "before_window" }
  if ($ForceRefresh) { return "fresh_generation" }
  $today = $LocalNow.ToString("yyyy-MM-dd")
  if (-not $TodayArchive -or $TodayArchive.issueDate -ne $today) { return "fresh_generation" }
  $items = @($TodayArchive.articles)
  $newsCount = @($items | Where-Object category -eq "international").Count
  $readingCount = @($items | Where-Object { $_.category -in @("ai", "paper") }).Count
  if ($items.Count -ne 7 -or $newsCount -ne 3 -or $readingCount -ne 4) { return "fresh_generation" }
  if (-not $TodayArchive.contentFingerprint -or $TodayArchive.contentFingerprint -ne (Get-ContentFingerprint $TodayArchive.articles)) { return "fresh_generation" }
  if ($PreviousArchive -and $TodayArchive.contentFingerprint -eq $PreviousArchive.contentFingerprint) { return "fresh_generation" }
  if (-not $CurrentPayload -or (($CurrentPayload | ConvertTo-Json -Compress -Depth 20) -ne ($TodayArchive | ConvertTo-Json -Compress -Depth 20))) { return "repair_publish" }
  if ($TodayArchive.updateStatus -eq "degraded") { return "summary_upgrade" }
  if ($TodayArchive.updateStatus -eq "complete") { return "already_complete" }
  return "fresh_generation"
}

function Update-DegradedPayload {
  param($Payload, [scriptblock]$AnalyzeItem)
  $before = [string]$Payload.contentFingerprint
  foreach ($item in @($Payload.articles | Where-Object summarySource -eq "source_extract")) {
    $analysis = & $AnalyzeItem $item
    $item.summary = $analysis.summary
    $item.failureAnalysis = $analysis.failureAnalysis
    $item.summarySource = $analysis.summarySource
    $item.sourceExcerpt = $analysis.sourceExcerpt
    if ($analysis.translations.en) { $item.translations.en = $analysis.translations.en }
    if ($item.category -eq "paper" -and $analysis.paperCard) {
      $item.paperCard = $analysis.paperCard
      $item.translations.en.paperCard = $analysis.translations.en.paperCard
    }
  }
  $Payload.contentFingerprint = Get-ContentFingerprint $Payload.articles
  if ($Payload.contentFingerprint -ne $before) { throw "Summary upgrade changed article selection." }
  $Payload.updateStatus = if (@($Payload.articles | Where-Object summarySource -eq "source_extract").Count) { "degraded" } else { "complete" }
  return $Payload
}
```

- [ ] **Step 4: Run the support test and verify GREEN**

Run: `pwsh -NoProfile -File scripts/test-daily-update-support.ps1`

Expected: `Daily update support tests passed.`

- [ ] **Step 5: Commit Task 3**

```powershell
git add scripts/daily-update-support.ps1 scripts/test-daily-update-support.ps1
git commit -m "fix: repair stale daily content after nine"
```

---

### Task 4: Integrate recovery, safe publishing, and DST-aware scheduling

**Files:**
- Modify: `scripts/update-daily.ps1:1-4,36-45,1093-1192`
- Modify: `.github/workflows/daily-update.yml`
- Modify: `scripts/test-update-daily-rules.ps1`

**Interfaces:**
- Consumes: Task 3 `Get-DailyUpdateAction` and `Update-DegradedPayload`.
- Produces: `Publish-DailyPayload($Payload, [string]$OutputPath)` validates before writing and synchronizes root/archive/public data.
- Workflow passes `ForceRefresh` only for an explicit `workflow_dispatch` checkbox.

- [ ] **Step 1: Add failing workflow and safe-publish contracts**

Extend `scripts/test-update-daily-rules.ps1`:

```powershell
if ($workflow -notmatch 'cron:\s*"7 15,16,17 \* \* \*"') {
  throw "Workflow must cover 08:07 and 09:07 in both PDT and PST."
}
if ($workflow -notmatch 'force:\s+description:') {
  throw "Manual runs must expose an explicit force input."
}
if ($workflow -match 'Archive for \$laDate already exists') {
  throw "Workflow must not treat file existence as update success."
}
if ($source -notmatch 'function Publish-DailyPayload') {
  throw "Publishing must be centralized behind validation."
}
if ($source -match '\$payload \| ConvertTo-Json -Depth 8 \| Set-Content -Path \$target') {
  throw "The main flow must not write the live target directly."
}
```

- [ ] **Step 2: Run rules test and verify RED**

Run: `pwsh -NoProfile -File scripts/test-update-daily-rules.ps1`

Expected: FAIL on the new cron/force/publisher contracts.

- [ ] **Step 3: Centralize validated publication**

Move target, archive, index, and `sync-public.ps1` writes into `Publish-DailyPayload`. Serialize once, write target/archive temporary sibling files, and keep sibling backups so a move failure restores both previous files:

```powershell
function Publish-DailyPayload {
  param($Payload, [string]$OutputPath = "data/articles.json")
  Assert-DailyPayload -Payload $Payload
  $target = Join-Path (Get-Location) $OutputPath
  $archiveFolder = Join-Path (Get-Location) "data/archive"
  New-Item -ItemType Directory -Force -Path (Split-Path $target),$archiveFolder | Out-Null
  $archiveFile = Join-Path $archiveFolder "$($Payload.issueDate).json"
  $json = $Payload | ConvertTo-Json -Depth 10
  $targetTemp = "$target.$([guid]::NewGuid().ToString('N')).tmp"
  $archiveTemp = "$archiveFile.$([guid]::NewGuid().ToString('N')).tmp"
  $targetBackup = "$target.before-publish.bak"
  $archiveBackup = "$archiveFile.before-publish.bak"
  $targetExisted = Test-Path $target
  $archiveExisted = Test-Path $archiveFile
  try {
    $json | Set-Content -LiteralPath $targetTemp -Encoding UTF8
    $json | Set-Content -LiteralPath $archiveTemp -Encoding UTF8
    if ($targetExisted) { Copy-Item -LiteralPath $target -Destination $targetBackup -Force }
    if ($archiveExisted) { Copy-Item -LiteralPath $archiveFile -Destination $archiveBackup -Force }
    Move-Item -LiteralPath $archiveTemp -Destination $archiveFile -Force
    Move-Item -LiteralPath $targetTemp -Destination $target -Force
  } catch {
    if ($archiveExisted) { Copy-Item -LiteralPath $archiveBackup -Destination $archiveFile -Force }
    elseif (Test-Path $archiveFile) { Remove-Item -LiteralPath $archiveFile -Force }
    if ($targetExisted) { Copy-Item -LiteralPath $targetBackup -Destination $target -Force }
    elseif (Test-Path $target) { Remove-Item -LiteralPath $target -Force }
    throw
  } finally {
    @($targetTemp,$archiveTemp,$targetBackup,$archiveBackup) | Where-Object { Test-Path $_ } | ForEach-Object { Remove-Item -LiteralPath $_ -Force }
  }
  Update-ArchiveIndex
  & (Join-Path (Get-Location) "scripts/sync-public.ps1")
}
```

Extract existing index-building code into `Update-ArchiveIndex`. The main flow ends with `Publish-DailyPayload -Payload $payload -OutputPath $OutputPath` and a status summary containing date, count, fingerprint, DeepSeek count, extract count, and action.

- [ ] **Step 4: Integrate time/state routing and summary-only analysis**

Change the parameter block and add `Get-LosAngelesNow`:

```powershell
param([string]$OutputPath = "data/articles.json", [bool]$ForceRefresh = $false)

function Get-LosAngelesNow {
  try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById("America/Los_Angeles") }
  catch [TimeZoneNotFoundException] { $tz = [TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time") }
  return [TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz)
}
function Get-LosAngelesDate { return (Get-LosAngelesNow).ToString("yyyy-MM-dd") }
```

Before candidate collection, safely load `data/articles.json`, today's archive, and the most recent earlier archive. Call `Get-DailyUpdateAction`, log `Daily update action: <action>`, then route:

```powershell
switch ($action) {
  "before_window" { Write-Host "Before local 08:00; no update attempted."; exit 0 }
  "already_complete" { Write-Host "Today's content is complete and changed; no update needed."; exit 0 }
  "repair_publish" { Publish-DailyPayload -Payload $todayArchive -OutputPath $OutputPath; exit 0 }
  "summary_upgrade" {
    $payload = Update-DegradedPayload -Payload $todayArchive -AnalyzeItem {
      param($item)
      $sourceText = if ($item.category -eq "paper") { Get-PdfTextFromUrl -Url ([string]$item.url) } else { [string]$item.sourceExcerpt }
      if (-not $sourceText) { return $item }
      New-ArticleAnalysis -Category $item.category -Title $item.title -Source $item.source -Url $item.url -SourceText $sourceText -ScoreLabel $item.scoreLabel -RequiresRiskAnalysis ($item.category -eq "ai")
    }
    Assert-DailyPayload -Payload $payload
    Publish-DailyPayload -Payload $payload -OutputPath $OutputPath
    exit 0
  }
  "fresh_generation" { }
}
```

The `summary_upgrade` callback may redownload only the already-selected paper PDF and may use only the stored source excerpt for news/AI. It never calls candidate selectors. End both upgrade and fresh-generation paths with the same status line containing date, article count, fingerprint, DeepSeek count, source-extract count, and action.

- [ ] **Step 5: Replace the workflow gate and schedules**

Use this trigger shape:

```yaml
on:
  workflow_dispatch:
    inputs:
      force:
        description: Force a full regeneration even when today is complete
        required: false
        default: false
        type: boolean
  push:
    branches: [main]
    paths:
      - ".github/workflows/daily-update.yml"
      - "scripts/update-daily.ps1"
      - "scripts/daily-update-support.ps1"
  schedule:
    # PDT: 08:07, 09:07, 10:07; PST: 07:07 (script skips), 08:07, 09:07.
    - cron: "7 15,16,17 * * *"
```

Remove the archive-existence gate. Always prepare the runtime, then invoke:

```powershell
$force = "${{ github.event_name }}" -eq "workflow_dispatch" -and "${{ inputs.force }}" -eq "true"
./scripts/update-daily.ps1 -ForceRefresh:$force
```

Keep concurrency, the 30-minute timeout, request retry, Python 3.12, pinned `pypdf==6.10.2`, `DEEPSEEK_API_KEY`, `GITHUB_TOKEN`, and commit logic.

- [ ] **Step 6: Run focused tests and parse checks**

Run:

```powershell
pwsh -NoProfile -File scripts/test-update-daily-rules.ps1
$tokens=$null; $errors=$null; [void][Management.Automation.Language.Parser]::ParseFile((Resolve-Path scripts/update-daily.ps1),[ref]$tokens,[ref]$errors); if($errors){throw $errors[0]}
```

Expected: rules pass and parser emits no error.

- [ ] **Step 7: Commit Task 4**

```powershell
git add .github/workflows/daily-update.yml scripts/update-daily.ps1 scripts/test-update-daily-rules.ps1
git commit -m "fix: add nine oclock content recovery"
```

---

### Task 5: Bilingual source-extract disclosure in the frontend

**Files:**
- Modify: `site-core.js`
- Modify: `app.js:13-48,127-139,173-213`
- Modify: `styles.css`
- Modify: `scripts/test-site-core.js`
- Modify: `scripts/test-app-contract.ps1`

**Interfaces:**
- Produces: `SiteCore.getSummarySourceLabel(article, language) -> string`.
- `app.js` renders `.summary-source-label` before any `source_extract` summary.

- [ ] **Step 1: Add failing frontend tests**

Append to `scripts/test-site-core.js`:

```javascript
assert.equal(core.getSummarySourceLabel({ summarySource: "deepseek" }, "zh"), "");
assert.equal(
  core.getSummarySourceLabel({ summarySource: "source_extract" }, "zh"),
  "DeepSeek 暂不可用，当前为公开原文自动摘录",
);
assert.equal(
  core.getSummarySourceLabel({ summarySource: "source_extract" }, "en"),
  "DeepSeek is temporarily unavailable; showing an automatic extract from the public source",
);
assert.equal(core.getSummarySourceLabel({}, "zh"), "");
```

Add to `scripts/test-app-contract.ps1`:

```powershell
if ($source -notmatch "summary-source-label") { throw "Source extracts must render a disclosure label." }
if ($source -notmatch "SiteCore.getSummarySourceLabel") { throw "Disclosure copy must use the tested SiteCore helper." }
```

- [ ] **Step 2: Run frontend tests and verify RED**

Run:

```powershell
node scripts/test-site-core.js
pwsh -NoProfile -File scripts/test-app-contract.ps1
```

Expected: Node fails because `getSummarySourceLabel` is undefined; the app contract also fails.

- [ ] **Step 3: Implement and export the label helper**

Add to `site-core.js` before the return block:

```javascript
function getSummarySourceLabel(article, language) {
  if (article?.summarySource !== "source_extract") return "";
  return language === "en"
    ? "DeepSeek is temporarily unavailable; showing an automatic extract from the public source"
    : "DeepSeek 暂不可用，当前为公开原文自动摘录";
}
```

Export `getSummarySourceLabel` in the returned object.

- [ ] **Step 4: Render the label in both summary surfaces**

In `renderIndexCard` and `renderArticle`, compute:

```javascript
const summarySourceLabel = SiteCore.getSummarySourceLabel(article, state.language);
const summarySourceMarkup = summarySourceLabel
  ? `<small class="summary-source-label">${escapeHtml(summarySourceLabel)}</small>`
  : "";
```

Place `summarySourceMarkup` immediately before the summary in the index card and detail page. Add restrained styling:

```css
.summary-source-label {
  display: block;
  margin-bottom: 0.45rem;
  color: var(--ink-muted);
  font-size: 0.75rem;
  letter-spacing: 0.04em;
}
```

- [ ] **Step 5: Run frontend tests and sync contract**

Run:

```powershell
node scripts/test-site-core.js
pwsh -NoProfile -File scripts/test-app-contract.ps1
pwsh -NoProfile -File scripts/test-frontend-language.js
pwsh -NoProfile -File scripts/sync-public.ps1
```

Expected: all tests pass; `public/app.js`, `public/site-core.js`, and `public/styles.css` match root copies.

- [ ] **Step 6: Commit Task 5**

```powershell
git add app.js site-core.js styles.css public/app.js public/site-core.js public/styles.css scripts/test-site-core.js scripts/test-app-contract.ps1
git commit -m "feat: label source extracted summaries"
```

---

### Task 6: Documentation and full verification

**Files:**
- Modify: `README.md`
- Modify: `PROJECT_CONTEXT.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Documents exact operational meanings of `complete`, `degraded`, 08:07, 09:07, force refresh, and content fingerprints.

- [ ] **Step 1: Update operational documentation**

Add a dated changelog entry that records the observed root cause: the 2026-07-14 push run succeeded while publishing `Local fallback` because the cloud secret was absent or unavailable. Document that the code can detect only presence, not inspect the secret value.

Update `README.md` and `PROJECT_CONTEXT.md` with:

```text
08:07 左右首次生成；09:07 按实际日期、7 篇结构、发布/归档一致性、URL 指纹和总结状态执行恢复检查。
complete 表示所有总结已由 DeepSeek 生成；degraded 表示内容已更新但包含公开来源自动摘录。
只有 workflow_dispatch 的 force 选项可以强制覆盖当天完整归档。
```

Also retain the manual requirement to configure the repository secret named exactly `DEEPSEEK_API_KEY`.

- [ ] **Step 2: Run the complete local test suite**

Run:

```powershell
pwsh -NoProfile -File scripts/test-daily-update-support.ps1
pwsh -NoProfile -File scripts/test-update-daily-rules.ps1
pwsh -NoProfile -File scripts/test-paper-selection.ps1
pwsh -NoProfile -File scripts/test-ai-selection.ps1
pwsh -NoProfile -File scripts/test-translation.ps1
node scripts/test-site-core.js
node scripts/test-frontend-language.js
pwsh -NoProfile -File scripts/test-app-contract.ps1
pwsh -NoProfile -File scripts/test-site-shell.ps1
pwsh -NoProfile -File scripts/test-visual-contract.ps1
```

Expected: every command exits 0 and prints its pass message; no warnings or parse errors are introduced.

- [ ] **Step 3: Run data and synchronization verification**

Run:

```powershell
Get-Content -Raw -Encoding UTF8 data/articles.json | ConvertFrom-Json | Out-Null
Get-ChildItem data/archive/*.json | ForEach-Object { Get-Content -Raw -Encoding UTF8 $_.FullName | ConvertFrom-Json | Out-Null }
pwsh -NoProfile -File scripts/sync-public.ps1
if ((Get-FileHash app.js).Hash -ne (Get-FileHash public/app.js).Hash) { throw "app.js is not synchronized" }
if ((Get-FileHash site-core.js).Hash -ne (Get-FileHash public/site-core.js).Hash) { throw "site-core.js is not synchronized" }
if ((Get-FileHash styles.css).Hash -ne (Get-FileHash public/styles.css).Hash) { throw "styles.css is not synchronized" }
```

Expected: JSON parsing succeeds and synchronized root/public files have no differences.

- [ ] **Step 4: Inspect the final diff for scope and secrets**

Run:

```powershell
git status --short
git diff --check
git diff -- . ':!scripts/start-web-server.ps1' ':!scripts/edit_template.py'
```

Expected: only planned files are changed; `.env.local`, secret values, `scripts/start-web-server.ps1`, and `scripts/edit_template.py` are absent from the implementation diff.

- [ ] **Step 5: Commit documentation**

```powershell
git add README.md PROJECT_CONTEXT.md CHANGELOG.md
git commit -m "docs: explain daily update recovery states"
```

- [ ] **Step 6: Verify the commit set**

Run:

```powershell
git log --oneline --decorate -8
git status --short
```

Expected: the task commits are present; only the user's pre-existing uncommitted files remain.

---

## Deployment Verification After Local Implementation

1. Confirm the repository Actions secret is named exactly `DEEPSEEK_API_KEY`; only its presence and update timestamp should be inspected, never its value.
2. Push the implementation commits to `main` only after local tests pass.
3. Observe the push-triggered run and confirm its status summary reports date, action, fingerprint, DeepSeek count, and source-extract count.
4. If the run reports `degraded`, verify the public page shows the disclosure and the next scheduled recovery uses `summary_upgrade` without changing the fingerprint.
5. At the next natural 09:07 recovery, verify stale content causes `fresh_generation`, a stale live file causes `repair_publish`, and valid complete content causes `already_complete`.
