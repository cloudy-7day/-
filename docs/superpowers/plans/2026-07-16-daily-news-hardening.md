# Daily News Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dead Reuters feed, close sports and conversion-quality gaps, and make the pull request run the complete read-only regression suite.

**Architecture:** Keep the existing feed collector, pure selector module, conversion-refill loop, and final payload validator. Tighten behavior at their current boundaries: source configuration, hard exclusion, candidate acceptance, and GitHub Actions event routing. No live article page is fetched and no JSON payload is generated during testing.

**Tech Stack:** Windows PowerShell 5.1-compatible and PowerShell 7-compatible scripts, Node.js CommonJS tests, GitHub Actions YAML, Python 3.12 with PyYAML/pypdf for verification.

## Global Constraints

- Preserve exactly 3 `domestic`, 2 `international`, and 4 `ai`/`paper` items in every new payload.
- Preserve the 48-hour maximum news age and politics-or-finance international classification.
- Read only RSS title, excerpt, date, and direct HTTP(S) article URL; never fetch news article pages.
- Do not modify generated JSON, live payloads, or historical archives.
- Candidate-quality failures must refill from remaining eligible candidates before the update is rejected.
- Pull-request checks must never invoke `scripts/update-daily.ps1` as a live updater, stage data, commit, or push.

---

### Task 1: Replace the inactive Reuters RSS source

**Files:**
- Modify: `scripts/test-update-daily-rules.ps1:234-269`
- Modify: `scripts/update-daily.ps1:393-406`
- Modify: `PROJECT_CONTEXT.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `Get-OpenNewsFeeds` returning objects with `source`, `url`, `scope`, and `language`.
- Produces: one `BBC Business` international feed at `https://feeds.bbci.co.uk/news/business/rss.xml`, with no active Reuters feed.

- [ ] **Step 1: Write the failing source-contract test**

Replace the Reuters URL in `$expectedOfficialFeeds` with:

```powershell
"https://feeds.bbci.co.uk/news/business/rss.xml"
```

Add immediately after the expected-feed loop:

```powershell
if (@($newsFeeds | Where-Object { $_.url -eq "https://feeds.reuters.com/Reuters/worldNews" }).Count -ne 0) {
  throw "The inactive Reuters RSS endpoint must not remain in the default feed pool."
}
$bbcBusiness = @($newsFeeds | Where-Object { $_.url -eq "https://feeds.bbci.co.uk/news/business/rss.xml" })
if ($bbcBusiness.Count -ne 1 -or $bbcBusiness[0].scope -ne "international" -or $bbcBusiness[0].language -ne "en") {
  throw "BBC Business must be configured once as an English international feed."
}
```

- [ ] **Step 2: Run the rule test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
```

Expected: FAIL with `Missing official open-news feed: https://feeds.bbci.co.uk/news/business/rss.xml` or the inactive Reuters assertion.

- [ ] **Step 3: Replace the feed entry**

In `Get-OpenNewsFeeds`, replace:

```powershell
@{ source = "Reuters World"; url = "https://feeds.reuters.com/Reuters/worldNews"; scope = "international"; language = "en" }
```

with:

```powershell
@{ source = "BBC Business"; url = "https://feeds.bbci.co.uk/news/business/rss.xml"; scope = "international"; language = "en" }
```

Update `PROJECT_CONTEXT.md` and the current `CHANGELOG.md` entry to list BBC Business as the international-finance-oriented public RSS replacement and record that the inactive Reuters endpoint was removed.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-news-selection.ps1
```

Expected: both tests print their pass messages and exit 0.

- [ ] **Step 5: Commit**

```powershell
git add scripts/test-update-daily-rules.ps1 scripts/update-daily.ps1 PROJECT_CONTEXT.md CHANGELOG.md
git commit -m "fix: replace inactive Reuters news feed"
```

---

### Task 2: Exclude named global sports events

**Files:**
- Modify: `scripts/test-news-selection.ps1`
- Modify: `scripts/news-selection.ps1:5-17`

**Interfaces:**
- Consumes: `Test-NewsHardExcluded -Candidate` and `Get-InternationalNewsKind -Candidate`.
- Produces: hard exclusion of World Cup/FIFA World Cup/Olympic/Olympics/世界杯/奥运/奥运会 before domestic or international classification.

- [ ] **Step 1: Write failing selector fixtures**

Add after the existing sports test:

```powershell
$namedSportsEvents = @(
  New-NewsCandidate -Id "world-cup-finance" -Title "Financial winners and losers from the World Cup" -Scope "international"
  New-NewsCandidate -Id "olympic-policy" -Title "Government announces Olympic policy package" -Scope "international"
  New-NewsCandidate -Id "world-cup-cn" -Title ([regex]::Unescape("\u4e16\u754c\u676f\u5546\u4e1a\u6536\u5165\u4e0e\u91d1\u878d\u5e02\u573a")) -Scope "international"
  New-NewsCandidate -Id "olympic-cn" -Title ([regex]::Unescape("\u5965\u8fd0\u4f1a\u7ecf\u6d4e\u653f\u7b56")) -Scope "international"
)
foreach ($candidate in $namedSportsEvents) {
  Assert-True (Test-NewsHardExcluded -Candidate $candidate) "Named sports event '$($candidate.id)' must be hard excluded."
  Assert-Equal (Get-InternationalNewsKind -Candidate $candidate) $null "Named sports events must not classify as international finance or politics."
}
```

- [ ] **Step 2: Run the selector test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-news-selection.ps1
```

Expected: FAIL for `world-cup-finance` because the current pattern classifies it as finance.

- [ ] **Step 3: Extend the precise hard-exclusion terms**

Add these alternatives to `$script:NewsHardExclusionPattern`:

```powershell
"\b(?:world\s+cup|fifa\s+world\s+cup|olympics?|olympic)\b",
"\u4e16\u754c\u676f", "\u5965\u8fd0", "\u5965\u8fd0\u4f1a"
```

Do not add generic `match`, `games`, or `cup` terms.

- [ ] **Step 4: Run the selector and rule tests and verify GREEN**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-news-selection.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```powershell
git add scripts/news-selection.ps1 scripts/test-news-selection.ps1
git commit -m "fix: exclude named international sports events"
```

---

### Task 3: Refill news candidates rejected by publication-quality checks

**Files:**
- Modify: `scripts/test-update-daily-rules.ps1:337-460`
- Modify: `scripts/update-daily.ps1:1010-1025`

**Interfaces:**
- Consumes: `Test-NewsArticleConversionComplete -Article <object> -Category <domestic|international>`.
- Produces: `$false` for any converted news item that would fail the news-specific final publication checks, allowing `Convert-NewsCandidateQuota` to remove its URL and refill.

- [ ] **Step 1: Make the valid fixture satisfy source-extract metadata**

Add to `New-ConvertedNewsFixture` beside `summarySource`:

```powershell
sourceExcerpt = "Verifiable fixture source excerpt."
```

This is test-fixture correctness, not the new assertion.

- [ ] **Step 2: Add a failing invalid-quality refill test**

After the existing incomplete-conversion refill test, reset the candidate pool to include `domestic-backup`, then configure the first conversion to return a non-Chinese `zh.title`:

```powershell
$script:failedDomesticOnce = $false
$script:domesticFailureMode = "invalid-quality"
```

Extend the fixture conversion branch:

```powershell
if ($script:domesticFailureMode -eq "invalid-quality") {
  $invalid = New-ConvertedNewsFixture -Candidate $Candidate -Category $Category
  $invalid.translations.zh.title = "English title only"
  return $invalid
}
```

Then assert:

```powershell
$qualityRefilled = @(Get-OpenNewsItems)
if (@($qualityRefilled | Where-Object id -eq "domestic-policy").Count -ne 0 -or
    @($qualityRefilled | Where-Object id -eq "domestic-backup").Count -ne 1) {
  throw "A converted news item that fails Chinese display-title quality must be rejected and refilled."
}
```

- [ ] **Step 3: Run the rule test and verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
```

Expected: FAIL with `A converted news item that fails Chinese display-title quality must be rejected and refilled.`

- [ ] **Step 4: Tighten `Test-NewsArticleConversionComplete` minimally**

After the required field loops, add:

```powershell
if ($Article.summarySource -notin @("deepseek", "source_extract")) { return $false }
if ($Article.summarySource -eq "source_extract" -and [string]::IsNullOrWhiteSpace([string]$Article.sourceExcerpt)) { return $false }

$chinese = $Article.translations.zh
$english = $Article.translations.en
if (-not (Test-ChineseDisplayTitle -Title ([string]$chinese.title))) { return $false }
if ([string]$Article.highlight.Length -gt 260 -or
    [string]$chinese.highlight.Length -gt 260 -or
    [string]$english.highlight.Length -gt 260) { return $false }
if (Test-ForbiddenHighlightOpening -Text ([string]$Article.highlight)) { return $false }
if (Test-ForbiddenHighlightOpening -Text ([string]$chinese.highlight)) { return $false }
if (Test-ForbiddenFallbackText -Text "$($Article.summary) $($Article.failureAnalysis) $($chinese.summary) $($chinese.failureAnalysis) $($english.summary) $($english.failureAnalysis)") { return $false }
```

Use `.Length` directly on the already-required non-empty strings; do not cast the numeric length to string in the implementation.

- [ ] **Step 5: Add direct predicate cases for the remaining boundaries**

Create valid fixtures, mutate one field at a time, and assert `$false` for:

```powershell
summarySource = "unknown"
sourceExcerpt = "" when summarySource is "source_extract"
highlight = ("x" * 261)
translations.zh.highlight = "本文介绍了模板内容"
summary = "Local fallback: candidate collected automatically"
```

Also assert that an unchanged `New-ConvertedNewsFixture` returns `$true`.

- [ ] **Step 6: Run focused tests and verify GREEN**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-translation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-daily-update-support.ps1
```

Expected: all three pass; warning output from injected conversion failures is expected.

- [ ] **Step 7: Commit**

```powershell
git add scripts/update-daily.ps1 scripts/test-update-daily-rules.ps1
git commit -m "fix: refill news after quality validation failures"
```

---

### Task 4: Add read-only pull-request validation

**Files:**
- Modify: `scripts/test-update-daily-rules.ps1:1-140`
- Modify: `.github/workflows/daily-update.yml`

**Interfaces:**
- Consumes: GitHub events `pull_request`, `push`, `schedule`, and `workflow_dispatch`.
- Produces: `validate` job for pull requests and an `update` job guarded from pull requests.

- [ ] **Step 1: Add failing workflow contract assertions**

Add source-level checks that require:

```powershell
if ($workflowSource -notmatch '(?m)^\s*pull_request:\s*$') { throw "Workflow must validate pull requests." }
if ($workflowSource -notmatch '(?m)^\s*validate:\s*$') { throw "Workflow must define a read-only validation job." }
if ($workflowSource -notmatch 'github\.event_name\s*==\s*''pull_request''') { throw "Validation job must run only for pull requests." }
if ($workflowSource -notmatch 'github\.event_name\s*!=\s*''pull_request''') { throw "Live update job must not run for pull requests." }
```

For each of the ten PowerShell and two Node test paths, assert the path occurs inside the `validate` job text. Also assert that the extracted `validate` job text does not contain:

```powershell
./scripts/update-daily.ps1
git add
git commit
git push
```

Require top-level `contents: read` and job-level update permissions containing `contents: write` and `models: read`.

- [ ] **Step 2: Run the rule test and verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
```

Expected: FAIL with `Workflow must validate pull requests.`

- [ ] **Step 3: Add the pull-request trigger and least-privilege defaults**

Add under `on`:

```yaml
  pull_request:
    paths:
      - ".github/workflows/daily-update.yml"
      - "scripts/**"
      - "app.js"
      - "site-core.js"
      - "data/**"
      - "PROJECT_CONTEXT.md"
      - "CHANGELOG.md"
```

Change top-level permissions to:

```yaml
permissions:
  contents: read
```

- [ ] **Step 4: Add the read-only validation job**

Before `update`, add:

```yaml
  validate:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - name: Check out pull request
        uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install PDF extraction dependency
        run: python -m pip install pypdf==6.10.2
      - name: Run PowerShell regression tests
        shell: pwsh
        run: |
          ./scripts/test-news-selection.ps1
          ./scripts/test-ai-selection.ps1
          ./scripts/test-paper-selection.ps1
          ./scripts/test-update-daily-rules.ps1
          ./scripts/test-daily-update-support.ps1
          ./scripts/test-published-data.ps1
          ./scripts/test-translation.ps1
          ./scripts/test-app-contract.ps1
          ./scripts/test-site-shell.ps1
          ./scripts/test-visual-contract.ps1
      - name: Run frontend regression tests
        run: |
          node scripts/test-site-core.js
          node scripts/test-frontend-language.js
```

- [ ] **Step 5: Guard and authorize the live update job**

Add to `update`:

```yaml
    if: github.event_name != 'pull_request'
    permissions:
      contents: write
      models: read
```

Keep its existing selector-test → rule-test → updater order and publication commit step unchanged.

- [ ] **Step 6: Run workflow tests and parse YAML**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
python -c "import pathlib,yaml; yaml.safe_load(pathlib.Path('.github/workflows/daily-update.yml').read_text(encoding='utf-8')); print('workflow YAML parse OK')"
```

Expected: rule tests pass and YAML prints `workflow YAML parse OK`.

- [ ] **Step 7: Commit**

```powershell
git add .github/workflows/daily-update.yml scripts/test-update-daily-rules.ps1
git commit -m "ci: validate daily news changes on pull requests"
```

---

### Task 5: Full verification and PR update

**Files:**
- Verify only: all files changed in Tasks 1-4
- Do not modify: `data/articles.json`, `data/archive/*.json`

**Interfaces:**
- Consumes: completed branch commits.
- Produces: fresh local evidence and an updated remote draft PR.

- [ ] **Step 1: Run all ten PowerShell tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-news-selection.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-ai-selection.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-paper-selection.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-daily-update-support.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-published-data.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-translation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-app-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-site-shell.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-visual-contract.ps1
```

Expected: 10 pass messages and 10 exit-0 results.

- [ ] **Step 2: Run both Node tests**

```powershell
node scripts/test-site-core.js
node scripts/test-frontend-language.js
```

Expected: both pass.

- [ ] **Step 3: Run syntax, YAML, diff, and scope checks**

Parse `scripts/update-daily.ps1`, `scripts/daily-update-support.ps1`, and `scripts/news-selection.ps1` with the PowerShell AST parser and require zero errors. Parse the workflow with PyYAML. Then run:

```powershell
git diff --check origin/main...HEAD
git diff --name-only origin/main...HEAD -- '*.json'
git status --short
```

Expected: no whitespace errors, no JSON paths, and a clean worktree.

- [ ] **Step 4: Review the final diff**

Confirm every production change is covered by a test that was observed failing before implementation. Confirm no article-page fetch, quota change, archive rewrite, live updater execution, or unrelated root-worktree file appears.

- [ ] **Step 5: Push and inspect PR checks**

```powershell
git push
gh pr view 1 --json url,isDraft,state,statusCheckRollup
```

Expected: branch push succeeds; PR #1 remains open and draft; the pull-request validation workflow appears in the check rollup (running or completed).
