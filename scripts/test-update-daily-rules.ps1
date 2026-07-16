$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "update-daily.ps1"
$source = Get-Content -Raw -Encoding UTF8 $scriptPath
$supportSource = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot "daily-update-support.ps1")
$workflowPath = Join-Path (Split-Path -Parent $PSScriptRoot) ".github/workflows/daily-update.yml"
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
. (Join-Path $PSScriptRoot "article-selection.ps1")
. (Join-Path $PSScriptRoot "daily-update-support.ps1")
. (Join-Path $PSScriptRoot "news-selection.ps1")

if ($source -notmatch '(?m)^\. \(Join-Path \$PSScriptRoot "news-selection\.ps1"\)\s*$') {
  throw "The daily updater must import the domestic/international news selection module."
}

foreach ($functionName in @("Get-OpenNewsFeeds", "Get-OpenNewsCandidates", "ConvertTo-NewsArticle", "Get-OpenNewsItems")) {
  if ($source -notmatch "function\s+$functionName\b") {
    throw "The daily updater is missing required news function: $functionName"
  }
}

if ($source -notmatch '(?m)^\$articles \+= Get-OpenNewsItems\s*$') {
  throw "The main assembly must collect the domestic/international news quotas through Get-OpenNewsItems."
}

if ($source -match '(?m)^\s*\$articles \+= Get-OpenWorldNewsItems\s*$') {
  throw "The main assembly must not retain an active Get-OpenWorldNewsItems call."
}

if ($source -match "news-api\.ap\.org|apikey=demo") {
  throw "Default news feeds should not include API-gated AP demo endpoints."
}

if ($source -match 'Invoke-WebRequest\s+-Uri\s+\$link') {
  throw "News collection should not fetch each selected RSS article page during candidate collection."
}

if ($workflow -notmatch 'actions/setup-python@v5') {
  throw "The cloud workflow must set up a known Python runtime."
}

if ($workflow -notmatch 'python -m pip install pypdf==6\.10\.2') {
  throw "The cloud workflow must install the pinned PDF extraction dependency."
}

if ($workflow -notmatch 'GITHUB_TOKEN:\s*\$\{\{\s*secrets\.GITHUB_TOKEN\s*\}\}') {
  throw "The update step must pass the GitHub Actions token to the collector."
}

if ($workflow -notmatch 'permissions:\s+contents:\s+write\s+models:\s+read') {
  throw "The workflow must grant read access to GitHub Models for keyless DeepSeek fallback."
}

if ($workflow -notmatch '\$maxAttempts\s*=\s*2') {
  throw "The cloud update must retry once after a transient collection failure."
}

if ($workflow -notmatch 'cron:\s*"7 15,16,17 \* \* \*"') {
  throw "Workflow must cover 08:07 and 09:07 in both PDT and PST."
}

if ($workflow -notmatch 'force:\s+description:') {
  throw "Manual runs must expose an explicit force input."
}

if ($workflow -match 'Archive for \$laDate already exists') {
  throw "Workflow must not treat file existence as update success."
}

if ($workflow -notmatch 'uses:\s*actions/checkout@v4\s+with:\s+ref:\s*main') {
  throw "Queued runs must check out the latest main branch before evaluating the daily archive gate."
}

if ($source -notmatch 'Authorization\s*=\s*"Bearer \$env:GITHUB_TOKEN"') {
  throw "GitHub API requests must use the Actions token when it is available."
}

if ($source -notmatch 'Invoke-WithRetry\s+-Operation\s+\{\s*Invoke-WebRequest\s+-Uri\s+\$Url') {
  throw "PDF downloads must use the request-level retry helper."
}

if ($source -notmatch 'function Get-LosAngelesDate') {
  throw "The issue date must be derived explicitly from the Los Angeles timezone."
}

if ($source -notmatch 'Assert-DailyPayload') {
  throw "Generated data must be validated before replacing the published JSON files."
}

if ($source -notmatch 'Read-ArticleLedger' -or $source -notmatch 'Select-UniqueArticleCandidates') {
  throw "Daily selection must exclude historically used and same-topic candidates before ranking."
}

if ($source -notmatch 'https://models\.github\.ai/inference/chat/completions' -or $source -notmatch 'deepseek/deepseek-v3-0324') {
  throw "Missing DeepSeek keys must fall back to DeepSeek V3 through GitHub Models."
}

if ($source -match '"deepseek-chat"') {
  throw "The deprecated DeepSeek API model name must not remain in the active update script."
}

if ($source -notmatch 'function Invoke-DegradedArticleRecovery' -or $source -notmatch '\$batchSourceLimit\s*=\s*500' -or $source -notmatch 'response_format\s*=\s*@\{\s*type\s*=\s*"json_object"') {
  throw "GitHub Models fallback must batch all items into one token-bounded strict-JSON request."
}

if ($source -notmatch 'foreach\s*\(\$entry\s+in\s+@\(\$uniqueItems') {
  throw "arXiv collection must use a real loop so one unreadable PDF cannot silently exit the whole script."
}

if ($source -notmatch 'function Publish-DailyPayload') {
  throw "Publishing must be centralized behind validation."
}

if ($source -match '\$payload\s*\|\s*ConvertTo-Json\s+-Depth\s+8\s*\|\s*Set-Content\s+-Path\s+\$target') {
  throw "The main flow must not write the live target directly."
}

if ($source -notmatch 'Get-DailyUpdateAction' -or $source -notmatch 'Update-DegradedPayload') {
  throw "The update script must route stale, degraded, and complete daily states."
}

if ($source -notmatch '"summary_upgrade"\s*\{[\s\S]*Get-PaperAnalysisText\s+-FullText') {
  throw "Summary upgrades must reapply the usable full-text gate to downloaded papers."
}

if ($source -notmatch '"title":\s*"A concise, faithful Simplified Chinese display title') {
  throw "DeepSeek analysis must request a Simplified Chinese display title."
}

if ($source -notmatch '"highlight":\s*"One faithful Chinese rendering' -or $source -notmatch '"highlight":\s*"One source-grounded English sentence') {
  throw "DeepSeek analysis must request bilingual source-grounded highlights."
}

if (("$source`n$supportSource") -notmatch '\$item\.highlight\s*=\s*\$analysis\.highlight') {
  throw "Daily article construction and upgrades must propagate highlights."
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
  throw "update-daily.ps1 must parse without errors: $($parseErrors[0].Message)"
}

function Import-ScriptFunction {
  param([string]$Name)

  $definition = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
  }, $true)
  if (-not $definition) {
    throw "Missing required function: $Name"
  }
  return [scriptblock]::Create($definition.Extent.Text)
}

. (Import-ScriptFunction -Name "Get-OpenNewsFeeds")
$savedNewsFeedUrls = $env:NEWS_FEED_URLS
try {
  $env:NEWS_FEED_URLS = "https://example.com/custom-news.xml,/relative-feed.xml,ftp://example.com/feed.xml"
  $newsFeeds = @(Get-OpenNewsFeeds)
} finally {
  $env:NEWS_FEED_URLS = $savedNewsFeedUrls
}
$expectedOfficialFeeds = @(
  "https://www.chinanews.com.cn/rss/china.xml",
  "https://www.chinanews.com.cn/rss/society.xml",
  "https://www.chinanews.com.cn/rss/finance.xml",
  "http://www.xinhuanet.com/politics/news_politics.xml",
  "http://www.xinhuanet.com/finance/news_finance.xml",
  "http://www.people.com.cn/rss/politics.xml",
  "http://www.people.com.cn/rss/society.xml",
  "http://www.chinadaily.com.cn/rss/china_rss.xml",
  "http://www.chinadaily.com.cn/rss/bizchina_rss.xml",
  "https://cs.mfa.gov.cn/gyls/lsgz/lsyj/rss_57447.xml",
  "https://feeds.npr.org/1004/rss.xml",
  "https://www.theguardian.com/world/rss",
  "https://feeds.reuters.com/Reuters/worldNews"
)
foreach ($feed in $newsFeeds) {
  $feedUri = $null
  if (-not $feed.source -or $feed.scope -notin @("domestic", "international") -or -not $feed.language -or
    -not [uri]::TryCreate([string]$feed.url, [System.UriKind]::Absolute, [ref]$feedUri) -or $feedUri.Scheme -notin @("http", "https")) {
    throw "Every open-news feed must declare source, scope, language, and an absolute HTTP(S) URL."
  }
}
foreach ($expectedUrl in $expectedOfficialFeeds) {
  if (@($newsFeeds | Where-Object { $_.url -eq $expectedUrl }).Count -ne 1) {
    throw "Missing official open-news feed: $expectedUrl"
  }
}
$customFeed = @($newsFeeds | Where-Object { $_.url -eq "https://example.com/custom-news.xml" })
if ($customFeed.Count -ne 1 -or $customFeed[0].scope -ne "international" -or $customFeed[0].language -ne "unknown") {
  throw "Custom NEWS_FEED_URLS entries must remain international feeds with unknown language."
}
if ($source -match 'miit\.gov\.cn') {
  throw "The MIIT HTML subscription index must not be configured or scraped."
}

. (Import-ScriptFunction -Name "ConvertFrom-HtmlText")
. (Import-ScriptFunction -Name "Get-FeedText")
. (Import-ScriptFunction -Name "Get-FeedLink")
. (Import-ScriptFunction -Name "Get-FeedItems")
. (Import-ScriptFunction -Name "Invoke-WithRetry")
. (Import-ScriptFunction -Name "Get-OpenNewsCandidates")
$script:ArticleLedger = [pscustomobject]@{ version = 1; urls = @(); titles = @() }
function Select-UniqueArticleCandidates {
  param($Articles, $Ledger)
  return @($Articles)
}
$script:fakeFeed = [pscustomobject]@{
  rss = [pscustomobject]@{
    channel = [pscustomobject]@{
      item = @(
        [pscustomobject]@{ title = "Valid domestic item"; link = "https://example.com/valid"; description = "<p>Retained <b>excerpt</b>.</p>"; pubDate = "Wed, 15 Jul 2026 12:00:00 GMT" },
        [pscustomobject]@{ title = "Invalid date"; link = "https://example.com/bad-date"; description = "Bad date excerpt"; pubDate = "not-a-date" },
        [pscustomobject]@{ title = "Unsafe link"; link = "javascript:alert(1)"; description = "Unsafe"; pubDate = "Wed, 15 Jul 2026 11:00:00 GMT" },
        [pscustomobject]@{ title = "Relative link"; link = "/relative/story"; description = "Relative"; pubDate = "Wed, 15 Jul 2026 10:00:00 GMT" }
      )
    }
  }
}
function Invoke-RestMethod {
  param([string]$Uri, $Headers, [int]$TimeoutSec)
  $script:capturedFeedUri = $Uri
  $script:capturedFeedHeaders = $Headers
  $script:capturedFeedTimeout = $TimeoutSec
  return $script:fakeFeed
}
$fakeFeedInfo = [pscustomobject]@{ source = "Local official fixture"; url = "https://example.com/feed.xml"; scope = "domestic"; language = "zh" }
$normalizedCandidates = @(Get-OpenNewsCandidates -Feeds @($fakeFeedInfo))
if ($normalizedCandidates.Count -ne 1) {
  throw "Candidate normalization must skip invalid dates and unsafe or nonabsolute URLs."
}
$normalized = $normalizedCandidates[0]
if ($normalized.scope -ne "domestic" -or $normalized.language -ne "zh" -or $normalized.excerpt -notmatch '^Retained excerpt\s*\.$' -or
  $capturedFeedUri -ne $fakeFeedInfo.url -or $capturedFeedHeaders["User-Agent"] -ne "personal-info-library/0.1" -or $capturedFeedTimeout -ne 30) {
  throw "Candidate normalization must retain feed metadata/excerpts and use the bounded existing RSS request settings. Got scope='$($normalized.scope)', language='$($normalized.language)', excerpt='$($normalized.excerpt)', uri='$capturedFeedUri', userAgent='$($capturedFeedHeaders['User-Agent'])', timeout='$capturedFeedTimeout'."
}
$script:fakeFeed.rss.channel.item = @(1..13 | ForEach-Object {
  [pscustomobject]@{
    title = "Bounded item $_"
    link = "https://example.com/bounded/$_"
    description = "Excerpt $_"
    pubDate = "Wed, 15 Jul 2026 12:00:00 GMT"
  }
})
$boundedCandidates = @(Get-OpenNewsCandidates -Feeds @($fakeFeedInfo))
if ($boundedCandidates.Count -ne 12) {
  throw "Open-news collection must read no more than 12 entries per feed."
}

. (Import-ScriptFunction -Name "Get-OpenNewsItems")
$integrationNow = (Get-Date).ToUniversalTime()
function New-IntegrationNewsCandidate {
  param(
    [string]$Id,
    [string]$Title,
    [string]$Source,
    [string]$Scope,
    [int]$AgeHours
  )

  return [pscustomobject]@{
    id = $Id
    title = $Title
    source = $Source
    url = "https://example.com/$Id"
    publishedAt = $integrationNow.AddHours(-$AgeHours).ToString("o")
    sourceText = "Verifiable source excerpt for $Id."
    excerpt = "Verifiable source excerpt for $Id."
    scope = $Scope
    language = "en"
  }
}
$script:testNewsCandidates = @(
  New-IntegrationNewsCandidate -Id "domestic-policy" -Title "Government announces central policy and law package" -Source "Domestic Wire A" -Scope "domestic" -AgeHours 1
  New-IntegrationNewsCandidate -Id "domestic-disaster" -Title "Flood disaster triggers emergency public safety response" -Source "Domestic Wire B" -Scope "domestic" -AgeHours 2
  New-IntegrationNewsCandidate -Id "domestic-science" -Title "Science research delivers a key technology breakthrough" -Source "Domestic Wire C" -Scope "domestic" -AgeHours 3
  New-IntegrationNewsCandidate -Id "international-politics" -Title "Election and government diplomacy update" -Source "International Wire A" -Scope "international" -AgeHours 1
  New-IntegrationNewsCandidate -Id "international-finance" -Title "Global markets and central bank finance update" -Source "International Wire B" -Scope "international" -AgeHours 2
)
function Get-OpenNewsCandidates { return @($script:testNewsCandidates) }
$script:convertedNewsCategories = @()
function ConvertTo-NewsArticle {
  param($Candidate, [string]$Category)
  $script:convertedNewsCategories += $Category
  return [pscustomobject]@{ id = $Candidate.id; category = $Category; url = $Candidate.url; candidateScope = $Candidate.scope }
}
$quotaItems = @(Get-OpenNewsItems)
if ($quotaItems.Count -ne 5 -or @($quotaItems | Where-Object { $_.category -eq "domestic" }).Count -ne 3 -or
  @($quotaItems | Where-Object { $_.category -eq "international" }).Count -ne 2) {
  throw "Real news selectors must return exactly 3 domestic and 2 international articles through Get-OpenNewsItems."
}
if (@($quotaItems.url | Sort-Object -Unique).Count -ne 5) {
  throw "Domestic and international selection must not return the same candidate URL twice."
}
foreach ($quotaItem in $quotaItems) {
  if ($quotaItem.category -ne $quotaItem.candidateScope) {
    throw "News category '$($quotaItem.category)' must be converted only from the matching candidate scope '$($quotaItem.candidateScope)'."
  }
}
$script:testNewsCandidates = @($script:testNewsCandidates | Where-Object { $_.id -ne "domestic-science" })
$script:convertedNewsCategories = @()
$quotaRejected = $false
try {
  Get-OpenNewsItems | Out-Null
} catch {
  $quotaRejected = $_.Exception.Message -match 'domestic.*2.*3' -and $_.Exception.Message -match 'international.*2.*2'
}
if (-not $quotaRejected -or $convertedNewsCategories.Count -ne 0) {
  throw "A news quota shortfall must report both counts and throw before converting any candidate."
}

. (Import-ScriptFunction -Name "ConvertTo-NewsArticle")
function New-ArticleAnalysis {
  param([string]$Category, [string]$Title, [string]$Source, [string]$Url, [string]$SourceText, [string]$ScoreLabel)
  $script:convertedAnalysisCategory = $Category
  return [ordered]@{
    title = "国内新闻转换测试"
    highlight = "来源提供了可核验的国内公共影响事实。"
    summary = "这是基于来源摘录的国内新闻摘要。"
    failureAnalysis = "应继续核验来源证据。"
    summarySource = "source_extract"
    sourceExcerpt = $SourceText
    translations = [ordered]@{
      zh = [ordered]@{ title = "国内新闻转换测试"; highlight = "来源提供了可核验的国内公共影响事实。"; summary = "这是基于来源摘录的国内新闻摘要。"; failureAnalysis = "应继续核验来源证据。" }
      en = [ordered]@{ title = "Domestic news conversion test"; highlight = "The source provides verifiable facts about public impact."; summary = "This domestic-news summary is based on the source excerpt."; failureAnalysis = "The source evidence should be verified further." }
    }
  }
}
$domesticArticle = ConvertTo-NewsArticle -Category "domestic" -Candidate ([pscustomobject]@{
  id = "domestic-conversion"
  title = "国内新闻转换测试"
  source = "Fixture source"
  url = "https://example.com/domestic-conversion"
  publishedAt = "2026-07-15T12:00:00Z"
  excerpt = "Specific public-impact facts from the source feed."
})
if ($convertedAnalysisCategory -ne "domestic" -or $domesticArticle.category -ne "domestic" -or
  -not $domesticArticle.selectionReason -or -not $domesticArticle.translations.zh.title -or -not $domesticArticle.translations.en.title) {
  throw "Domestic conversion must pass the actual category through analysis and return complete fallback translations. Got analysisCategory='$convertedAnalysisCategory', category='$($domesticArticle.category)', reason='$($domesticArticle.selectionReason)', zhTitle='$($domesticArticle.translations.zh.title)', enTitle='$($domesticArticle.translations.en.title)'."
}
$invalidCategoryRejected = $false
try { ConvertTo-NewsArticle -Category "ai" -Candidate $domesticArticle | Out-Null } catch { $invalidCategoryRejected = $true }
if (-not $invalidCategoryRejected) {
  throw "ConvertTo-NewsArticle must reject categories other than domestic or international."
}

. (Import-ScriptFunction -Name "Get-LosAngelesNow")
. (Import-ScriptFunction -Name "Get-LosAngelesDate")

$laDate = Get-LosAngelesDate
if ($laDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
  throw "Get-LosAngelesDate must return YYYY-MM-DD on Windows and Linux."
}

. (Import-ScriptFunction -Name "Invoke-WithRetry")
$attempts = 0
$retryResult = Invoke-WithRetry -DelaySeconds 0 -Operation {
  $script:attempts += 1
  if ($script:attempts -eq 1) { throw "transient" }
  return "ok"
}
if ($retryResult -ne "ok" -or $attempts -ne 2) {
  throw "Invoke-WithRetry must retry a transient failure exactly once."
}

. (Import-ScriptFunction -Name "New-ArticleAnalysis")
. (Import-ScriptFunction -Name "Invoke-DegradedArticleRecovery")
function Invoke-WithRetry {
  param([scriptblock]$Operation, [int]$MaxAttempts = 2, [int]$DelaySeconds = 2)
  return & $Operation
}
function Invoke-JsonPostUtf8 {
  param([string]$Uri, [string]$JsonBody, [hashtable]$Headers)
  $script:capturedAnalysisUri = $Uri
  $script:capturedAnalysisBody = $JsonBody
  return [pscustomobject]@{
    choices = @([pscustomobject]@{
      message = [pscustomobject]@{ content = '{"summary":"","failureAnalysis":""}' }
    })
  }
}
$savedDeepSeekKey = $env:DEEPSEEK_API_KEY
$savedGitHubToken = $env:GITHUB_TOKEN
$env:DEEPSEEK_API_KEY = "test-key"
try {
  $incompleteAnalysis = New-ArticleAnalysis `
    -Category "international" `
    -Title "Specific source title" `
    -Source "Test source" `
    -Url "https://example.com/source" `
    -SourceText "Specific source material explains the event and the people involved." `
    -ScoreLabel "Test"
  if ($incompleteAnalysis.summarySource -ne "source_extract") {
    throw "Incomplete DeepSeek JSON must fall back per item instead of failing the batch later."
  }
  if ($capturedAnalysisBody -notmatch 'deepseek-v4-flash') {
    throw "Primary DeepSeek analysis must use deepseek-v4-flash."
  }
  function Invoke-JsonPostUtf8 {
    param([string]$Uri, [string]$JsonBody, [hashtable]$Headers)
    return [pscustomobject]@{
      choices = @([pscustomobject]@{
        message = [pscustomobject]@{ content = '{"title":"DietrichGebert/ponytail 中文版","highlight":"这是忠于来源且信息具体的一句中文摘录。","summary":"这是中文摘要，用于复现中文比例不足的标题。","failureAnalysis":"这是关键判断。","translations":{"en":{"title":"DietrichGebert/ponytail","highlight":"A concrete source-grounded sentence for this repository.","summary":"This summary reproduces a mixed-language title.","failureAnalysis":"This is the key takeaway."}}}' }
      })
    }
  }
  $mixedTitleAnalysis = New-ArticleAnalysis `
    -Category "ai" `
    -Title "DietrichGebert/ponytail" `
    -Source "GitHub Search" `
    -Url "https://github.com/DietrichGebert/ponytail" `
    -SourceText "GitHub repository with recent public activity and a concrete description." `
    -ScoreLabel "GitHub stars"
  if ($mixedTitleAnalysis.summarySource -ne "source_extract") {
    throw "A mixed title with only token Chinese must be degraded before final payload validation."
  }
  function Invoke-JsonPostUtf8 {
    param([string]$Uri, [string]$JsonBody, [hashtable]$Headers)
    $script:capturedAnalysisUri = $Uri
    $script:capturedAnalysisBody = $JsonBody
    return [pscustomobject]@{
      choices = @([pscustomobject]@{
        message = [pscustomobject]@{ content = '{"items":[{"id":"news-batch","title":"批量生成的中文标题","highlight":"一句忠于来源且足够具体的中文摘录。","summary":"这是批量生成的中文摘要。","failureAnalysis":"这是批量生成的中文判断。","englishTitle":"Batch-generated English title","englishHighlight":"A concrete source-grounded sentence.","englishSummary":"This is the batch-generated English summary.","englishFailureAnalysis":"This is the batch-generated English takeaway."}]}' }
      })
    }
  }
  $env:DEEPSEEK_API_KEY = ""
  $env:GITHUB_TOKEN = "test-github-token"
  $batchArticle = [ordered]@{
    id = "news-batch"
    category = "international"
    title = "Original source title"
    source = "Test source"
    sourceExcerpt = (("A" * 9000) + "TAIL_MARKER_MUST_BE_TRUNCATED")
    highlight = "Source highlight"
    summary = "Source summary"
    failureAnalysis = "Pending"
    summarySource = "source_extract"
    translations = [ordered]@{ zh = [ordered]@{}; en = [ordered]@{} }
  }
  $batchResult = @(Invoke-DegradedArticleRecovery -Articles @($batchArticle))
  if ($capturedAnalysisUri -ne "https://models.github.ai/inference/chat/completions" -or $capturedAnalysisBody -notmatch 'deepseek/deepseek-v3-0324') {
    throw "Batch fallback must call DeepSeek V3 with the built-in GitHub token."
  }
  if ($capturedAnalysisBody -match 'TAIL_MARKER_MUST_BE_TRUNCATED') {
    throw "Batch fallback must truncate each oversized source excerpt before inference."
  }
  if ($batchResult[0].translations.zh.title -ne "批量生成的中文标题" -or $batchResult[0].summarySource -ne "deepseek") {
    throw "Batch fallback must merge complete Chinese analysis into each article."
  }

  function Invoke-JsonPostUtf8 {
    param([string]$Uri, [string]$JsonBody, [hashtable]$Headers)
    $script:capturedAnalysisUri = $Uri
    $script:capturedAnalysisBody = $JsonBody
    return [pscustomobject]@{
      choices = @([pscustomobject]@{
        message = [pscustomobject]@{ content = '{"items":[{"id":"needs-recovery","title":"备用通道补齐的中文标题","highlight":"备用通道补齐了一句忠于来源的中文摘录。","summary":"备用通道补齐了中文摘要。","failureAnalysis":"备用通道补齐了关键判断。","englishTitle":"Recovered English title","englishHighlight":"The backup channel recovered this source-grounded sentence.","englishSummary":"The backup channel recovered the English summary.","englishFailureAnalysis":"The backup channel recovered the key takeaway."}]}' }
      })
    }
  }
  $env:DEEPSEEK_API_KEY = "configured-primary-key"
  $script:capturedAnalysisUri = ""
  $script:capturedAnalysisBody = ""
  $alreadyComplete = [ordered]@{
    id = "already-complete"
    category = "ai"
    title = "Already complete"
    source = "Test source"
    sourceExcerpt = "Already complete source text."
    highlight = "原有高亮"
    summary = "原有摘要"
    failureAnalysis = "原有判断"
    summarySource = "deepseek"
    translations = [ordered]@{
      zh = [ordered]@{ title = "已经完成的中文标题"; highlight = "原有高亮"; summary = "原有摘要"; failureAnalysis = "原有判断" }
      en = [ordered]@{ title = "Already complete"; highlight = "Existing highlight."; summary = "Existing summary."; failureAnalysis = "Existing takeaway." }
    }
  }
  $needsRecovery = [ordered]@{
    id = "needs-recovery"
    category = "ai"
    title = "Source title requiring recovery"
    source = "Test source"
    sourceExcerpt = "Specific source text for the degraded item."
    highlight = "Specific source text for the degraded item."
    summary = "Specific source text for the degraded item."
    failureAnalysis = "Pending backup analysis."
    summarySource = "source_extract"
    translations = [ordered]@{
      zh = [ordered]@{ title = ""; highlight = ""; summary = ""; failureAnalysis = "" }
      en = [ordered]@{ title = "Source title requiring recovery"; highlight = "Source highlight."; summary = "Source summary."; failureAnalysis = "Pending." }
    }
  }
  $recoveredBatch = @(Invoke-DegradedArticleRecovery -Articles @($alreadyComplete, $needsRecovery))
  if ($recoveredBatch[1].translations.zh.title -ne "备用通道补齐的中文标题" -or $recoveredBatch[1].summarySource -ne "deepseek") {
    throw "A per-item DeepSeek degradation must be recovered through a bounded backup batch."
  }
  if ($capturedAnalysisUri -ne "https://api.deepseek.com/chat/completions" -or $capturedAnalysisBody -notmatch 'deepseek-v4-flash') {
    throw "Configured DeepSeek credentials must route degraded recovery through DeepSeek instead of rate-limited GitHub Models."
  }
  if ($recoveredBatch[0].translations.zh.title -ne "已经完成的中文标题" -or $capturedAnalysisBody -match 'already-complete') {
    throw "Backup recovery must leave already-complete articles unchanged and out of the recovery prompt."
  }
} finally {
  $env:DEEPSEEK_API_KEY = $savedDeepSeekKey
  $env:GITHUB_TOKEN = $savedGitHubToken
}

. (Import-ScriptFunction -Name "Get-AiItems")
$script:ArticleLedger = [pscustomobject]@{ version = 1; urls = @(); titles = @() }
$script:testAiCandidatePool = @(
  [ordered]@{
    id = "degraded-application"
    category = "ai"
    title = "Autonomous workflow deployment platform"
    source = "Test"
    url = "https://example.com/degraded-application"
    publishedAt = "2026-07-14T18:00:00Z"
    aiArticleType = "application_innovation"
    aiSelectionScore = 500
  },
  [ordered]@{
    id = "valid-concept"
    category = "ai"
    title = "Context engineering for reliable agents"
    source = "Test"
    url = "https://example.com/valid-concept"
    publishedAt = "2026-07-14T17:00:00Z"
    aiArticleType = "concept_explanation"
    aiSelectionScore = 400
  },
  [ordered]@{
    id = "valid-application"
    category = "ai"
    title = "Visual inspection assistant for factories"
    source = "Test"
    url = "https://example.com/valid-application"
    publishedAt = "2026-07-14T16:00:00Z"
    aiArticleType = "application_innovation"
    aiSelectionScore = 300
  }
)
function Get-HnAiCandidates { return @($script:testAiCandidatePool) }
function Get-FeedAiCandidates { return @() }
function Get-GitHubAiCandidates { return @() }
function Add-AiArticleAnalysis {
  param($Item)

  if ($Item.id -eq "degraded-application") {
    $Item.summarySource = "source_extract"
    $Item.translations = [ordered]@{ zh = [ordered]@{ title = "" } }
  } else {
    $Item.summarySource = "deepseek"
    $Item.translations = [ordered]@{ zh = [ordered]@{ title = "完整合格的中文人工智能标题" } }
  }
  return $Item
}
$savedCandidateTestKey = $env:DEEPSEEK_API_KEY
try {
  $env:DEEPSEEK_API_KEY = "configured-primary-key"
  $refilledAiItems = @(Get-AiItems -TargetCount 2)
  $refilledIds = @($refilledAiItems | ForEach-Object { [string]$_.id })
  if ($refilledAiItems.Count -ne 2 -or $refilledIds -contains "degraded-application" -or
    $refilledIds -notcontains "valid-concept" -or $refilledIds -notcontains "valid-application") {
    throw "AI selection must skip an incomplete analyzed candidate and refill from the remaining ranked pool."
  }
} finally {
  $env:DEEPSEEK_API_KEY = $savedCandidateTestKey
}

. (Import-ScriptFunction -Name "Assert-DailyPayload")
function New-TestArticle {
  param([string]$Id, [string]$Category)

  $article = [ordered]@{
    id = $Id
    category = $Category
    title = "Title $Id"
    url = "https://example.com/$Id"
    publishedAt = "2026-07-13T12:00:00Z"
    summary = "Summary $Id"
    highlight = "来源信息揭示了具体事件与可验证事实。"
    failureAnalysis = "Analysis $Id"
    summarySource = "deepseek"
    sourceExcerpt = "Source-specific material for $Id."
    translations = [ordered]@{
      zh = [ordered]@{
        title = "这是一条完整的中文测试标题"
        highlight = "来源信息揭示了具体事件与可验证事实。"
        summary = "中文摘要 $Id"
        failureAnalysis = "中文判断 $Id"
      }
      en = [ordered]@{
        title = "English $Id"
        highlight = "A source-grounded sentence captures the verifiable event clearly."
        summary = "English summary $Id"
        failureAnalysis = "English analysis $Id"
      }
    }
  }

  if ($Category -eq "paper") {
    $article.abstractUrl = "https://example.com/abstract/$Id"
    $article.readabilityStatus = "open"
    $article.paperCard = [ordered]@{
      problem = "Problem"
      method = "Method"
      difference = "Difference"
      innovation = "Innovation"
      implementation = "Implementation"
      applications = "Applications"
      technicalTerms = @("Term")
    }
    $article.translations.en.paperCard = $article.paperCard
    $article.translations.zh.paperCard = $article.paperCard
  }

  return $article
}

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
$validPayload = [ordered]@{
  issueDate = $laDate
  updateStatus = "complete"
  contentFingerprint = Get-ContentFingerprint -Articles $validArticles
  articles = $validArticles
}
Assert-DailyPayload -Payload $validPayload

function Assert-DailyPayloadRejected {
  param($Payload, [string]$Message, [string]$ExpectedMessagePattern = "")

  $rejected = $false
  $actualMessage = ""
  try {
    Assert-DailyPayload -Payload $Payload
  } catch {
    $rejected = $true
    $actualMessage = $_.Exception.Message
  }
  if (-not $rejected) {
    throw $Message
  }
  if ($ExpectedMessagePattern -and $actualMessage -notmatch $ExpectedMessagePattern) {
    throw "$Message Expected an error matching '$ExpectedMessagePattern', got '$actualMessage'."
  }
}

$eightArticles = @($validPayload.articles | Select-Object -First 8)
$eightPayload = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$eightPayload.articles = $eightArticles
$eightPayload.contentFingerprint = Get-ContentFingerprint -Articles $eightArticles
Assert-DailyPayloadRejected -Payload $eightPayload -Message "Daily payloads must reject a total of eight articles." -ExpectedMessagePattern 'exactly 9 articles; collected 8'

$tenPayload = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$extraArticle = New-TestArticle -Id "ai-3" -Category "ai"
$tenPayload.articles = @($tenPayload.articles) + @($extraArticle)
$tenPayload.contentFingerprint = Get-ContentFingerprint -Articles $tenPayload.articles
Assert-DailyPayloadRejected -Payload $tenPayload -Message "Daily payloads must reject a total of ten articles." -ExpectedMessagePattern 'exactly 9 articles; collected 10'

$wrongDomestic = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$wrongDomestic.articles[0].category = "international"
$wrongDomestic.contentFingerprint = Get-ContentFingerprint -Articles $wrongDomestic.articles
Assert-DailyPayloadRejected -Payload $wrongDomestic -Message "Daily payloads must reject a domestic count other than three." -ExpectedMessagePattern 'exactly 3 domestic and 2 international.*collected 2 domestic and 3 international'

$wrongInternational = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$wrongInternational.articles[3].category = "ai"
$wrongInternational.contentFingerprint = Get-ContentFingerprint -Articles $wrongInternational.articles
Assert-DailyPayloadRejected -Payload $wrongInternational -Message "Daily payloads must reject an international count other than two." -ExpectedMessagePattern 'exactly 3 domestic and 2 international.*collected 3 domestic and 1 international'

$wrongReading = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$wrongReading.articles[5].category = "other"
$wrongReading.contentFingerprint = Get-ContentFingerprint -Articles $wrongReading.articles
Assert-DailyPayloadRejected -Payload $wrongReading -Message "Daily payloads must reject a reading count other than four." -ExpectedMessagePattern 'exactly 4 AI/paper articles.*collected 1 AI and 2 papers'

$unsupportedCategory = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$unsupportedCategory.articles[8].category = "unsupported"
$unsupportedCategory.contentFingerprint = Get-ContentFingerprint -Articles $unsupportedCategory.articles
Assert-DailyPayloadRejected -Payload $unsupportedCategory -Message "Daily payloads must reject unsupported categories."

$missingChinese = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$missingChinese.articles[0].translations.PSObject.Properties.Remove("zh")
$rejected = $false
try {
  Assert-DailyPayload -Payload $missingChinese
} catch {
  $rejected = $true
}
if (-not $rejected) {
  throw "Published payloads must reject missing Simplified Chinese translations."
}

$englishChineseTitle = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$englishChineseTitle.articles[0].translations.zh.title = "English title only"
$rejected = $false
try {
  Assert-DailyPayload -Payload $englishChineseTitle
} catch {
  $rejected = $true
}
if (-not $rejected) {
  throw "Chinese-mode titles must reject fully English titles."
}

$mostlyEnglishChineseTitle = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mostlyEnglishChineseTitle.articles[0].translations.zh.title = "English title only 中文"
$rejected = $false
try {
  Assert-DailyPayload -Payload $mostlyEnglishChineseTitle
} catch {
  $rejected = $true
}
if (-not $rejected) {
  throw "Chinese-mode titles must be predominantly Chinese, not merely contain one Chinese token."
}

$missingHighlight = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$missingHighlight.articles[0].highlight = ""
$rejected = $false
try {
  Assert-DailyPayload -Payload $missingHighlight
} catch {
  $rejected = $true
}
if (-not $rejected) {
  throw "Published payloads must reject empty highlights."
}

$templateHighlight = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$templateHighlight.articles[0].highlight = "文章指出，来源中存在一项具体变化。"
$rejected = $false
try {
  Assert-DailyPayload -Payload $templateHighlight
} catch {
  $rejected = $true
}
if (-not $rejected) {
  throw "Published payloads must reject template-style highlight openings."
}

$placeholderPayload = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$placeholderPayload.articles[5].summary = "智能总结需要 DeepSeek key 和完整内容输入后生成。"
$rejected = $false
try {
  Assert-DailyPayload -Payload $placeholderPayload
} catch {
  $rejected = $true
}
if (-not $rejected) {
  throw "Published payloads must reject legacy fallback text."
}

$wrongFingerprint = $validPayload | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$wrongFingerprint.contentFingerprint = "deadbeef"
$rejected = $false
try {
  Assert-DailyPayload -Payload $wrongFingerprint
} catch {
  $rejected = $true
}
if (-not $rejected) {
  throw "Published payloads must reject an incorrect fingerprint."
}

. (Import-ScriptFunction -Name "Publish-DailyPayload")
$invalidOutput = "data/invalid-publish-probe.json"
if (Test-Path $invalidOutput) { Remove-Item -LiteralPath $invalidOutput -Force }
$rejected = $false
try {
  Publish-DailyPayload -Payload $wrongFingerprint -OutputPath $invalidOutput
} catch {
  $rejected = $true
}
if (-not $rejected -or (Test-Path $invalidOutput)) {
  throw "Invalid payloads must fail before the live target is written."
}

$invalidArticles = @(($validArticles | ConvertTo-Json -Depth 8 | ConvertFrom-Json))
$invalidArticles[0].summary = ""
$rejected = $false
try {
  Assert-DailyPayload -Payload ([ordered]@{ issueDate = $laDate; articles = $invalidArticles })
} catch {
  $rejected = $true
}
if (-not $rejected) {
  throw "Payload validation must reject articles with empty summaries."
}

$missingDateArticles = @(($validArticles | ConvertTo-Json -Depth 8 | ConvertFrom-Json))
$missingDateArticles[0].publishedAt = ""
$rejected = $false
try {
  Assert-DailyPayload -Payload ([ordered]@{ issueDate = $laDate; articles = $missingDateArticles })
} catch {
  $rejected = $true
}
if (-not $rejected) {
  throw "Payload validation must reject articles without a valid publication date."
}

. (Import-ScriptFunction -Name "Update-ArchiveIndex")
$archiveProbe = Join-Path ([System.IO.Path]::GetTempPath()) "daily-update-archive-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $archiveProbe | Out-Null
try {
  [ordered]@{ issueDate = "2026-07-14"; articles = @() } |
    ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath (Join-Path $archiveProbe "2026-07-14.json") -Encoding UTF8
  [ordered]@{ issueDate = "2026-07-12"; articles = @() } |
    ConvertTo-Json -Depth 3 |
    Set-Content -LiteralPath (Join-Path $archiveProbe "2026-07-13.json") -Encoding UTF8

  Update-ArchiveIndex -ArchiveFolder $archiveProbe
  $archiveIndex = Get-Content -Raw -Encoding UTF8 (Join-Path $archiveProbe "index.json") | ConvertFrom-Json
  if ($archiveIndex.archives.Count -ne 1 -or $archiveIndex.archives[0].date -ne "2026-07-14") {
    throw "Archive index must exclude payloads whose issue date does not match the archive filename."
  }
} finally {
  Remove-Item -LiteralPath $archiveProbe -Recurse -Force
}

Write-Host "Daily update rule tests passed."
