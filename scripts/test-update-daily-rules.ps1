$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "update-daily.ps1"
$source = Get-Content -Raw -Encoding UTF8 $scriptPath
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

if ($source -notmatch 'function Publish-DailyPayload') {
  throw "Publishing must be centralized behind validation."
}

if ($source -match '\$payload\s*\|\s*ConvertTo-Json\s+-Depth\s+8\s*\|\s*Set-Content\s+-Path\s+\$target') {
  throw "The main flow must not write the live target directly."
}

if ($source -notmatch 'Get-DailyUpdateAction' -or $source -notmatch 'Update-DegradedPayload') {
  throw "The update script must route stale, degraded, and complete daily states."
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
    failureAnalysis = "Analysis $Id"
    summarySource = "deepseek"
    sourceExcerpt = "Source-specific material for $Id."
    translations = [ordered]@{
      en = [ordered]@{
        title = "English $Id"
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

Write-Host "Daily update rule tests passed."
