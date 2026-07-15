# Daily Update Candidate Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent one AI candidate with incomplete DeepSeek output from aborting the entire seven-article daily update.

**Architecture:** Keep collection, ranking, and publication validation unchanged. Change the AI selection boundary so ranked candidates are analyzed one at a time, incomplete candidates are rejected locally, and later ranked candidates refill the required slots. When no repository DeepSeek key exists, retain source-extract candidates so the existing batch recovery provider can still translate them.

**Tech Stack:** PowerShell 7, GitHub Actions, DeepSeek chat completions, existing script-based regression suite.

## Global Constraints

- Publish exactly seven unique articles: three international items and four AI/paper items.
- Chinese display titles must pass `Test-ChineseDisplayTitle`.
- Do not publish a source-extract AI item when `DEEPSEEK_API_KEY` is configured.
- Preserve the keyless GitHub Models batch recovery path.
- Never modify live JSON until `Assert-DailyPayload` passes.

---

### Task 1: Isolate Failed AI Candidates and Refill Slots

**Files:**
- Modify: `scripts/update-daily.ps1`
- Test: `scripts/test-update-daily-rules.ps1`

**Interfaces:**
- Consumes: `Get-AiItems([int]$TargetCount)`, `Add-AiArticleAnalysis($Item)`, `Test-ChineseDisplayTitle([string]$Title)`.
- Produces: an array of at most `$TargetCount` analyzed AI articles; with a configured DeepSeek key, every returned item has `summarySource = "deepseek"` and a valid Chinese display title.

- [ ] **Step 1: Write the failing candidate-refill test**

Import `Get-AiItems`, stub the three candidate collectors, and return three ranked candidates: a highest-ranked application whose analysis degrades, a valid concept, and a lower-ranked valid application. Stub `Add-AiArticleAnalysis` so the first candidate has `summarySource = "source_extract"` and the others have valid Chinese titles. Assert that `Get-AiItems -TargetCount 2` returns the two valid candidates and excludes the degraded one.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-update-daily-rules.ps1
```

Expected: FAIL because the current pipeline selects two candidates before analysis and retains the degraded highest-ranked item.

- [ ] **Step 3: Implement candidate-level acceptance**

Replace the final `Select-Object -First $TargetCount | ForEach-Object` pipeline in `Get-AiItems` with an ordered loop:

```powershell
$accepted = @()
foreach ($candidate in $orderedCandidates) {
  $analyzed = Add-AiArticleAnalysis -Item $candidate
  $isComplete = $analyzed.summarySource -eq "deepseek" -and
    (Test-ChineseDisplayTitle -Title ([string]$analyzed.translations.zh.title))
  if ($env:DEEPSEEK_API_KEY -and -not $isComplete) {
    Write-Warning "Skipping AI candidate after incomplete DeepSeek analysis: $($candidate.id)"
    continue
  }
  $accepted += $analyzed
  if ($accepted.Count -ge $TargetCount) { break }
}
return $accepted
```

- [ ] **Step 4: Run focused and related tests and verify GREEN**

Run the daily-update rules, daily-update support, published-data, translation, AI-selection, and frontend-language tests. Expected: all commands exit `0`, and `git diff --check` reports no errors.

- [ ] **Step 5: Commit and deploy**

Stage only the plan, `scripts/update-daily.ps1`, and `scripts/test-update-daily-rules.ps1`; commit with `fix: refill failed AI candidates`; push `main`; trigger `workflow_dispatch` with `force=true`; verify the workflow succeeds, a `Daily article update` commit changes the content fingerprint, and the subsequent Pages deployment succeeds.
