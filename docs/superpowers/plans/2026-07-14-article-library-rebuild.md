# Article Library Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the visible article library with seven unique current articles, complete Chinese/English presentation, and permanent cross-day duplicate prevention.

**Architecture:** Put canonical identity and ledger operations in `daily-update-support.ps1`, enforce the bilingual/unique contract in the generator, and keep browser localization in `site-core.js`. A one-time reset script converts all removed payloads into a non-visible tombstone ledger before clearing archives.

**Tech Stack:** PowerShell 7/Windows PowerShell compatibility, vanilla JavaScript, JSON, GitHub Actions, GitHub Pages.

## Global Constraints

- Publish exactly 7 items: 3 international, 2 AI, and preferably 2 open papers.
- Never publish a canonical URL or normalized title already present in `data/seen-articles.json`.
- Chinese mode must use `translations.zh`; a Chinese title must contain at least one Han character.
- Highlights must be faithful source excerpts or concise source-grounded renderings, never generic template text.
- Validation must fail before replacing existing published data.
- Preserve the 08:00 generation and 09:00 unchanged-content recovery behavior.

---

### Task 1: Canonical identity and tombstone ledger

**Files:**
- Modify: `scripts/daily-update-support.ps1`
- Modify: `scripts/test-daily-update-support.ps1`
- Create: `data/seen-articles.json`

**Interfaces:**
- Produces: `Get-CanonicalArticleUrl([string]) -> [string]`, `Get-NormalizedArticleTitle([string]) -> [string]`, `Read-ArticleLedger([string]) -> object`, `Test-ArticleSeen($article,$ledger) -> [bool]`.

- [ ] **Step 1: Write failing identity tests**

```powershell
Assert-Equal (Get-CanonicalArticleUrl 'HTTPS://Example.com/a/?utm_source=x#part') 'https://example.com/a' 'Tracking and fragments must not create new identities.'
Assert-Equal (Get-NormalizedArticleTitle ' Codex: Usage UP! ') 'codexusageup' 'Title identity must ignore punctuation and case.'
Assert-True (Test-ArticleSeen ([pscustomobject]@{url='https://example.com/a';title='Other'}) ([pscustomobject]@{urls=@('https://example.com/a');titles=@()})) 'Ledger URL must reject a candidate.'
```

- [ ] **Step 2: Run the test and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-daily-update-support.ps1`

Expected: FAIL because `Get-CanonicalArticleUrl` is not defined.

- [ ] **Step 3: Implement minimal identity helpers**

```powershell
function Get-CanonicalArticleUrl { param([string]$Url) # parse, strip fragment/tracking query, normalize }
function Get-NormalizedArticleTitle { param([string]$Title) return (($Title.Normalize().ToLowerInvariant()) -replace '[^\p{L}\p{N}]','') }
function Test-ArticleSeen { param($Article,$Ledger) return $Ledger.urls -contains (Get-CanonicalArticleUrl $Article.url) -or $Ledger.titles -contains (Get-NormalizedArticleTitle $Article.title) }
```

- [ ] **Step 4: Run support tests and verify GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-daily-update-support.ps1`

Expected: `Daily update support tests passed.`

- [ ] **Step 5: Commit**

```text
git add scripts/daily-update-support.ps1 scripts/test-daily-update-support.ps1
git commit -m "feat: add persistent article identity rules"
```

### Task 2: Complete bilingual display contract

**Files:**
- Modify: `site-core.js`
- Modify: `scripts/test-frontend-language.js`
- Modify: `scripts/update-daily.ps1`
- Modify: `scripts/test-translation.ps1`
- Modify: `scripts/test-update-daily-rules.ps1`

**Interfaces:**
- Consumes: `article.translations.zh` and `article.translations.en`.
- Produces: `SiteCore.getLocalizedArticle(article, language)` with explicit Chinese and English resolution.

- [ ] **Step 1: Add failing Chinese-mode and payload-validation tests**

```javascript
const chinese = core.getLocalizedArticle({ title: "English source", translations: { zh: { title: "中文标题" } } }, "zh");
assert.equal(chinese.title, "中文标题");
```

```powershell
$invalid.translations.zh = $null
Assert-Throws { Assert-DailyPayload -Payload $payload } 'complete Simplified Chinese translation'
```

- [ ] **Step 2: Run focused tests and verify RED**

Run: `node scripts/test-frontend-language.js`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1`

Expected: the new zh-contract assertion fails.

- [ ] **Step 3: Require and generate `translations.zh`**

Update the DeepSeek JSON schema so both translation objects contain title/highlight/summary/failureAnalysis, build `translations.zh` from the Chinese response, and require a Han-containing zh title in `Assert-DailyPayload`. Source-extract fallback must also create a safe zh display title or refuse publication.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run: `node scripts/test-frontend-language.js`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-translation.ps1`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1`

Expected: all three print their passed messages.

- [ ] **Step 5: Commit**

```text
git add site-core.js scripts/update-daily.ps1 scripts/test-frontend-language.js scripts/test-translation.ps1 scripts/test-update-daily-rules.ps1
git commit -m "fix: require Chinese article titles"
```

### Task 3: Cross-day and same-topic selection

**Files:**
- Modify: `scripts/update-daily.ps1`
- Modify: `scripts/test-ai-selection.ps1`
- Modify: `scripts/test-paper-selection.ps1`
- Modify: `scripts/test-update-daily-rules.ps1`

**Interfaces:**
- Consumes: `Read-ArticleLedger data/seen-articles.json` and canonical identity helpers.
- Produces: candidate filters that exclude ledger collisions and a final `Assert-ArticleSetUnique` validation.

- [ ] **Step 1: Write failing ledger and similar-topic tests**

```powershell
$ledger = [pscustomobject]@{ urls=@('https://example.com/used'); titles=@('usedtitle') }
Assert-True (-not (Test-ArticleCandidate -Article ([pscustomobject]@{url='https://example.com/used';title='Fresh wording'}) -Ledger $ledger)) 'Used URL must be filtered before ranking.'
Assert-Throws { Assert-ArticleSetUnique @($natoA,$natoB) $ledger } 'same topic'
```

- [ ] **Step 2: Run selection tests and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-ai-selection.ps1`

Expected: FAIL because the candidate filter is not defined.

- [ ] **Step 3: Apply filtering before ranking and validation before publish**

Load the ledger once, filter news/AI/paper candidates by canonical identity, refill from remaining candidates, and reject exact or high-overlap title token pairs in the final seven items. Validate the final set against the ledger before computing its fingerprint.

- [ ] **Step 4: Run all selection/rule tests and verify GREEN**

Run: all PowerShell test scripts matching `test-ai-selection.ps1`, `test-paper-selection.ps1`, and `test-update-daily-rules.ps1`.

Expected: all three pass.

- [ ] **Step 5: Commit**

```text
git add scripts/update-daily.ps1 scripts/test-ai-selection.ps1 scripts/test-paper-selection.ps1 scripts/test-update-daily-rules.ps1
git commit -m "fix: prevent historical and topical duplicates"
```

### Task 4: Reset and regenerate the library

**Files:**
- Create: `scripts/reset-article-library.ps1`
- Create: `scripts/test-reset-article-library.ps1`
- Modify: `data/seen-articles.json`
- Modify: `data/articles.json`
- Delete: `data/archive/2026-07-06.json` through `data/archive/2026-07-14.json`
- Modify: `data/archive/index.json`

**Interfaces:**
- Produces: a tombstone ledger derived before deletion and one freshly generated issue.

- [ ] **Step 1: Test reset in a temporary fixture**

Create two fixture archives containing a repeated URL, run the reset helper against the fixture, and assert that the ledger has one canonical URL, dated archives are gone, and the index is empty.

- [ ] **Step 2: Run reset test and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-reset-article-library.ps1`

Expected: FAIL because reset script does not exist.

- [ ] **Step 3: Implement and run the reset**

The script must write the ledger atomically before removing dated JSON files. Run it against `data`, then run `scripts/update-daily.ps1 -ForceRefresh $true` so validation and publishing create today's sole archive.

- [ ] **Step 4: Validate regenerated content**

Assert: 7 total, 3 international, 2 AI, 2 papers when available, 7 unique canonical URLs, 7 unique normalized titles, no ledger collision, complete zh/en fields, and no generic highlights.

- [ ] **Step 5: Commit**

```text
git add scripts/reset-article-library.ps1 scripts/test-reset-article-library.ps1 data/seen-articles.json data/articles.json data/archive
git commit -m "content: rebuild article library"
```

### Task 5: Visual QA, complete verification, and release

**Files:**
- Generated ignored preview: `public/**`
- No production source changes unless a verified defect is found.

**Interfaces:**
- Consumes: the rebuilt JSON and existing dynamic site.
- Produces: verified local and GitHub Pages behavior.

- [ ] **Step 1: Run every automated test**

Run all `scripts/test-*.js` with Node and all `scripts/test-*.ps1` with ExecutionPolicy Bypass.

Expected: all tests pass.

- [ ] **Step 2: Synchronize and inspect the local visual page**

Run `scripts/sync-public.ps1`, serve the repository, inspect the archive and detail views in zh/en, and confirm no English-only title appears in Chinese mode.

- [ ] **Step 3: Review the full diff and data invariants**

Check `git diff --check`, the tombstone count, article/category counts, canonical uniqueness, translated title language, and archive index consistency.

- [ ] **Step 4: Merge to main and push**

Fast-forward or cherry-pick the reviewed commits onto `main`, preserving the user's unrelated dirty files, then push `main`.

- [ ] **Step 5: Verify GitHub Pages**

Poll the deployed HTML, JavaScript, current data, archive index, and today's archive until they match the pushed commit; inspect the live dynamic page in both languages.
