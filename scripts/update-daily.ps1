param(
  [string]$OutputPath = "data/articles.json"
)

$ErrorActionPreference = "Stop"

function Import-LocalEnv {
  $envPath = Join-Path (Get-Location) ".env.local"
  if (-not (Test-Path $envPath)) {
    return
  }

  Get-Content -Path $envPath -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) {
      return
    }

    $parts = $line.Split("=", 2)
    if ($parts.Count -ne 2) {
      return
    }

    $name = $parts[0].Trim()
    $value = $parts[1].Trim().Trim('"').Trim("'")
    if ($name) {
      Set-Item -Path "Env:$name" -Value $value
    }
  }
}

Import-LocalEnv

function Invoke-JsonPostUtf8 {
  param(
    [string]$Uri,
    [string]$JsonBody,
    [hashtable]$Headers
  )

  $request = [System.Net.HttpWebRequest]::Create($Uri)
  $request.Method = "POST"
  $request.ContentType = "application/json; charset=utf-8"
  foreach ($key in $Headers.Keys) {
    $request.Headers[$key] = $Headers[$key]
  }

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonBody)
  $request.ContentLength = $bytes.Length
  $requestStream = $request.GetRequestStream()
  $requestStream.Write($bytes, 0, $bytes.Length)
  $requestStream.Close()

  try {
    $response = $request.GetResponse()
    $stream = $response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
    $text = $reader.ReadToEnd()
    $reader.Close()
    $response.Close()
    return $text | ConvertFrom-Json
  } catch [System.Net.WebException] {
    if ($_.Exception.Response) {
      $stream = $_.Exception.Response.GetResponseStream()
      $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
      $message = $reader.ReadToEnd()
      $reader.Close()
      throw $message
    }
    throw
  }
}

function New-LocalAnalysis {
  param(
    [string]$Category,
    [string]$SourceText
  )

  switch ($Category) {
    "international" {
      return [ordered]@{
        summary = "Local fallback: news candidate collected automatically. Read the source and judge event, stakeholders, and next variables."
        failureAnalysis = "Local fallback: one news item can amplify short-term emotion. Watch institutions, incentives, and execution before judging."
      }
    }
    "ai" {
      return [ordered]@{
        summary = "Local fallback: AI application candidate collected automatically. Judge the friction it removes, why now, and whether users return."
        failureAnalysis = "Local fallback: the project must prove user value, data access, cost, stability, and integration depth."
      }
    }
    "paper" {
      return [ordered]@{
        summary = $SourceText
        failureAnalysis = "Local fallback: the paper must prove experimental conditions, sample size, hardware cost, regulatory path, and reproducibility."
      }
    }
    default {
      return [ordered]@{
        summary = $SourceText
        failureAnalysis = "Local fallback: verify demand, evidence quality, cost structure, and deployment path."
      }
    }
  }
}

function New-ArticleAnalysis {
  param(
    [string]$Category,
    [string]$Title,
    [string]$Source,
    [string]$Url,
    [string]$SourceText,
    [string]$ScoreLabel
  )

  if (-not $env:DEEPSEEK_API_KEY) {
    return New-LocalAnalysis -Category $Category -SourceText $SourceText
  }

  $categoryGuide = switch ($Category) {
    "international" { "This is international news. Help the reader understand the event, stakeholders, and next variables. Avoid emotional commentary." }
    "ai" { "This is an AI application/project. Focus on the real problem, deployment path, user value, and business/engineering constraints." }
    "paper" { "This is an applied research paper. Focus on practical value, experiment conditions, reproducibility, and the distance from paper to product." }
    default { "Give a rigorous, restrained, verifiable first read." }
  }

  $prompt = @"
You are helping a non-technical boss build technical taste by reading articles.

Respond in Simplified Chinese.
Only use the information below. Do not pretend that you read the full article.

Category: $Category
Title: $Title
Source: $Source
Heat/selection signal: $ScoreLabel
URL: $Url
Known content: $SourceText

$categoryGuide

Return strict JSON only. Do not use Markdown or code fences:
{
  "summary": "2-3 Chinese sentences explaining what this article/paper says and why it is worth reading.",
  "failureAnalysis": "2-4 Chinese sentences explaining why it may fail. Be scientific and focus on demand, cost, validation, distribution, regulation, data, or engineering constraints."
}
"@

  $body = @{
    model = "deepseek-chat"
    messages = @(
      @{ role = "system"; content = "You are a rigorous technical-taste coach. You do not call GPT. Analyze only the provided information. Respond in Simplified Chinese." },
      @{ role = "user"; content = $prompt }
    )
    temperature = 0.2
  } | ConvertTo-Json -Depth 8

  try {
    $response = Invoke-JsonPostUtf8 `
      -Uri "https://api.deepseek.com/chat/completions" `
      -JsonBody $body `
      -Headers @{ Authorization = "Bearer $env:DEEPSEEK_API_KEY" }

    $content = [string]$response.choices[0].message.content
    $content = $content.Trim() -replace "^```json\s*", "" -replace "^```\s*", "" -replace "\s*```$", ""
    $parsed = $content | ConvertFrom-Json

    return [ordered]@{
      summary = [string]$parsed.summary
      failureAnalysis = [string]$parsed.failureAnalysis
    }
  } catch {
    return [ordered]@{
      summary = if ($SourceText) { $SourceText } else { "DeepSeek failed, so only title/source metadata is kept for now." }
      failureAnalysis = "DeepSeek API failed. This system does not call GPT. Check DEEPSEEK_API_KEY, network, or DeepSeek quota."
    }
  }
}

function Get-DateStringFromCrossrefParts {
  param($DateParts)

  if (-not $DateParts -or -not $DateParts.'date-parts') {
    return (Get-Date).ToUniversalTime().ToString("o")
  }

  $parts = $DateParts.'date-parts'[0]
  if ($parts -is [string]) {
    $parts = $parts -split "\s+"
  }
  $year = if ($parts.Count -ge 1) { [int]$parts[0] } else { [int](Get-Date).Year }
  $month = if ($parts.Count -ge 2) { [int]$parts[1] } else { 1 }
  $day = if ($parts.Count -ge 3) { [int]$parts[2] } else { 1 }
  return (Get-Date -Year $year -Month $month -Day $day -Hour 0 -Minute 0 -Second 0).ToUniversalTime().ToString("o")
}

function Get-PaperAuthorityScore {
  param([string]$Source)

  if ($Source -match "^(Nature|Science|Cell)$") { return 70 }
  if ($Source -match "Nature|Science|Cell|NEJM|The Lancet|PNAS") { return 64 }
  if ($Source -match "IEEE|ACM|AAAI|NeurIPS|ICML|ICLR|CVPR|CHI") { return 56 }
  if ($Source -match "arXiv") { return 25 }
  return 35
}

function Get-PaperTypeFitScore {
  param(
    [string]$Title,
    [string]$Text
  )

  $haystack = "$Title $Text".ToLowerInvariant()
  $patterns = @(
    "brain.?computer|bci|neural implant|neuroprosthetic|eeg|brain signal",
    "artificial intelligence|machine learning|large language model|foundation model|ai ",
    "chip|semiconductor|neuromorphic|integrated circuit|transistor|photonic",
    "battery|energy storage|solar cell|hydrogen|fusion|electrolyte",
    "psychology|cognitive|mental health|behavior|behaviour|culture|cultural|social"
  )

  foreach ($pattern in $patterns) {
    if ($haystack -match $pattern) {
      return 30
    }
  }

  return 0
}

function New-PaperItem {
  param(
    [string]$Id,
    [string]$Title,
    [string]$Source,
    [string]$Url,
    [string]$PublishedAt,
    [string]$SourceText
  )

  $authorityScore = Get-PaperAuthorityScore -Source $Source
  $typeFitScore = Get-PaperTypeFitScore -Title $Title -Text $SourceText
  $totalScore = $authorityScore + $typeFitScore
  $scoreLabel = "Authority $authorityScore/70 + type fit $typeFitScore/30"

  $analysis = New-ArticleAnalysis `
    -Category "paper" `
    -Title $Title `
    -Source $Source `
    -Url $Url `
    -SourceText $SourceText `
    -ScoreLabel $scoreLabel

  [ordered]@{
    id = $Id
    category = "paper"
    title = $Title
    source = $Source
    url = $Url
    publishedAt = $PublishedAt
    scoreLabel = $scoreLabel
    recommendationScore = $totalScore
    selectionReason = "Paper score: authority source is weighted 70%, topic fit is weighted 30%"
    summary = $analysis.summary
    failureAnalysis = $analysis.failureAnalysis
  }
}

function Get-NytWorldItems {
  $feed = Invoke-RestMethod -Uri "https://rss.nytimes.com/services/xml/rss/nyt/World.xml"
  $feed | Select-Object -First 3 | ForEach-Object {
    $link = if ($_.link -is [array]) { $_.link[0] } else { $_.link }
    $scoreLabel = "RSS order"
    $analysis = New-ArticleAnalysis `
      -Category "international" `
      -Title ([string]$_.title) `
      -Source "New York Times World RSS" `
      -Url ([string]$link) `
      -SourceText "RSS provides title and URL, but no verifiable real view count." `
      -ScoreLabel $scoreLabel

    [ordered]@{
      id = "news-" + ([guid]::NewGuid().ToString("N"))
      category = "international"
      title = [string]$_.title
      source = "New York Times World RSS"
      url = [string]$link
      publishedAt = ([datetime]$_.pubDate).ToUniversalTime().ToString("o")
      scoreLabel = $scoreLabel
      selectionReason = "High in world-news RSS, used as public heat proxy"
      summary = $analysis.summary
      failureAnalysis = $analysis.failureAnalysis
    }
  }
}

function Get-HnAiItems {
  $cutoff = [int][double]::Parse((Get-Date).AddDays(-15).ToUniversalTime().Subtract([datetime]"1970-01-01").TotalSeconds)
  $url = "https://hn.algolia.com/api/v1/search?tags=story&query=LLM&numericFilters=created_at_i%3C$cutoff&hitsPerPage=20"
  $items = (Invoke-RestMethod -Uri $url).hits |
    Where-Object { $_.url -and $_.points -gt 300 -and $_.title -match "Show HN|local|run|tool|agent|visual|deploy|single file|LLM" } |
    Select-Object -First 2

  $items | ForEach-Object {
    $scoreLabel = "$($_.points) points / $($_.num_comments) comments"
    $analysis = New-ArticleAnalysis `
      -Category "ai" `
      -Title ([string]$_.title) `
      -Source "Hacker News" `
      -Url ([string]$_.url) `
      -SourceText "HN candidate. Public metrics include points and comments; full article fetching is not enabled yet." `
      -ScoreLabel $scoreLabel

    [ordered]@{
      id = "ai-" + $_.objectID
      category = "ai"
      title = [string]$_.title
      source = "Hacker News"
      url = [string]$_.url
      publishedAt = ([datetime]$_.created_at).ToUniversalTime().ToString("o")
      scoreLabel = $scoreLabel
      selectionReason = "Older than 15 days, high HN interaction, application-oriented"
      summary = $analysis.summary
      failureAnalysis = $analysis.failureAnalysis
    }
  }
}

function Get-CrossrefAuthorityPapers {
  $sourceQueries = @(
    @{ source = "Nature Biomedical Engineering"; query = "brain computer interface neural implant" },
    @{ source = "Nature Machine Intelligence"; query = "artificial intelligence application machine learning" },
    @{ source = "Nature Electronics"; query = "semiconductor chip neuromorphic transistor" },
    @{ source = "Nature Energy"; query = "battery energy storage electrolyte" },
    @{ source = "Nature Human Behaviour"; query = "psychology culture behavior cognition" },
    @{ source = "Science"; query = "brain computer interface artificial intelligence chip battery psychology culture" },
    @{ source = "Cell"; query = "brain computer interface artificial intelligence psychology culture" },
    @{ source = "PNAS"; query = "brain computer interface artificial intelligence chip energy psychology culture" }
  )
  $items = @()

  foreach ($pair in $sourceQueries) {
    $encodedQuery = [uri]::EscapeDataString($pair.query)
    $encodedSource = [uri]::EscapeDataString($pair.source)
    $url = "https://api.crossref.org/works?query.container-title=$encodedSource&query.bibliographic=$encodedQuery&filter=from-pub-date:2025-01-01,type:journal-article&rows=5&select=DOI,title,container-title,published-print,published-online,URL,abstract"

    try {
      Start-Sleep -Milliseconds 1200
      $response = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "personal-info-library/0.1" }
      foreach ($work in $response.message.items) {
        $title = if ($work.title -is [array]) { [string]$work.title[0] } else { [string]$work.title }
        $source = if ($work.'container-title' -is [array]) { [string]$work.'container-title'[0] } else { [string]$work.'container-title' }
        if (-not $title -or -not $source) { continue }
        if ($work.DOI -match "10\.1038/d41586" -or $title -match "Daily briefing|News|Editorial|Comment|Correspondence|Career") { continue }

        $authorityScore = Get-PaperAuthorityScore -Source $source
        $typeFitScore = Get-PaperTypeFitScore -Title $title -Text ([string]$work.abstract)
        if (($authorityScore + $typeFitScore) -lt 70) { continue }

        $published = if ($work.'published-online') { $work.'published-online' } else { $work.'published-print' }
        $publishedAt = Get-DateStringFromCrossrefParts -DateParts $published
        $sourceText = if ($work.abstract) { [string]$work.abstract } else { "Crossref record with DOI $($work.DOI). Abstract not available in the index." }

        $items += [ordered]@{
          id = "paper-crossref-" + ($work.DOI -replace "[^a-zA-Z0-9]", "-")
          title = $title
          source = $source
          url = [string]$work.URL
          publishedAt = $publishedAt
          sourceText = $sourceText
          recommendationScore = $authorityScore + $typeFitScore
        }
      }
    } catch {
      continue
    }
  }

  $items |
    Sort-Object -Property recommendationScore,publishedAt -Descending |
    Group-Object -Property title |
    ForEach-Object { $_.Group[0] } |
    Select-Object -First 2 |
    ForEach-Object {
      New-PaperItem `
        -Id $_.id `
        -Title $_.title `
        -Source $_.source `
        -Url $_.url `
        -PublishedAt $_.publishedAt `
        -SourceText $_.sourceText
    }
}

function Get-ArxivAppliedPapers {
  $query = "https://export.arxiv.org/api/query?search_query=all:%22brain-computer%20interface%22%20OR%20all:%22neuromorphic%20chip%22%20OR%20all:%22solid-state%20battery%22&start=0&max_results=12&sortBy=submittedDate&sortOrder=descending"
  $items = Invoke-RestMethod -Uri $query
  $items | Where-Object {
    $_.title -notmatch "cosmological|Poincare|wave equation|mathematics|theory"
  } | Select-Object -First 2 | ForEach-Object {
    $sourceText = ([string]$_.summary).Trim()
    New-PaperItem `
      -Id ("paper-" + ([uri]$_.id).Segments[-1].Replace("v1", "")) `
      -Title ([string]$_.title) `
      -Source "arXiv" `
      -Url ([string]$_.id) `
      -PublishedAt (([datetime]$_.published).ToUniversalTime().ToString("o")) `
      -SourceText $sourceText
  }
}

$articles = @()
$articles += Get-NytWorldItems
$articles += Get-HnAiItems
$paperItems = @(Get-CrossrefAuthorityPapers)
if ($paperItems.Count -lt 2) {
  $paperItems += Get-ArxivAppliedPapers
}
$articles += $paperItems |
  Sort-Object -Property recommendationScore,publishedAt -Descending |
  Select-Object -First 2

$payload = [ordered]@{
  issueDate = (Get-Date).ToString("yyyy-MM-dd")
  notes = @(
    "Real news view counts are usually not public; this version uses RSS order as a heat proxy.",
    "HN provides points and comments; Reddit needs OAuth credentials for stable access.",
    "First-read and failure analysis use DeepSeek only, not GPT; local rules are used only as fallback."
  )
  articles = $articles
}

$target = Join-Path (Get-Location) $OutputPath
$folder = Split-Path $target
if (-not (Test-Path $folder)) {
  New-Item -ItemType Directory -Path $folder | Out-Null
}

$payload | ConvertTo-Json -Depth 8 | Set-Content -Path $target -Encoding UTF8
$archiveFolder = Join-Path (Get-Location) "data/archive"
if (-not (Test-Path $archiveFolder)) {
  New-Item -ItemType Directory -Path $archiveFolder | Out-Null
}

$archiveDate = $payload.issueDate
$archiveFile = Join-Path $archiveFolder "$archiveDate.json"
$payload | ConvertTo-Json -Depth 8 | Set-Content -Path $archiveFile -Encoding UTF8

$archiveEntries = @()
Get-ChildItem -Path $archiveFolder -Filter "*.json" |
  Where-Object { $_.Name -ne "index.json" } |
  Sort-Object -Property BaseName -Descending |
  ForEach-Object {
    $archiveEntries += [ordered]@{
      date = $_.BaseName
      path = "data/archive/$($_.Name)"
    }
  }

$archiveIndex = [ordered]@{
  updatedAt = (Get-Date).ToUniversalTime().ToString("o")
  archives = $archiveEntries
}
$archiveIndex | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $archiveFolder "index.json") -Encoding UTF8
& (Join-Path (Get-Location) "scripts/sync-public.ps1")
Write-Host "Updated $OutputPath with $($articles.Count) articles."
