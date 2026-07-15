$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "update-daily.ps1"
$source = Get-Content -Raw -Encoding UTF8 $scriptPath
$supportSource = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot "daily-update-support.ps1")
$workflowPath = Join-Path (Split-Path -Parent $PSScriptRoot) ".github/workflows/daily-update.yml"
$workflow = Get-Content -Raw -Encoding UTF8 $workflowPath
. (Join-Path $PSScriptRoot "daily-update-support.ps1")

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

if ($source -notmatch 'function Invoke-GitHubModelsBatchAnalysis' -or $source -notmatch '\$batchSourceLimit\s*=\s*500' -or $source -notmatch 'response_format\s*=\s*@\{\s*type\s*=\s*"json_object"') {
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
. (Import-ScriptFunction -Name "Invoke-GitHubModelsBatchAnalysis")
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
  $batchResult = @(Invoke-GitHubModelsBatchAnalysis -Articles @($batchArticle))
  if ($capturedAnalysisUri -ne "https://models.github.ai/inference/chat/completions" -or $capturedAnalysisBody -notmatch 'deepseek/deepseek-v3-0324') {
    throw "Batch fallback must call DeepSeek V3 with the built-in GitHub token."
  }
  if ($capturedAnalysisBody -match 'TAIL_MARKER_MUST_BE_TRUNCATED') {
    throw "Batch fallback must truncate each oversized source excerpt before inference."
  }
  if ($batchResult[0].translations.zh.title -ne "批量生成的中文标题" -or $batchResult[0].summarySource -ne "deepseek") {
    throw "Batch fallback must merge complete Chinese analysis into each article."
  }
} finally {
  $env:DEEPSEEK_API_KEY = $savedDeepSeekKey
  $env:GITHUB_TOKEN = $savedGitHubToken
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
  New-TestArticle -Id "news-1" -Category "international"
  New-TestArticle -Id "news-2" -Category "international"
  New-TestArticle -Id "news-3" -Category "international"
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
