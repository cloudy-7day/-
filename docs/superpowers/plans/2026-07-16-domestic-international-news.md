# Domestic and International Daily News Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the daily payload to nine articles with three filtered domestic news items, two international politics/finance items, two AI items, and two paper-or-AI deep-reading items.

**Architecture:** Add a deterministic news-selection module beside the existing AI selection module, then make the daily collector attach scope metadata to official RSS candidates and select fixed domestic/international quotas before DeepSeek summarization. Keep three front-end entrances by introducing a virtual `news` route that groups `domestic` and `international`, while publication validation and recovery logic enforce the new nine-item contract without rewriting legacy archives.

**Tech Stack:** PowerShell 7-compatible scripts and tests, vanilla JavaScript/CommonJS tests, static HTML/CSS, GitHub Actions, JSON archives.

## Global Constraints

- Every new payload contains exactly 9 articles: 3 `domestic`, 2 `international`, and 4 items whose category is `ai` or `paper`.
- The AI and paper selection rules do not change; paper shortfalls continue to use qualified AI items.
- Candidate collection reads only official RSS title, excerpt, publication date, and direct article URL; it does not fetch article pages.
- Only `http` and `https` article URLs are eligible.
- Prefer items from the last 24 hours and permit items up to 48 hours old when necessary.
- Domestic entertainment, celebrity, sports, fashion, travel-guide, advertorial, pure-opinion, and low-impact promotional items are ineligible.
- International items must be politics or finance; target one of each and permit one class to fill both slots when the other is unavailable.
- A source may repeat when required, but importance outranks source diversity.
- If the exact 3 domestic + 2 international quota cannot be filled, fail before publication and preserve the current payload.
- Do not rewrite historical archive JSON files.
- Preserve the existing retry, content fingerprint, source-extract degradation, DeepSeek recovery, translation, paper readability, and safe publication behavior.

---

## File Structure

- Create `scripts/news-selection.ps1`: pure candidate eligibility, classification, scoring, diversity, and quota selection; no network calls or DeepSeek calls.
- Create `scripts/test-news-selection.ps1`: deterministic unit tests for exclusions, priorities, recency, politics/finance balance, fallback, and source diversity.
- Modify `scripts/update-daily.ps1`: source definitions, RSS candidate normalization, domestic/international selection, article conversion, nine-item assembly, and payload validation.
- Modify `scripts/test-update-daily-rules.ps1`: collector contract, source list, direct-link safety, and nine-item validator tests.
- Modify `scripts/daily-update-support.ps1`: nine-item recovery-state checks.
- Modify `scripts/test-daily-update-support.ps1`: legacy/new payload routing tests.
- Modify `site-core.js`: virtual news category mapping and backward-compatible route mapping.
- Modify `app.js`: render the combined news category with domestic/international sections and mapped back links.
- Modify `scripts/test-site-core.js`: news grouping and legacy-category compatibility tests.
- Modify `scripts/test-app-contract.ps1`: combined category rendering contract.
- Modify `scripts/test-published-data.ps1`: accept untouched seven-item legacy archives and validate nine-item archives when `domestic` exists.
- Modify `PROJECT_CONTEXT.md` and `CHANGELOG.md`: record the nine-item contract, source pool, filtering, and operational behavior.

---

### Task 1: Deterministic news selection module

**Files:**
- Create: `scripts/news-selection.ps1`
- Create: `scripts/test-news-selection.ps1`

**Interfaces:**
- Consumes: candidate objects with `id`, `title`, `source`, `url`, `publishedAt`, `sourceText`, and `scope`.
- Produces: `Test-NewsHardExcluded -Candidate`, `Get-DomesticNewsPriority -Candidate`, `Get-InternationalNewsKind -Candidate`, `Select-DomesticNewsCandidates -Candidates -Now -TargetCount`, and `Select-InternationalNewsCandidates -Candidates -Now -TargetCount`.

- [ ] **Step 1: Write failing selector tests**

Create `scripts/test-news-selection.ps1` with fixed UTC time and a helper that builds candidates:

```powershell
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "news-selection.ps1")

$now = [datetime]"2026-07-16T16:00:00Z"
function New-NewsCandidate {
  param([string]$Id, [string]$Scope, [string]$Title, [string]$Source = "Test", [int]$HoursAgo = 2)
  [pscustomobject]@{
    id = $Id; scope = $Scope; title = $Title; source = $Source
    url = "https://example.com/$Id"
    publishedAt = $now.AddHours(-$HoursAgo).ToString("o")
    sourceText = $Title
  }
}

$domestic = @(
  New-NewsCandidate "policy" "domestic" "国务院公布重要法律实施条例" "新华网"
  New-NewsCandidate "disaster" "domestic" "多地暴雨引发重大洪涝灾害 应急响应启动" "中国新闻网"
  New-NewsCandidate "science" "domestic" "我国科学家发现新型量子材料" "China Daily"
  New-NewsCandidate "economy" "domestic" "央行发布重要金融政策" "人民网"
  New-NewsCandidate "social" "domestic" "公共交通服务发生全国性调整" "中国新闻网"
  New-NewsCandidate "celebrity" "domestic" "明星新片登上娱乐热搜" "人民网"
  New-NewsCandidate "old" "domestic" "国务院公布另一项重要政策" "新华网" 60
)
$pickedDomestic = @(Select-DomesticNewsCandidates -Candidates $domestic -Now $now -TargetCount 3)
if (($pickedDomestic.id -join ",") -ne "policy,disaster,science") { throw "Domestic priority order is incorrect." }
if ($pickedDomestic.id -contains "celebrity" -or $pickedDomestic.id -contains "old") { throw "Excluded or stale domestic items were selected." }

$international = @(
  New-NewsCandidate "politics" "international" "Governments open ceasefire negotiations after border conflict" "NPR"
  New-NewsCandidate "finance" "international" "Central bank changes interest rates as inflation rises" "Reuters"
  New-NewsCandidate "finance-2" "international" "Global markets fall after new trade tariffs" "Guardian"
  New-NewsCandidate "sport" "international" "Football final draws record crowd" "Guardian"
)
$pickedInternational = @(Select-InternationalNewsCandidates -Candidates $international -Now $now -TargetCount 2)
if ($pickedInternational.id -notcontains "politics" -or $pickedInternational.id -notcontains "finance") { throw "International selection must target politics plus finance." }

$financeOnly = @($international | Where-Object { $_.id -like "finance*" })
if (@(Select-InternationalNewsCandidates -Candidates $financeOnly -Now $now -TargetCount 2).Count -ne 2) { throw "One international class must be able to fill both slots." }

Write-Host "News selection tests passed."
```

- [ ] **Step 2: Run the selector test and verify it fails**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-news-selection.ps1
```

Expected: FAIL because `scripts/news-selection.ps1` or the selector functions do not exist.

- [ ] **Step 3: Implement pure filtering and quota selection**

Create `scripts/news-selection.ps1`. Use case-insensitive keyword regexes, 48-hour eligibility, descending priority, and a two-pass source-diversity helper:

```powershell
function Get-NewsCandidateText {
  param($Candidate)
  return (([string]$Candidate.title + " " + [string]$Candidate.sourceText) -replace '\s+', ' ').Trim()
}

function Test-NewsCandidateFresh {
  param($Candidate, [datetime]$Now, [int]$MaximumAgeHours = 48)
  try { $published = ([datetime]$Candidate.publishedAt).ToUniversalTime() } catch { return $false }
  $age = $Now.ToUniversalTime() - $published
  return $age.TotalHours -ge 0 -and $age.TotalHours -le $MaximumAgeHours
}

function Test-NewsHardExcluded {
  param($Candidate)
  $text = Get-NewsCandidateText $Candidate
  return $text -match '(?i)娱乐|明星|影视|综艺|票房|体育|足球|篮球|时尚|穿搭|旅游攻略|购物|促销|celebrity|entertainment|movie|sports?|football|basketball|fashion|travel guide'
}

function Get-DomesticNewsPriority {
  param($Candidate)
  $text = Get-NewsCandidateText $Candidate
  if (Test-NewsHardExcluded $Candidate) { return 0 }
  if ($text -match '政治|国务院|中央|全国人大|全国政协|法律|法规|政策|监管|politic|government|regulation') { return 500 }
  if ($text -match '灾害|地震|洪涝|暴雨|台风|事故|应急|公共安全|救援|disaster|earthquake|flood|emergency') { return 400 }
  if ($text -match '科学家|科学发现|研究发现|技术突破|量子|航天|芯片|人工智能|science|discovery|breakthrough|quantum') { return 300 }
  if ($text -match '宏观经济|央行|金融政策|产业|贸易|就业|通胀|利率|economy|central bank|industry|trade') { return 200 }
  return 100
}

function Get-InternationalNewsKind {
  param($Candidate)
  $text = Get-NewsCandidateText $Candidate
  if (Test-NewsHardExcluded $Candidate) { return "" }
  if ($text -match '(?i)diplomac|government|election|parliament|president|minister|war|conflict|ceasefire|sanction|NATO|United Nations|policy|外交|选举|战争|冲突|制裁') { return "politics" }
  if ($text -match '(?i)central bank|interest rate|inflation|market|trade|tariff|energy|currency|econom|finance|央行|利率|通胀|市场|贸易|关税|能源|金融') { return "finance" }
  return ""
}

function Select-PriorityPreservingCandidates {
  param([object[]]$Candidates, [scriptblock]$Priority, [int]$TargetCount)
  $selected = @(); $usedSources = @{}
  $tiers = @($Candidates | Group-Object { [int](& $Priority $_) } | Sort-Object { [int]$_.Name } -Descending)
  foreach ($tier in $tiers) {
    $rankedTier = @($tier.Group | Sort-Object publishedAt -Descending)
    foreach ($item in @($rankedTier | Where-Object { -not $usedSources.ContainsKey([string]$_.source) })) {
      if ($selected.Count -ge $TargetCount) { break }
      $selected += $item; $usedSources[[string]$item.source] = $true
    }
    foreach ($item in @($rankedTier | Where-Object { $_.url -notin @($selected.url) })) {
      if ($selected.Count -ge $TargetCount) { break }
      $selected += $item; $usedSources[[string]$item.source] = $true
    }
    if ($selected.Count -ge $TargetCount) { break }
  }
  return @($selected)
}

function Select-DomesticNewsCandidates {
  param([object[]]$Candidates, [datetime]$Now = (Get-Date).ToUniversalTime(), [int]$TargetCount = 3)
  $ranked = @($Candidates | Where-Object {
    $_.scope -eq 'domestic' -and (Test-NewsCandidateFresh $_ $Now) -and (Get-DomesticNewsPriority $_) -gt 0
  } | Sort-Object @{ Expression = { Get-DomesticNewsPriority $_ }; Descending = $true }, @{ Expression = { [datetime]$_.publishedAt }; Descending = $true })
  return @(Select-PriorityPreservingCandidates -Candidates $ranked -Priority { param($item) Get-DomesticNewsPriority $item } -TargetCount $TargetCount)
}

function Select-InternationalNewsCandidates {
  param([object[]]$Candidates, [datetime]$Now = (Get-Date).ToUniversalTime(), [int]$TargetCount = 2)
  $eligible = @($Candidates | Where-Object { $_.scope -eq 'international' -and (Test-NewsCandidateFresh $_ $Now) -and (Get-InternationalNewsKind $_) })
  $politics = @($eligible | Where-Object { (Get-InternationalNewsKind $_) -eq 'politics' } | Sort-Object publishedAt -Descending)
  $finance = @($eligible | Where-Object { (Get-InternationalNewsKind $_) -eq 'finance' } | Sort-Object publishedAt -Descending)
  $balanced = @()
  if ($politics.Count) { $balanced += $politics[0] }
  if ($finance.Count) {
    $differentSource = @($finance | Where-Object { $_.source -notin @($balanced.source) } | Select-Object -First 1)
    $balanced += if ($differentSource.Count) { $differentSource[0] } else { $finance[0] }
  }
  $remaining = @($eligible | Where-Object { $_.url -notin @($balanced.url) } | Sort-Object publishedAt -Descending)
  return @(@($balanced + $remaining) | Select-Object -First $TargetCount)
}
```

- [ ] **Step 4: Run selector tests**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test-news-selection.ps1`

Expected: `News selection tests passed.`

- [ ] **Step 5: Commit the selector module**

```powershell
git add scripts/news-selection.ps1 scripts/test-news-selection.ps1
git commit -m "feat: add deterministic news selection rules"
```

---

### Task 2: Official RSS pool and five-news collection

**Files:**
- Modify: `scripts/update-daily.ps1:380-405, 445-465, 882-980, 1593-1597`
- Modify: `scripts/test-update-daily-rules.ps1:1-80`

**Interfaces:**
- Consumes: selectors from `scripts/news-selection.ps1` and existing `Invoke-WithRetry`, `Get-FeedItems`, `Get-FeedText`, `ConvertFrom-HtmlText`, `Select-UniqueArticleCandidates`, `New-ArticleAnalysis`, and translation helpers.
- Produces: `Get-OpenNewsFeeds`, `Get-OpenNewsCandidates`, `ConvertTo-NewsArticle`, and `Get-OpenNewsItems`; the last function returns exactly three `domestic` and two `international` articles or throws.

- [ ] **Step 1: Add failing collector contract assertions**

At the start of `scripts/test-update-daily-rules.ps1`, add source and architecture checks:

```powershell
if ($source -notmatch '\.\s+\(Join-Path \$PSScriptRoot "news-selection\.ps1"\)') { throw "Daily update must load the news selector module." }
@(
  'https://www.chinanews.com.cn/rss/china.xml',
  'http://www.xinhuanet.com/politics/news_politics.xml',
  'http://www.people.com.cn/rss/politics.xml',
  'http://www.chinadaily.com.cn/rss/china_rss.xml',
  'https://cs.mfa.gov.cn/gyls/lsgz/lsyj/rss_57447.xml'
) | ForEach-Object {
  if ($source -notmatch [regex]::Escape($_)) { throw "Missing official domestic source: $_" }
}
if ($source -notmatch 'function Get-OpenNewsCandidates' -or $source -notmatch 'function Get-OpenNewsItems') { throw "News collection must separate normalization from selection." }
if ($source -match 'Invoke-WebRequest\s+-Uri\s+\$link') { throw "News collection must not fetch article pages." }
```

Also extend the AST import section to import `Get-OpenNewsFeeds`, and assert every returned feed has `scope` in `domestic|international`, a source name, and an HTTP(S) URL.

- [ ] **Step 2: Run the rules test and verify it fails**

Run: `powershell -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1`

Expected: FAIL with missing domestic source/module assertions.

- [ ] **Step 3: Load the selector and replace feed configuration**

Near the top of `scripts/update-daily.ps1`, dot-source the module:

```powershell
. (Join-Path $PSScriptRoot "news-selection.ps1")
```

Replace `Get-OpenNewsFeeds` with structured entries using the official RSS endpoints verified during design:

```powershell
function Get-OpenNewsFeeds {
  $feeds = @(
    @{ source = "中国新闻网国内"; url = "https://www.chinanews.com.cn/rss/china.xml"; scope = "domestic"; language = "zh" },
    @{ source = "中国新闻网社会"; url = "https://www.chinanews.com.cn/rss/society.xml"; scope = "domestic"; language = "zh" },
    @{ source = "中国新闻网财经"; url = "https://www.chinanews.com.cn/rss/finance.xml"; scope = "domestic"; language = "zh" },
    @{ source = "新华网时政"; url = "http://www.xinhuanet.com/politics/news_politics.xml"; scope = "domestic"; language = "zh" },
    @{ source = "新华网金融"; url = "http://www.xinhuanet.com/finance/news_finance.xml"; scope = "domestic"; language = "zh" },
    @{ source = "人民网时政"; url = "http://www.people.com.cn/rss/politics.xml"; scope = "domestic"; language = "zh" },
    @{ source = "人民网社会"; url = "http://www.people.com.cn/rss/society.xml"; scope = "domestic"; language = "zh" },
    @{ source = "China Daily China"; url = "http://www.chinadaily.com.cn/rss/china_rss.xml"; scope = "domestic"; language = "en" },
    @{ source = "China Daily BizChina"; url = "http://www.chinadaily.com.cn/rss/bizchina_rss.xml"; scope = "domestic"; language = "en" },
    @{ source = "外交部领事安全提醒"; url = "https://cs.mfa.gov.cn/gyls/lsgz/lsyj/rss_57447.xml"; scope = "international"; language = "zh" },
    @{ source = "NPR World"; url = "https://feeds.npr.org/1004/rss.xml"; scope = "international"; language = "en" },
    @{ source = "The Guardian World"; url = "https://www.theguardian.com/world/rss"; scope = "international"; language = "en" },
    @{ source = "Reuters World"; url = "https://feeds.reuters.com/Reuters/worldNews"; scope = "international"; language = "en" }
  )
  if ($env:NEWS_FEED_URLS) {
    foreach ($url in @($env:NEWS_FEED_URLS.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
      $feeds += @{ source = "Custom open feed"; url = $url; scope = "international"; language = "unknown" }
    }
  }
  return $feeds
}
```

The MIIT page currently exposed by search is an HTML subscription index rather than a verifiable XML endpoint, so this implementation must not treat it as RSS or scrape it. Record MIIT as an unavailable optional source in `PROJECT_CONTEXT.md`; it can be added later only after an official XML endpoint is confirmed.

- [ ] **Step 4: Split normalization, selection, and article conversion**

Refactor `Get-OpenWorldNewsItems` into these three functions:

```powershell
function Get-OpenNewsCandidates {
  $candidates = @()
  foreach ($feedInfo in Get-OpenNewsFeeds) {
    try {
      $feed = Invoke-WithRetry -Operation {
        Invoke-RestMethod -Uri $feedInfo.url -Headers @{ "User-Agent" = "personal-info-library/0.1" } -TimeoutSec 30
      }
      $rank = 0
      foreach ($feedItem in @(Get-FeedItems -Feed $feed | Select-Object -First 12)) {
        $rank += 1
        $title = Get-FeedText -Value $feedItem.title
        $link = Get-FeedText -Value $feedItem.link
        $description = ConvertFrom-HtmlText -Value (Get-FeedText -Value $feedItem.description)
        try { $publishedAt = ([datetime](Get-FeedText -Value $feedItem.pubDate)).ToUniversalTime().ToString("o") } catch { continue }
        $safeUri = $null
        if (-not [uri]::TryCreate([string]$link, [System.UriKind]::Absolute, [ref]$safeUri) -or $safeUri.Scheme -notin @("http", "https")) { continue }
        if (-not $title) { continue }
        $candidates += [pscustomobject][ordered]@{
          id = "news-" + ([guid]::NewGuid().ToString("N")); title = $title
          source = [string]$feedInfo.source; url = $safeUri.AbsoluteUri; publishedAt = $publishedAt
          sourceText = if ($description) { $description } else { $title }
          scope = [string]$feedInfo.scope; language = [string]$feedInfo.language; feedRank = $rank
        }
      }
    } catch {
      Write-Warning "Skipping feed $($feedInfo.source): $($_.Exception.Message)"
    }
  }
  return @(Select-UniqueArticleCandidates -Articles @($candidates | Sort-Object publishedAt -Descending) -Ledger $script:ArticleLedger)
}

function ConvertTo-NewsArticle {
  param($Candidate, [ValidateSet("domestic", "international")][string]$Category)
  $analysis = New-ArticleAnalysis -Category $Category -Title ([string]$Candidate.title) `
    -Source ([string]$Candidate.source) -Url ([string]$Candidate.url) `
    -SourceText ([string]$Candidate.sourceText) -ScoreLabel "Open official RSS"
  return [ordered]@{
    id = [string]$Candidate.id; category = $Category; title = [string]$Candidate.title
    source = [string]$Candidate.source; url = [string]$Candidate.url; publishedAt = [string]$Candidate.publishedAt
    scoreLabel = "Open official RSS"
    selectionReason = if ($Category -eq "domestic") { "Domestic priority $((Get-DomesticNewsPriority $Candidate))" } else { "International $((Get-InternationalNewsKind $Candidate))" }
    highlight = $analysis.highlight; summary = $analysis.summary; failureAnalysis = $analysis.failureAnalysis
    summarySource = $analysis.summarySource; sourceExcerpt = $analysis.sourceExcerpt
    translations = [ordered]@{
      zh = Get-ChineseTranslationForAnalysis -Category $Category -Analysis $analysis
      en = Get-EnglishTranslationForAnalysis -Category $Category -Title ([string]$Candidate.title) -Analysis $analysis
    }
  }
}

function Get-OpenNewsItems {
  $candidates = @(Get-OpenNewsCandidates)
  $domestic = @(Select-DomesticNewsCandidates -Candidates $candidates -TargetCount 3)
  $international = @(Select-InternationalNewsCandidates -Candidates $candidates -TargetCount 2)
  if ($domestic.Count -ne 3 -or $international.Count -ne 2) {
    throw "News quota not met: domestic=$($domestic.Count)/3 international=$($international.Count)/2. Existing published data was not replaced."
  }
  $articles = @()
  $articles += $domestic | ForEach-Object { ConvertTo-NewsArticle -Candidate $_ -Category "domestic" }
  $articles += $international | ForEach-Object { ConvertTo-NewsArticle -Candidate $_ -Category "international" }
  return @($articles)
}
```

The normalized candidate must copy `scope`, `language`, RSS excerpt, and direct URL. `ConvertTo-NewsArticle` must pass the actual category to analysis and translations, set `selectionReason` to the matched class/priority, and retain `summarySource` and `sourceExcerpt` exactly as today.

- [ ] **Step 5: Add domestic analysis guidance and assemble five news items**

Add a `domestic` branch beside `international` in `New-ArticleAnalysis` and source-extract translation helpers:

```powershell
"domestic" { "This is important domestic Chinese news. Summarize the verifiable public impact and do not force a failure analysis." }
```

Replace the main call with:

```powershell
$articles = @()
$articles += Get-OpenNewsItems
```

Leave the AI/paper assembly unchanged.

- [ ] **Step 6: Run focused tests**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-news-selection.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
```

Expected: both scripts print their PASS messages. Network collection is not executed by these unit tests.

- [ ] **Step 7: Commit feed and collector integration**

```powershell
git add scripts/update-daily.ps1 scripts/test-update-daily-rules.ps1
git commit -m "feat: collect domestic and international news quotas"
```

---

### Task 3: Nine-item publication and recovery contract

**Files:**
- Modify: `scripts/update-daily.ps1:91-118`
- Modify: `scripts/daily-update-support.ps1:342-345`
- Modify: `scripts/test-update-daily-rules.ps1:200-360`
- Modify: `scripts/test-daily-update-support.ps1`
- Modify: `scripts/test-published-data.ps1:20-40`

**Interfaces:**
- Consumes: article categories emitted by Task 2.
- Produces: `Assert-DailyPayload` and `Get-DailyUpdateAction` enforcing the nine-item live contract while published-data tests recognize untouched legacy archives.

- [ ] **Step 1: Change test fixtures to the new contract and add legacy recovery coverage**

In `scripts/test-update-daily-rules.ps1`, construct:

```powershell
$validArticles = @(
  New-TestArticle -Id "domestic-1" -Category "domestic"
  New-TestArticle -Id "domestic-2" -Category "domestic"
  New-TestArticle -Id "domestic-3" -Category "domestic"
  New-TestArticle -Id "news-1" -Category "international"
  New-TestArticle -Id "news-2" -Category "international"
  New-TestArticle -Id "ai-1" -Category "ai"
  New-TestArticle -Id "ai-2" -Category "ai"
  New-TestArticle -Id "paper-1" -Category "paper"
  New-TestArticle -Id "paper-2" -Category "paper"
)
```

In `scripts/test-daily-update-support.ps1`, add one current-day nine-item payload expected to route to `already_complete`, then remove a domestic item and expect `fresh_generation`. Keep a seven-item legacy archive only as `PreviousArchive`; it must not make a valid current-day nine-item payload stale.

- [ ] **Step 2: Run both tests and verify contract failures**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-daily-update-support.ps1
```

Expected: FAIL because validators still require seven items and three international items.

- [ ] **Step 3: Update publication validation**

In `Assert-DailyPayload`, replace the old count checks with:

```powershell
if ($items.Count -ne 9) { throw "Daily payload must contain exactly 9 articles; collected $($items.Count). Existing published data was not replaced." }
$domesticCount = @($items | Where-Object { $_.category -eq "domestic" }).Count
$internationalCount = @($items | Where-Object { $_.category -eq "international" }).Count
if ($domesticCount -ne 3 -or $internationalCount -ne 2) {
  throw "Daily payload must contain exactly 3 domestic and 2 international news items."
}
$allowedCategories = @("domestic", "international", "ai", "paper")
```

Keep the existing `ai + paper = 4`, translation, uniqueness, date, fingerprint, paper-card, and source validation unchanged.

- [ ] **Step 4: Update recovery-state validation**

In `Get-DailyUpdateAction`, use:

```powershell
$domesticCount = @($items | Where-Object { $_.category -eq "domestic" }).Count
$internationalCount = @($items | Where-Object { $_.category -eq "international" }).Count
$readingCount = @($items | Where-Object { $_.category -in @("ai", "paper") }).Count
if ($items.Count -ne 9 -or $domesticCount -ne 3 -or $internationalCount -ne 2 -or $readingCount -ne 4) {
  return "fresh_generation"
}
```

- [ ] **Step 5: Make published-data regression checks conditional for legacy archives**

In `scripts/test-published-data.ps1`, branch on domestic presence:

```powershell
$articles = @($payload.articles)
$hasDomestic = @($articles | Where-Object category -eq "domestic").Count -gt 0
if ($hasDomestic) {
  Assert-True ($articles.Count -eq 9) "New archives must contain exactly nine articles: $($file.Name)"
  Assert-True (@($articles | Where-Object category -eq "domestic").Count -eq 3) "New archives must contain three domestic articles."
  Assert-True (@($articles | Where-Object category -eq "international").Count -eq 2) "New archives must contain two international articles."
} else {
  Assert-True ($articles.Count -eq 7) "Legacy archives must retain seven articles: $($file.Name)"
  Assert-True (@($articles | Where-Object category -eq "international").Count -eq 3) "Legacy archives must retain three international articles."
}
Assert-True (@($articles | Where-Object { $_.category -in @("ai", "paper") }).Count -eq 4) "Every archive must contain four deep-reading articles."
```

- [ ] **Step 6: Run validation and support tests**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-daily-update-support.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-published-data.ps1
```

Expected: all three scripts print PASS. Existing archives remain unmodified.

- [ ] **Step 7: Commit the nine-item contract**

```powershell
git add scripts/update-daily.ps1 scripts/daily-update-support.ps1 scripts/test-update-daily-rules.ps1 scripts/test-daily-update-support.ps1 scripts/test-published-data.ps1
git commit -m "feat: enforce nine-item daily payload"
```

---

### Task 4: Combined “天下要闻” front-end category

**Files:**
- Modify: `site-core.js:7-40, 42-50, 146-157`
- Modify: `app.js:85-100, 139-160, 174-190`
- Modify: `scripts/test-site-core.js`
- Modify: `scripts/test-app-contract.ps1`

**Interfaces:**
- Consumes: articles categorized as `domestic` or `international`, including legacy archives with only `international`.
- Produces: `SiteCore.getDisplayCategory(category) -> "news"|"ai"|"paper"`, a `news` route, news grouping, and sectioned rendering.

- [ ] **Step 1: Write failing core and app contract tests**

Change the first `CATEGORY_CONFIG` expectation in `scripts/test-site-core.js` and add:

```javascript
assert.deepEqual(core.parseRoute("#/category/international"), { name: "category", category: "news" });
assert.equal(core.getDisplayCategory("domestic"), "news");
assert.equal(core.getDisplayCategory("international"), "news");
const articles = [
  { category: "domestic", title: "国内" },
  { category: "international", title: "国际" },
  { category: "ai", title: "工具" },
  { category: "paper", title: "论文" },
];
assert.equal(core.groupArticles(articles).news.length, 2);
```

Add to `scripts/test-app-contract.ps1`:

```powershell
if ($source -notmatch '国内要闻' -or $source -notmatch '国际要闻') { throw "The news page must render domestic and international sections." }
if ($source -notmatch 'SiteCore\.getDisplayCategory') { throw "Article navigation must map news subcategories to the shared route." }
```

- [ ] **Step 2: Run front-end tests and verify they fail**

Run:

```powershell
node scripts/test-site-core.js
powershell -ExecutionPolicy Bypass -File scripts/test-app-contract.ps1
```

Expected: FAIL because `news` and `getDisplayCategory` do not exist.

- [ ] **Step 3: Add the virtual news category**

In `site-core.js`, replace the `international` display entry with:

```javascript
news: {
  zh: "天下要闻",
  en: "Daily News",
  kickerZh: "观天下大事",
  kickerEn: "Signals at home and abroad",
  creature: "feifei",
},
```

Add and export:

```javascript
function getDisplayCategory(category) {
  return category === "domestic" || category === "international" ? "news" : category;
}
```

Make `parseRoute` map legacy `#/category/international` to `{ name: "category", category: "news" }`. Make `groupArticles` filter by `getDisplayCategory(article.category)`.

- [ ] **Step 4: Render domestic and international sections in the shared category**

In `renderCategory`, filter using `SiteCore.getDisplayCategory(article.category)`. When `category === "news"`, render two labeled sections in order:

```javascript
const renderNewsSection = (label, scope) => {
  const scoped = items.filter(({ article }) => article.category === scope);
  return `<section class="news-scope" data-news-scope="${scope}">
    <h2>${label}</h2>
    <div class="article-index">${scoped.map(({ article, index }, position) => renderIndexCard(article, index, position)).join("")}</div>
  </section>`;
};
const categoryContent = category === "news"
  ? renderNewsSection(state.language === "en" ? "China" : "国内要闻", "domestic") +
    renderNewsSection(state.language === "en" ? "World" : "国际要闻", "international")
  : `<div class="article-index">${items.map(({ article, index }, position) => renderIndexCard(article, index, position)).join("")}</div>`;
```

In `renderArticle`, resolve the config and back route through `SiteCore.getDisplayCategory(article.category)` so both new and legacy news articles return to `#/category/news`.

- [ ] **Step 5: Run front-end tests**

Run:

```powershell
node scripts/test-site-core.js
powershell -ExecutionPolicy Bypass -File scripts/test-app-contract.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-site-shell.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-visual-contract.ps1
```

Expected: all four tests pass.

- [ ] **Step 6: Commit the combined news view**

```powershell
git add site-core.js app.js scripts/test-site-core.js scripts/test-app-contract.ps1
git commit -m "feat: group domestic and international daily news"
```

---

### Task 5: Documentation, full verification, and safe handoff

**Files:**
- Modify: `PROJECT_CONTEXT.md`
- Modify: `CHANGELOG.md`
- Verify only: `.github/workflows/daily-update.yml`

**Interfaces:**
- Consumes: completed behavior from Tasks 1-4.
- Produces: current operational documentation and verification evidence; does not generate live data or rewrite archives.

- [ ] **Step 1: Update project documentation**

In `PROJECT_CONTEXT.md`, replace the current goal list with:

```markdown
当前目标是每天自动整理 9 篇内容：

- 3 篇国内要闻
- 2 篇国际政治或金融新闻
- 2 篇 AI 应用文章
- 2 篇应用型论文；论文不足时由合格 AI 应用文章补位

国内新闻候选来自中国新闻网、新华网、人民网和 China Daily 的官方 RSS；外交部领事安全提醒参与国际重大安全候选。工信部只在确认官方 XML 地址后加入，HTML 订阅页不作为抓取入口。新闻优先最近 24 小时，必要时放宽到 48 小时；娱乐、明星、体育、时尚、旅游攻略、消费软文和纯评论不进入新闻位。新归档执行 9 篇结构，旧归档保持原有 7 篇数据并继续兼容显示。
```

In the automation/status sections, replace checks described as `7 篇结构` with `9 篇结构（3 篇国内、2 篇国际、4 篇 AI/论文）`, and state that a quota shortfall aborts publication and preserves the previous payload.

At the top of `CHANGELOG.md`, add a dated entry with these exact headings:

```markdown
## 2026-07-16

### 增加国内要闻并将每日内容扩展为 9 篇

改了什么：

为什么这样改：

对使用的影响：
```

Use this complete entry body:

```markdown
改了什么：

每日内容从 7 篇扩展为 9 篇：3 篇国内要闻、2 篇国际政治或金融新闻，以及原有 2 篇 AI 应用和 2 篇论文/AI 补位内容。国内候选接入中国新闻网、新华网、人民网和 China Daily 官方 RSS，外交部安全提醒作为国际重大事件补充；新增可测试的重要性排序、娱乐软文排除和 24/48 小时时效规则。网页把原“天下异闻”改为“天下要闻”，在同一入口分组显示国内和国际新闻。

为什么这样改：

原有新闻全部偏国际，日常阅读与国内现实联系较弱。固定 3 篇国内、2 篇国际可以同时覆盖国内政策、灾害、科学和社会变化，以及国际政治与金融信号；规则筛选也避免为了凑数量混入娱乐内容。

对使用的影响：

每天发布前必须验证 9 篇结构。单个 RSS 失败时会重试并从其他公开来源补足；严格重大新闻不足时允许宏观经济、产业政策和普通社会新闻补位。最终仍无法凑齐 3 篇国内和 2 篇国际时，本次发布失败并保留上一份完整数据。旧的 7 篇历史归档不会被改写，仍可正常查看。
```

- [ ] **Step 2: Run every focused regression test**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/test-news-selection.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-ai-selection.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-paper-selection.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-daily-update-support.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-published-data.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-translation.ps1
node scripts/test-site-core.js
node scripts/test-frontend-language.js
powershell -ExecutionPolicy Bypass -File scripts/test-app-contract.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-site-shell.ps1
powershell -ExecutionPolicy Bypass -File scripts/test-visual-contract.ps1
```

Expected: every command exits 0 and prints its success message. Do not run `scripts/update-daily.ps1` during verification because that performs network calls and changes live data.

- [ ] **Step 3: Verify the workflow still exercises the updated test**

Run:

```powershell
Select-String -Path .github/workflows/daily-update.yml -Pattern 'test-update-daily-rules.ps1|update-daily.ps1'
```

Expected: the workflow runs the updated rule test before or as part of the daily update path. If the workflow currently omits the rule test, add a named PowerShell test step before the update step and rerun the source-level workflow assertions.

- [ ] **Step 4: Review the final diff and confirm unrelated changes are excluded**

Run:

```powershell
git status --short
git diff --check
git diff -- scripts/news-selection.ps1 scripts/test-news-selection.ps1 scripts/update-daily.ps1 scripts/daily-update-support.ps1 scripts/test-update-daily-rules.ps1 scripts/test-daily-update-support.ps1 scripts/test-published-data.ps1 site-core.js app.js scripts/test-site-core.js scripts/test-app-contract.ps1 PROJECT_CONTEXT.md CHANGELOG.md
```

Expected: no whitespace errors; `scripts/start-web-server.ps1`, `scripts/edit_template.py`, and the pre-existing redesign plan are not included in this feature diff or commits.

- [ ] **Step 5: Commit documentation**

```powershell
git add PROJECT_CONTEXT.md CHANGELOG.md
git commit -m "docs: describe nine-item daily news mix"
```

- [ ] **Step 6: Invoke completion verification and branch-finishing workflows**

Use `superpowers:verification-before-completion` to rerun the final evidence commands, then use `superpowers:requesting-code-review`. If all review findings are resolved and tests still pass, use `superpowers:finishing-a-development-branch` to present merge, PR, or local-keep options. Do not push or open a pull request without explicit user authorization.
