param(
  [string]$OutputPath = "data/articles.json",
  [bool]$ForceRefresh = $false
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "article-selection.ps1")
. (Join-Path $PSScriptRoot "daily-update-support.ps1")

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

function Get-LosAngelesNow {
  try {
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("America/Los_Angeles")
  } catch [System.TimeZoneNotFoundException] {
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")
  }
  return [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tz)
}

function Get-LosAngelesDate {
  return (Get-LosAngelesNow).ToString("yyyy-MM-dd")
}

function Get-GitHubRequestHeaders {
  $headers = @{
    "User-Agent" = "personal-info-library/0.1"
    "Accept" = "application/vnd.github+json"
    "X-GitHub-Api-Version" = "2022-11-28"
  }

  if ($env:GITHUB_TOKEN) {
    $headers.Authorization = "Bearer $env:GITHUB_TOKEN"
  }

  return $headers
}

function Invoke-WithRetry {
  param(
    [scriptblock]$Operation,
    [int]$MaxAttempts = 2,
    [int]$DelaySeconds = 2
  )

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      return & $Operation
    } catch {
      if ($attempt -eq $MaxAttempts) {
        throw
      }

      Write-Warning "Request attempt $attempt failed: $($_.Exception.Message)"
      if ($DelaySeconds -gt 0) {
        Start-Sleep -Seconds $DelaySeconds
      }
    }
  }
}

function Assert-DailyPayload {
  param($Payload)

  $items = @($Payload.articles)
  $expectedDate = Get-LosAngelesDate
  if ($Payload.issueDate -ne $expectedDate) {
    throw "Daily payload issueDate must be $expectedDate; received $($Payload.issueDate)."
  }

  if ($items.Count -ne 7) {
    throw "Daily payload must contain exactly 7 articles; collected $($items.Count). Existing published data was not replaced."
  }

  $newsCount = @($items | Where-Object { $_.category -eq "international" }).Count
  if ($newsCount -ne 3) {
    throw "Daily payload must contain exactly 3 international news items; collected $newsCount. Existing published data was not replaced."
  }

  $aiCount = @($items | Where-Object { $_.category -eq "ai" }).Count
  $paperCount = @($items | Where-Object { $_.category -eq "paper" }).Count
  if ($aiCount -lt 2 -or $aiCount -gt 4 -or $paperCount -lt 0 -or $paperCount -gt 2 -or ($aiCount + $paperCount) -ne 4) {
    throw "Daily payload must contain 2 AI items plus 0-2 papers, with AI filling any paper shortfall. Collected $aiCount AI and $paperCount papers."
  }

  $allowedCategories = @("international", "ai", "paper")
  $seenIds = @{}
  $seenUrls = @{}
  $paperFields = @("problem", "method", "difference", "innovation", "implementation", "applications")

  if ($Payload.updateStatus -notin @("complete", "degraded")) {
    throw "Daily payload updateStatus must be complete or degraded."
  }

  foreach ($item in $items) {
    if (-not $item.id -or -not $item.title -or -not $item.category -or -not $item.url -or -not $item.publishedAt -or -not $item.summary -or -not $item.failureAnalysis) {
      throw "Every article must include id, title, category, URL, publication date, summary, and analysis. Existing published data was not replaced."
    }

    if ($item.category -notin $allowedCategories) {
      throw "Unsupported article category: $($item.category)"
    }

    if ($item.summarySource -notin @("deepseek", "source_extract")) {
      throw "Every article must declare summarySource: $($item.id)"
    }

    if (Test-ForbiddenFallbackText -Text "$($item.summary) $($item.failureAnalysis)") {
      throw "Forbidden fallback text cannot be published: $($item.id)"
    }

    if ($item.summarySource -eq "source_extract" -and -not $item.sourceExcerpt) {
      throw "Source extracts must include sourceExcerpt: $($item.id)"
    }

    if ($seenIds.ContainsKey([string]$item.id) -or $seenUrls.ContainsKey([string]$item.url)) {
      throw "Article IDs and URLs must be unique: $($item.id)"
    }
    $seenIds[[string]$item.id] = $true
    $seenUrls[[string]$item.url] = $true

    $uri = $null
    if (-not [uri]::TryCreate([string]$item.url, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @("http", "https")) {
      throw "Article URL must use HTTP or HTTPS: $($item.url)"
    }

    $publishedAt = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$item.publishedAt, [ref]$publishedAt)) {
      throw "Article publication date is invalid: $($item.id)"
    }

    $english = $item.translations.en
    if (-not $english -or -not $english.title -or -not $english.summary -or -not $english.failureAnalysis) {
      throw "Every article must include a complete English translation: $($item.id)"
    }

    if ($item.category -eq "paper") {
      if ($item.readabilityStatus -ne "open" -or -not $item.abstractUrl -or -not $item.paperCard -or -not $english.paperCard) {
        throw "Every paper must be openly readable and include abstract and bilingual paper cards: $($item.id)"
      }

      foreach ($field in $paperFields) {
        if (-not $item.paperCard.$field -or -not $english.paperCard.$field) {
          throw "Paper card field '$field' is incomplete: $($item.id)"
        }
      }

      if (@($item.paperCard.technicalTerms).Count -eq 0 -or @($english.paperCard.technicalTerms).Count -eq 0) {
        throw "Paper technical terms are incomplete: $($item.id)"
      }
    }
  }

  $expectedFingerprint = Get-ContentFingerprint -Articles $items
  if ($Payload.contentFingerprint -ne $expectedFingerprint) {
    throw "Daily payload fingerprint does not match its article URLs."
  }

  $hasExtract = @($items | Where-Object { $_.summarySource -eq "source_extract" }).Count -gt 0
  if (($hasExtract -and $Payload.updateStatus -ne "degraded") -or (-not $hasExtract -and $Payload.updateStatus -ne "complete")) {
    throw "updateStatus must agree with article summarySource values."
  }
}

function Invoke-JsonPostUtf8 {
  param(
    [string]$Uri,
    [string]$JsonBody,
    [hashtable]$Headers
  )

  $request = [System.Net.HttpWebRequest]::Create($Uri)
  $request.Method = "POST"
  $request.ContentType = "application/json; charset=utf-8"
  $request.Timeout = 60000
  $request.ReadWriteTimeout = 60000
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

function ConvertFrom-HtmlText {
  param([string]$Value)

  if (-not $Value) {
    return ""
  }

  $text = $Value -replace "<[^>]+>", " "
  $text = [System.Net.WebUtility]::HtmlDecode($text)
  return (($text -replace "\s+", " ").Trim())
}

function Get-PdfTextFromUrl {
  param(
    [string]$Url,
    [int]$MaxCharacters = 18000
  )

  if (-not $Url) { return "" }

  $tempPdf = Join-Path ([System.IO.Path]::GetTempPath()) ("paper-" + [guid]::NewGuid().ToString("N") + ".pdf")
  $tempText = [System.IO.Path]::ChangeExtension($tempPdf, ".txt")

  try {
    Invoke-WithRetry -Operation {
      Invoke-WebRequest -Uri $Url -OutFile $tempPdf -Headers @{ "User-Agent" = "personal-info-library/0.1" } -TimeoutSec 30
    } | Out-Null

    $pdftotext = Get-Command "pdftotext" -ErrorAction SilentlyContinue
    if ($pdftotext) {
      & $pdftotext.Source -layout $tempPdf $tempText | Out-Null
      if (Test-Path $tempText) {
        return ((Get-Content -Encoding UTF8 -LiteralPath $tempText -Raw) -replace "\s+", " ").Trim().Substring(0, [Math]::Min($MaxCharacters, (Get-Content -Encoding UTF8 -LiteralPath $tempText -Raw).Length))
      }
    }

    $python = Get-Command "python" -ErrorAction SilentlyContinue
    $extractor = Join-Path $PSScriptRoot "extract-pdf-text.py"
    if ($python -and (Test-Path $extractor)) {
      $text = & $python.Source $extractor $tempPdf
      $text = (($text -join "`n") -replace "\s+", " ").Trim()
      if ($text) {
        return $text.Substring(0, [Math]::Min($MaxCharacters, $text.Length))
      }
    }
  } catch {
    Write-Warning "Could not extract PDF text from ${Url}: $($_.Exception.Message)"
  } finally {
    if (Test-Path $tempPdf) { Remove-Item -LiteralPath $tempPdf -Force }
    if (Test-Path $tempText) { Remove-Item -LiteralPath $tempText -Force }
  }

  return ""
}

function Get-FeedText {
  param($Value)

  if (-not $Value) {
    return ""
  }

  if ($Value -is [array]) {
    $Value = $Value[0]
  }

  if ($Value.InnerText) {
    return [string]$Value.InnerText
  }

  if ($Value.'#text') {
    return [string]$Value.'#text'
  }

  return [string]$Value
}

function Get-FeedLink {
  param($Item)

  if (-not $Item -or -not $Item.link) {
    return ""
  }

  $link = $Item.link
  if ($link -is [array]) {
    $link = @($link | Where-Object { $_.rel -eq "alternate" })[0]
    if (-not $link) { $link = $Item.link[0] }
  }

  if ($link.href) {
    return [string]$link.href
  }

  return Get-FeedText -Value $link
}

function Get-FeedItems {
  param($Feed)

  if ($Feed -is [array]) {
    return @($Feed)
  }

  if ($Feed.rss -and $Feed.rss.channel -and $Feed.rss.channel.item) {
    return @($Feed.rss.channel.item)
  }

  if ($Feed.channel -and $Feed.channel.item) {
    return @($Feed.channel.item)
  }

  if ($Feed.feed -and $Feed.feed.entry) {
    return @($Feed.feed.entry)
  }

  if ($Feed.entry) {
    return @($Feed.entry)
  }

  return @($Feed)
}

function Get-OpenNewsFeeds {
  $feeds = @(
    @{ source = "NPR World"; url = "https://feeds.npr.org/1004/rss.xml" },
    @{ source = "The Guardian World"; url = "https://www.theguardian.com/world/rss" },
    @{ source = "Reuters World"; url = "https://feeds.reuters.com/Reuters/worldNews" }
  )

  if ($env:NEWS_FEED_URLS) {
    $env:NEWS_FEED_URLS.Split(",") |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ } |
      ForEach-Object {
        $feeds += @{ source = "Custom open feed"; url = $_ }
      }
  }

  return $feeds
}

function Get-AiSourceFeeds {
  $feeds = @(
    @{ source = "Simon Willison"; url = "https://simonwillison.net/atom/everything/" },
    @{ source = "Latent Space"; url = "https://www.latent.space/feed" },
    @{ source = "Chip Huyen"; url = "https://huyenchip.com/feed.xml" },
    @{ source = "Interconnects"; url = "https://www.interconnects.ai/feed" }
  )

  if ($env:AI_FEED_URLS) {
    $env:AI_FEED_URLS.Split(",") |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ } |
      ForEach-Object {
        $feeds += @{ source = "Custom AI feed"; url = $_ }
      }
  }

  return $feeds
}

function New-ArticleAnalysis {
  param(
    [string]$Category,
    [string]$Title,
    [string]$Source,
    [string]$Url,
    [string]$SourceText,
    [string]$ScoreLabel,
    [bool]$RequiresRiskAnalysis = $false
  )

  if (-not $env:DEEPSEEK_API_KEY) {
    return New-SourceExtractAnalysis `
      -Category $Category `
      -Title $Title `
      -SourceText $SourceText `
      -RequiresRiskAnalysis $RequiresRiskAnalysis
  }

  $categoryGuide = switch ($Category) {
    "international" { "This is international news. Give a concise key takeaway. Do not force a failure analysis." }
    "ai" {
      if ($RequiresRiskAnalysis) {
        "This is an AI application/project. Focus on the real problem, deployment path, user value, and business/engineering constraints."
      } else {
        "This is an AI concept explanation. Give a concise concept summary and why it matters. Do not force a failure analysis."
      }
    }
    "paper" { "This is an applied research paper with a public full-text link. Explain it in plain Chinese for a beginner. Focus on problem, method, difference from older methods, innovation, implementation path, and applications." }
    default { "Give a rigorous, restrained, verifiable first read." }
  }

  $translationGuide = if ($Category -eq "paper") {
    @(
      '  "translations": {'
      '    "en": {'
      '      "title": "A concise English title for this paper.",'
      '      "summary": "2-3 English sentences explaining what the paper says and why it is worth reading.",'
      '      "failureAnalysis": "1-2 English sentences with the most important evidence limit or practical constraint.",'
      '      "paperCard": {'
      '        "problem": "Plain English explanation of the problem.",'
      '        "method": "Plain English explanation of the method.",'
      '        "difference": "How it differs from older methods.",'
      '        "innovation": "Where the innovation is.",'
      '        "implementation": "How it is implemented.",'
      '        "applications": "Where it can be applied.",'
      '        "technicalTerms": ["term: plain English explanation"]'
      '      }'
      '    }'
      '  }'
    ) -join "`n"
  } else {
    @(
      '  "translations": {'
      '    "en": {'
      '      "title": "A concise English title for this item.",'
      '      "summary": "2-3 English sentences explaining the item and why it is worth reading.",'
      '      "failureAnalysis": "1-2 English sentences with the key takeaway or practical constraint."'
      '    }'
      '  }'
    ) -join "`n"
  }

  $analysisGuide = if ($Category -eq "paper") {
    @(
      '"failureAnalysis": "1-2 Chinese sentences with the most important evidence limit or practical constraint.",'
      '  "paperCard": {'
      '    "problem": "用通俗中文说明它解决什么问题。",'
      '    "method": "用通俗中文说明它用什么方式解决。",'
      '    "difference": "说明它和之前方法有什么不同。",'
      '    "innovation": "说明创新点在哪里。",'
      '    "implementation": "说明具体怎么实现，保留少量关键技术词并解释。",'
      '    "applications": "说明可以应用到哪些场景。",'
      '    "technicalTerms": ["术语：白话解释"]'
      '  }'
    ) -join "`n"
  } elseif ($RequiresRiskAnalysis) {
    '"failureAnalysis": "2-4 Chinese sentences explaining why this AI project or idea may fail. Focus on demand, cost, validation, distribution, regulation, data, or engineering constraints."'
  } else {
    '"failureAnalysis": "1-2 Chinese sentences with a concise key takeaway. Do not frame it as failure unless the item is an AI application project."'
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
  $analysisGuide,
$translationGuide
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
    $response = Invoke-WithRetry -Operation {
      Invoke-JsonPostUtf8 `
        -Uri "https://api.deepseek.com/chat/completions" `
        -JsonBody $body `
        -Headers @{ Authorization = "Bearer $env:DEEPSEEK_API_KEY" }
    }

    $content = [string]$response.choices[0].message.content
    $content = $content.Trim() -replace "^```json\s*", "" -replace "^```\s*", "" -replace "\s*```$", ""
    $parsed = $content | ConvertFrom-Json
    if (-not $parsed.summary -or -not $parsed.failureAnalysis -or -not $parsed.translations.en.summary -or -not $parsed.translations.en.failureAnalysis) {
      throw "DeepSeek returned incomplete summary JSON."
    }
    if ($Category -eq "paper") {
      $paperFields = @("problem", "method", "difference", "innovation", "implementation", "applications")
      foreach ($field in $paperFields) {
        if (-not $parsed.paperCard.$field -or -not $parsed.translations.en.paperCard.$field) {
          throw "DeepSeek returned an incomplete paper card: $field"
        }
      }
      if (@($parsed.paperCard.technicalTerms).Count -eq 0 -or @($parsed.translations.en.paperCard.technicalTerms).Count -eq 0) {
        throw "DeepSeek returned incomplete paper technical terms."
      }
    }

    $result = [ordered]@{
      summary = [string]$parsed.summary
      failureAnalysis = [string]$parsed.failureAnalysis
      summarySource = "deepseek"
      sourceExcerpt = Get-SourceExcerpt -Text $SourceText
    }
    if ($Category -eq "paper" -and $parsed.paperCard) {
      $result.paperCard = [ordered]@{
        problem = [string]$parsed.paperCard.problem
        method = [string]$parsed.paperCard.method
        difference = [string]$parsed.paperCard.difference
        innovation = [string]$parsed.paperCard.innovation
        implementation = [string]$parsed.paperCard.implementation
        applications = [string]$parsed.paperCard.applications
        technicalTerms = @($parsed.paperCard.technicalTerms | ForEach-Object { [string]$_ })
      }
    }
    if ($parsed.translations -and $parsed.translations.en) {
      $english = [ordered]@{
        summary = [string]$parsed.translations.en.summary
        failureAnalysis = [string]$parsed.translations.en.failureAnalysis
      }
      if ($parsed.translations.en.title) {
        $english.title = [string]$parsed.translations.en.title
      }
      if ($Category -eq "paper" -and $parsed.translations.en.paperCard) {
        $english.paperCard = [ordered]@{
          problem = [string]$parsed.translations.en.paperCard.problem
          method = [string]$parsed.translations.en.paperCard.method
          difference = [string]$parsed.translations.en.paperCard.difference
          innovation = [string]$parsed.translations.en.paperCard.innovation
          implementation = [string]$parsed.translations.en.paperCard.implementation
          applications = [string]$parsed.translations.en.paperCard.applications
          technicalTerms = @($parsed.translations.en.paperCard.technicalTerms | ForEach-Object { [string]$_ })
        }
      }
      $result.translations = [ordered]@{ en = $english }
    }
    return $result
  } catch {
    Write-Warning "DeepSeek analysis failed for '$Title': $($_.Exception.Message)"
    return New-SourceExtractAnalysis `
      -Category $Category `
      -Title $Title `
      -SourceText $SourceText `
      -RequiresRiskAnalysis $RequiresRiskAnalysis
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

  if ((Get-PaperTopic -Title $Title -Text $Text) -eq "out_of_scope") { return 0 }
  return 30
}

function New-PaperItem {
  param(
    [string]$Id,
    [string]$Title,
    [string]$Source,
    [string]$Url,
    [string]$AbstractUrl = '',
    [string]$PublishedAt,
    [string]$SourceText,
    [int]$CitationCount = 0,
    [int]$InfluentialCitationCount = 0,
    [int]$AuthorCount = 0,
    [bool]$HasOpenAccessFullText = $false
  )

  $authorityScore = Get-PaperAuthorityScore -Source $Source
  $typeFitScore = Get-PaperTypeFitScore -Title $Title -Text $SourceText
  $profile = Get-PaperCandidateProfile `
    -Title $Title `
    -Source $Source `
    -SourceText $SourceText `
    -CitationCount $CitationCount `
    -InfluentialCitationCount $InfluentialCitationCount `
    -AuthorCount $AuthorCount `
    -HasOpenAccessFullText $HasOpenAccessFullText

  if (-not $profile.isEligibleForDailyPaper) {
    return $null
  }

  $totalScore = $authorityScore + $typeFitScore + [int]$profile.qualityScore
  $scoreLabel = "Quality $($profile.qualityScore)/100 + topic fit $typeFitScore/30"
  $selectionReason = "Open full-text paper; topic $($profile.paperTopic); quality signal passed; application scenario is clear."

  $analysis = New-ArticleAnalysis `
    -Category "paper" `
    -Title $Title `
    -Source $Source `
    -Url $Url `
    -SourceText $SourceText `
    -ScoreLabel $scoreLabel
  $paperCard = if ($analysis.paperCard) {
    $analysis.paperCard
  } else {
    New-PaperReadingCard `
      -Title $Title `
      -Topic $profile.paperTopic `
      -SourceText $SourceText `
      -SelectionReason $selectionReason
  }
  $englishTranslation = Get-EnglishTranslationForAnalysis `
    -Category "paper" `
    -Title $Title `
    -Analysis $analysis `
    -PaperCard $paperCard
  if (-not $englishTranslation.paperCard) {
    $englishTranslation.paperCard = ConvertTo-EnglishPaperCardFallback -PaperCard $paperCard
  }

  [ordered]@{
    id = $Id
    category = "paper"
    title = $Title
    source = $Source
    url = $Url
    abstractUrl = $AbstractUrl
    publishedAt = $PublishedAt
    scoreLabel = $scoreLabel
    recommendationScore = $totalScore
    selectionReason = $selectionReason
    paperTopic = $profile.paperTopic
    qualityScore = $profile.qualityScore
    readabilityStatus = $profile.readabilityStatus
    paperCard = $paperCard
    summary = $analysis.summary
    failureAnalysis = $analysis.failureAnalysis
    summarySource = $analysis.summarySource
    sourceExcerpt = $analysis.sourceExcerpt
    translations = [ordered]@{
      en = $englishTranslation
    }
  }
}

function Get-OpenWorldNewsItems {
  $candidates = @()
  foreach ($feedInfo in Get-OpenNewsFeeds) {
    try {
      $feed = Invoke-WithRetry -Operation {
        Invoke-RestMethod -Uri $feedInfo.url -Headers @{ "User-Agent" = "personal-info-library/0.1" } -TimeoutSec 30
      }
      $feedItems = Get-FeedItems -Feed $feed
      $rank = 0
      foreach ($feedItem in @($feedItems | Select-Object -First 6)) {
        $rank += 1
        $title = Get-FeedText -Value $feedItem.title
        $link = Get-FeedText -Value $feedItem.link
        $description = ConvertFrom-HtmlText -Value (Get-FeedText -Value $feedItem.description)
        $publishedAt = try {
          ([datetime](Get-FeedText -Value $feedItem.pubDate)).ToUniversalTime().ToString("o")
        } catch {
          (Get-Date).ToUniversalTime().ToString("o")
        }

        if (-not $title -or -not $link) {
          continue
        }

        $sourceText = if ($description) { $description } else { "Open RSS item with title and URL. Full text may depend on the publisher page." }
        $candidates += [pscustomobject][ordered]@{
          id = "news-" + ([guid]::NewGuid().ToString("N"))
          title = $title
          source = [string]$feedInfo.source
          url = [string]$link
          publishedAt = $publishedAt
          sourceText = $sourceText
          feedRank = $rank
        }
      }
    } catch {
      Write-Warning "Skipping feed $($feedInfo.source): $($_.Exception.Message)"
      continue
    }
  }

    $deduped = $candidates |
    Group-Object -Property title |
    ForEach-Object { $_.Group[0] }

  # 每个来源最多选 1 篇，保证来源多样性
  $perSource = $deduped |
    Group-Object -Property source |
    ForEach-Object { $_.Group | Sort-Object -Property publishedAt -Descending | Select-Object -First 1 }

  $finalNews = @($perSource | Sort-Object -Property publishedAt -Descending)
  if ($finalNews.Count -lt 3) {
        $usedUrls = @{}
    foreach ($item in $finalNews) { $usedUrls[$item.url] = $true }
    $remaining = $deduped | Where-Object { -not $usedUrls.ContainsKey($_.url) }
    $finalNews += $remaining | Sort-Object -Property publishedAt -Descending | Select-Object -First (3 - $finalNews.Count)
  }

  $finalNews | Select-Object -First 3 |
    ForEach-Object {
      $scoreLabel = "Open RSS source"
      $sourceText = $_.sourceText
    $analysis = New-ArticleAnalysis `
      -Category "international" `
        -Title ([string]$_.title) `
        -Source ([string]$_.source) `
        -Url ([string]$_.url) `
        -SourceText $sourceText `
      -ScoreLabel $scoreLabel

    [ordered]@{
        id = [string]$_.id
      category = "international"
      title = [string]$_.title
        source = [string]$_.source
        url = [string]$_.url
        publishedAt = [string]$_.publishedAt
      scoreLabel = $scoreLabel
        selectionReason = "Open, non-paywalled RSS candidate; recent item across configured news feeds"
      summary = $analysis.summary
      failureAnalysis = $analysis.failureAnalysis
      summarySource = $analysis.summarySource
      sourceExcerpt = $analysis.sourceExcerpt
      translations = [ordered]@{
        en = Get-EnglishTranslationForAnalysis `
          -Category "international" `
          -Title ([string]$_.title) `
          -Analysis $analysis
      }
    }
  }
}

function New-AiArticleItem {
  param(
    [string]$Id,
    [string]$Title,
    [string]$Source,
    [string]$Url,
    [string]$PublishedAt,
    [string]$SourceText,
    [string]$ScoreLabel,
    [int]$Points = 0,
    [int]$Comments = 0,
    [switch]$PreferConceptExplanation
  )

  $profile = Get-AiCandidateProfile `
    -Title $Title `
    -Url $Url `
    -Source $Source `
    -SourceText $SourceText `
    -PublishedAt $PublishedAt `
    -Points $Points `
    -Comments $Comments `
    -PreferConceptExplanation:$PreferConceptExplanation

  if (-not $profile.isEligibleForAiMainSlot) {
    return $null
  }

  [ordered]@{
    id = $Id
    category = "ai"
    title = $Title
    source = $Source
    url = $Url
    abstractUrl = $AbstractUrl
    publishedAt = $PublishedAt
    scoreLabel = $ScoreLabel
    aiArticleType = $profile.aiArticleType
    evidenceAnchors = $profile.evidenceAnchors
    evidenceLabel = $profile.evidenceLabel
    hasPrimaryAnchor = $profile.hasPrimaryAnchor
    requiresRiskAnalysis = $profile.requiresRiskAnalysis
    selectionReason = "AI source passed freshness and evidence-chain gate: $($profile.evidenceLabel)"
    sourceText = $SourceText
    summary = ""
    failureAnalysis = ""
  }
}

function Add-AiArticleAnalysis {
  param($Item)

  $analysis = New-ArticleAnalysis `
    -Category "ai" `
    -Title ([string]$Item.title) `
    -Source ([string]$Item.source) `
    -Url ([string]$Item.url) `
    -SourceText ([string]$Item.sourceText) `
    -ScoreLabel ([string]$Item.scoreLabel) `
    -RequiresRiskAnalysis ([bool]$Item.requiresRiskAnalysis)

  $Item.summary = $analysis.summary
  $Item.failureAnalysis = $analysis.failureAnalysis
  $Item.summarySource = $analysis.summarySource
  $Item.sourceExcerpt = $analysis.sourceExcerpt
  $Item.translations = [ordered]@{
      en = Get-EnglishTranslationForAnalysis `
        -Category "ai" `
        -Title ([string]$Item.title) `
        -Analysis $analysis
  }
  $Item.Remove("sourceText")
  return $Item
}

function Get-HnAiCandidates {
  $cutoff = [int][double]::Parse((Get-Date).AddDays(-90).ToUniversalTime().Subtract([datetime]"1970-01-01").TotalSeconds)
  $queries = @("AI agent", "LLM tool", "MCP", "Claude Code", "prompt engineering", "RAG", "evals")
  $candidates = @()

  foreach ($query in $queries) {
    $encodedQuery = [uri]::EscapeDataString($query)
    $url = "https://hn.algolia.com/api/v1/search?tags=story&query=$encodedQuery&numericFilters=created_at_i%3E$cutoff&hitsPerPage=25"

    try {
      $hits = (Invoke-WithRetry -Operation { Invoke-RestMethod -Uri $url -TimeoutSec 30 }).hits
      foreach ($hit in $hits) {
        if (-not $hit.url -or $hit.points -lt 40) { continue }
        if ($hit.title -notmatch "Show HN|agent|tool|LLM|AI|Claude|ChatGPT|MCP|workflow|prompt|eval|RAG|automation|deploy|local") { continue }

        $sourceText = "HN candidate with public discussion metrics. Points: $($hit.points). Comments: $($hit.num_comments)."
        $item = New-AiArticleItem `
          -Id ("ai-hn-" + $hit.objectID) `
          -Title ([string]$hit.title) `
          -Source "Hacker News" `
          -Url ([string]$hit.url) `
          -PublishedAt (([datetime]$hit.created_at).ToUniversalTime().ToString("o")) `
          -SourceText $sourceText `
          -ScoreLabel ("$($hit.points) points / $($hit.num_comments) comments") `
          -Points ([int]$hit.points) `
          -Comments ([int]$hit.num_comments)

        if ($item) {
          $item.aiSelectionScore = [int]$hit.points + ([int]$hit.num_comments * 2)
          $candidates += $item
        }
      }
    } catch {
      Write-Warning "Skipping HN AI query $query`: $($_.Exception.Message)"
    }
  }

  $candidates
}

function Get-FeedAiCandidates {
  $candidates = @()
  foreach ($feedInfo in Get-AiSourceFeeds) {
    try {
      $feed = Invoke-WithRetry -Operation {
        Invoke-RestMethod -Uri $feedInfo.url -Headers @{ "User-Agent" = "personal-info-library/0.1" } -TimeoutSec 30
      }
      $feedItems = Get-FeedItems -Feed $feed

      foreach ($feedItem in @($feedItems | Select-Object -First 8)) {
        $title = Get-FeedText -Value $feedItem.title
        $link = Get-FeedLink -Item $feedItem
        $description = ConvertFrom-HtmlText -Value (Get-FeedText -Value $feedItem.summary)
        if (-not $description) {
          $description = ConvertFrom-HtmlText -Value (Get-FeedText -Value $feedItem.description)
        }

        $publishedText = Get-FeedText -Value $feedItem.published
        if (-not $publishedText) { $publishedText = Get-FeedText -Value $feedItem.pubDate }
        $publishedAt = try {
          ([datetime]$publishedText).ToUniversalTime().ToString("o")
        } catch {
          (Get-Date).ToUniversalTime().ToString("o")
        }

        if (-not $title -or -not $link) { continue }
        if ("$title $description" -notmatch "AI|LLM|agent|model|prompt|eval|MCP|RAG|Claude|ChatGPT|automation|workflow") { continue }

        $sourceText = if ($description) { $description } else { "Public AI feed item with title and URL." }
        $item = New-AiArticleItem `
          -Id ("ai-feed-" + ([guid]::NewGuid().ToString("N"))) `
          -Title $title `
          -Source ([string]$feedInfo.source) `
          -Url $link `
          -PublishedAt $publishedAt `
          -SourceText $sourceText `
          -ScoreLabel "Curated engineering feed" `
          -PreferConceptExplanation

        if ($item) {
          $item.aiSelectionScore = if ($item.aiArticleType -eq "application_innovation") { 140 } else { 100 }
          $candidates += $item
        }
      }
    } catch {
      Write-Warning "Skipping AI feed $($feedInfo.source): $($_.Exception.Message)"
    }
  }

  $candidates
}

function Get-GitHubAiCandidates {
  $createdAfter = ([datetime](Get-LosAngelesDate)).AddDays(-90).ToString("yyyy-MM-dd")
  $queries = @(
    "llm agent created:>$createdAfter",
    "mcp ai created:>$createdAfter",
    "prompt engineering created:>$createdAfter",
    "ai workflow created:>$createdAfter"
  )
  $candidates = @()

  foreach ($query in $queries) {
    $encodedQuery = [uri]::EscapeDataString($query)
    $url = "https://api.github.com/search/repositories?q=$encodedQuery&sort=stars&order=desc&per_page=10"

    try {
      $response = Invoke-WithRetry -Operation {
        Invoke-RestMethod -Uri $url -Headers (Get-GitHubRequestHeaders) -TimeoutSec 30
      }

      foreach ($repo in $response.items) {
        if (-not $repo.html_url -or $repo.stargazers_count -lt 50) { continue }

        $sourceText = "GitHub repository with $($repo.stargazers_count) stars and recent public activity. Description: $($repo.description)"
        $item = New-AiArticleItem `
          -Id ("ai-github-" + $repo.id) `
          -Title ([string]$repo.full_name) `
          -Source "GitHub Search" `
          -Url ([string]$repo.html_url) `
          -PublishedAt (([datetime]$repo.created_at).ToUniversalTime().ToString("o")) `
          -SourceText $sourceText `
          -ScoreLabel ("GitHub $($repo.stargazers_count) stars")

        if ($item) {
          $item.aiSelectionScore = [int]$repo.stargazers_count
          $candidates += $item
        }
      }
    } catch {
      Write-Warning "Skipping GitHub AI query $query`: $($_.Exception.Message)"
    }
  }

  $candidates
}

function Get-AiItems {
  param([int]$TargetCount = 2)

  $hnCandidates = @(Get-HnAiCandidates)
  $feedCandidates = @(Get-FeedAiCandidates)
  $githubCandidates = @(Get-GitHubAiCandidates)

  $candidates = @()
  $candidates += $hnCandidates
  $candidates += $feedCandidates
  $candidates += $githubCandidates

  $deduped = $candidates |
    Group-Object -Property { $_["url"] } |
    ForEach-Object { $_.Group[0] }

  $application = $deduped |
    Where-Object { $_["aiArticleType"] -eq "application_innovation" } |
    Sort-Object -Property { [int]$_["aiSelectionScore"] }, { [datetime]$_["publishedAt"] } -Descending |
    Select-Object -First 1

  $applicationUrl = if ($application) { $application["url"] } else { "" }
  $conceptOrSignal = $deduped |
    Where-Object { $_["url"] -ne $applicationUrl -and $_["aiArticleType"] -eq "concept_explanation" } |
    Sort-Object -Property { [int]$_["aiSelectionScore"] }, { [datetime]$_["publishedAt"] } -Descending |
    Select-Object -First 1

  if (-not $conceptOrSignal) {
    $conceptOrSignal = $deduped |
    Where-Object { $_["url"] -ne $applicationUrl } |
    Sort-Object -Property { [int]$_["aiSelectionScore"] }, { [datetime]$_["publishedAt"] } -Descending |
    Select-Object -First 1
  }

  $pickedUrls = @($applicationUrl)
  if ($conceptOrSignal) { $pickedUrls += $conceptOrSignal["url"] }

  $remaining = $deduped |
    Where-Object { $pickedUrls -notcontains $_["url"] } |
    Sort-Object -Property { [int]$_["aiSelectionScore"] }, { [datetime]$_["publishedAt"] } -Descending

  @($application, $conceptOrSignal) + @($remaining) |
    Where-Object { $_ } |
    Select-Object -First $TargetCount |
    ForEach-Object { Add-AiArticleAnalysis -Item $_ }
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
      $response = Invoke-WithRetry -Operation {
        Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "personal-info-library/0.1" } -TimeoutSec 30
      }
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
  $query = "https://export.arxiv.org/api/query?search_query=all:%22applied%20artificial%20intelligence%22%20OR%20all:%22brain-computer%20interface%22%20OR%20all:%22neuromorphic%20chip%22%20OR%20all:%22solid-state%20battery%22&start=0&max_results=12&sortBy=submittedDate&sortOrder=descending"
  try {
    $items = Invoke-WithRetry -Operation { Invoke-RestMethod -Uri $query -TimeoutSec 30 }
    $items | Where-Object {
      $_.title -notmatch "cosmological|Poincare|wave equation|mathematics|theory"
    } | Select-Object -First 4 | ForEach-Object {
      $sourceText = ([string]$_.summary).Trim()
      $arxivId = ([uri]$_.id).Segments[-1]
      $pdfUrl = "https://arxiv.org/pdf/$arxivId.pdf"
      $pdfText = Get-PdfTextFromUrl -Url $pdfUrl
      $analysisText = Get-PaperAnalysisText -FullText $pdfText -Abstract $sourceText
      if (-not $analysisText) { continue }

      $arxivBase = $arxivId -replace "v\d+$", ""
      $abstractUrl = "https://arxiv.org/abs/$arxivBase"
      New-PaperItem `
        -Id ("paper-" + $arxivId.Replace("v1", "")) `
        -Title ([string]$_.title) `
        -Source "arXiv" `
        -Url $pdfUrl `
        -AbstractUrl $abstractUrl `
        -PublishedAt (([datetime]$_.published).ToUniversalTime().ToString("o")) `
        -SourceText $analysisText `
        -AuthorCount (@($_.author).Count) `
        -HasOpenAccessFullText $true
    }
  } catch {
    Write-Warning "Skipping arXiv applied papers: $($_.Exception.Message)"
    return @()
  }
}

function Read-JsonPayload {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  try {
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
  } catch {
    Write-Warning "Could not read JSON payload '$Path': $($_.Exception.Message)"
    return $null
  }
}

function Get-PreviousArchivePayload {
  param(
    [string]$ArchiveFolder,
    [string]$Today
  )

  $file = Get-ChildItem -LiteralPath $ArchiveFolder -Filter "*.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.BaseName -match '^\d{4}-\d{2}-\d{2}$' -and $_.BaseName -lt $Today } |
    Sort-Object -Property BaseName -Descending |
    Select-Object -First 1
  if (-not $file) {
    return $null
  }
  return Read-JsonPayload -Path $file.FullName
}

function Update-ArchiveIndex {
  param([string]$ArchiveFolder)

  $archiveEntries = @()
  Get-ChildItem -LiteralPath $ArchiveFolder -Filter "*.json" |
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
  $indexPath = Join-Path $ArchiveFolder "index.json"
  $indexTemp = "$indexPath.$([guid]::NewGuid().ToString('N')).tmp"
  try {
    $archiveIndex | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $indexTemp -Encoding UTF8
    Move-Item -LiteralPath $indexTemp -Destination $indexPath -Force
  } finally {
    if (Test-Path -LiteralPath $indexTemp) {
      Remove-Item -LiteralPath $indexTemp -Force
    }
  }
}

function Publish-DailyPayload {
  param(
    $Payload,
    [string]$OutputPath = "data/articles.json"
  )

  Assert-DailyPayload -Payload $Payload
  $target = Join-Path (Get-Location) $OutputPath
  $targetFolder = Split-Path $target
  $archiveFolder = Join-Path (Get-Location) "data/archive"
  if (-not (Test-Path -LiteralPath $targetFolder)) {
    New-Item -ItemType Directory -Path $targetFolder | Out-Null
  }
  if (-not (Test-Path -LiteralPath $archiveFolder)) {
    New-Item -ItemType Directory -Path $archiveFolder | Out-Null
  }

  $archiveFile = Join-Path $archiveFolder "$($Payload.issueDate).json"
  $indexFile = Join-Path $archiveFolder "index.json"
  $json = $Payload | ConvertTo-Json -Depth 10
  $suffix = [guid]::NewGuid().ToString('N')
  $targetTemp = "$target.$suffix.tmp"
  $archiveTemp = "$archiveFile.$suffix.tmp"
  $targetBackup = "$target.$suffix.bak"
  $archiveBackup = "$archiveFile.$suffix.bak"
  $indexBackup = "$indexFile.$suffix.bak"
  $targetExisted = Test-Path -LiteralPath $target
  $archiveExisted = Test-Path -LiteralPath $archiveFile
  $indexExisted = Test-Path -LiteralPath $indexFile

  try {
    $json | Set-Content -LiteralPath $targetTemp -Encoding UTF8
    $json | Set-Content -LiteralPath $archiveTemp -Encoding UTF8
    if ($targetExisted) { Copy-Item -LiteralPath $target -Destination $targetBackup -Force }
    if ($archiveExisted) { Copy-Item -LiteralPath $archiveFile -Destination $archiveBackup -Force }
    if ($indexExisted) { Copy-Item -LiteralPath $indexFile -Destination $indexBackup -Force }
    Move-Item -LiteralPath $archiveTemp -Destination $archiveFile -Force
    Move-Item -LiteralPath $targetTemp -Destination $target -Force
    Update-ArchiveIndex -ArchiveFolder $archiveFolder
    & (Join-Path (Get-Location) "scripts/sync-public.ps1")
  } catch {
    if (Test-Path -LiteralPath $archiveBackup) { Copy-Item -LiteralPath $archiveBackup -Destination $archiveFile -Force }
    elseif (-not $archiveExisted -and (Test-Path -LiteralPath $archiveFile)) { Remove-Item -LiteralPath $archiveFile -Force }
    if (Test-Path -LiteralPath $targetBackup) { Copy-Item -LiteralPath $targetBackup -Destination $target -Force }
    elseif (-not $targetExisted -and (Test-Path -LiteralPath $target)) { Remove-Item -LiteralPath $target -Force }
    if (Test-Path -LiteralPath $indexBackup) { Copy-Item -LiteralPath $indexBackup -Destination $indexFile -Force }
    elseif (-not $indexExisted -and (Test-Path -LiteralPath $indexFile)) { Remove-Item -LiteralPath $indexFile -Force }
    try {
      & (Join-Path (Get-Location) "scripts/sync-public.ps1")
    } catch {
      Write-Warning "Could not resynchronize public files after rollback: $($_.Exception.Message)"
    }
    throw
  } finally {
    @($targetTemp, $archiveTemp, $targetBackup, $archiveBackup, $indexBackup) |
      Where-Object { Test-Path -LiteralPath $_ } |
      ForEach-Object { Remove-Item -LiteralPath $_ -Force }
  }
}

function Write-DailyUpdateSummary {
  param(
    [string]$Action,
    $Payload
  )

  $deepSeekCount = @($Payload.articles | Where-Object { $_.summarySource -eq "deepseek" }).Count
  $extractCount = @($Payload.articles | Where-Object { $_.summarySource -eq "source_extract" }).Count
  Write-Host "Update result: date=$($Payload.issueDate) action=$Action articles=$(@($Payload.articles).Count) fingerprint=$($Payload.contentFingerprint) deepseek=$deepSeekCount source_extract=$extractCount status=$($Payload.updateStatus)"
}

$localNow = Get-LosAngelesNow
$today = $localNow.ToString("yyyy-MM-dd")
$targetPath = Join-Path (Get-Location) $OutputPath
$archiveFolder = Join-Path (Get-Location) "data/archive"
$todayArchivePath = Join-Path $archiveFolder "$today.json"
$currentPayload = Read-JsonPayload -Path $targetPath
$todayArchive = Read-JsonPayload -Path $todayArchivePath
$previousArchive = Get-PreviousArchivePayload -ArchiveFolder $archiveFolder -Today $today
$action = Get-DailyUpdateAction `
  -LocalNow $localNow `
  -CurrentPayload $currentPayload `
  -TodayArchive $todayArchive `
  -PreviousArchive $previousArchive `
  -ForceRefresh $ForceRefresh

Write-Host "Los Angeles time: $($localNow.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "DeepSeek API key present: $([bool]$env:DEEPSEEK_API_KEY)"
Write-Host "Daily update action: $action"

switch ($action) {
  "before_window" {
    Write-Host "Before local 08:00; no update attempted."
    exit 0
  }
  "already_complete" {
    Write-DailyUpdateSummary -Action $action -Payload $todayArchive
    exit 0
  }
  "repair_publish" {
    Publish-DailyPayload -Payload $todayArchive -OutputPath $OutputPath
    Write-DailyUpdateSummary -Action $action -Payload $todayArchive
    exit 0
  }
  "summary_upgrade" {
    $payload = Update-DegradedPayload -Payload $todayArchive -AnalyzeItem {
      param($item)

      $sourceText = if ($item.category -eq "paper") {
        $pdfText = Get-PdfTextFromUrl -Url ([string]$item.url)
        Get-PaperAnalysisText -FullText $pdfText -Abstract ""
      } else {
        [string]$item.sourceExcerpt
      }
      if (-not $sourceText) {
        return $item
      }
      $analysis = New-ArticleAnalysis `
        -Category ([string]$item.category) `
        -Title ([string]$item.title) `
        -Source ([string]$item.source) `
        -Url ([string]$item.url) `
        -SourceText $sourceText `
        -ScoreLabel ([string]$item.scoreLabel) `
        -RequiresRiskAnalysis ($item.category -eq "ai")
      if ($analysis.summarySource -eq "source_extract") {
        return $item
      }
      return $analysis
    }
    Assert-DailyPayload -Payload $payload
    Publish-DailyPayload -Payload $payload -OutputPath $OutputPath
    Write-DailyUpdateSummary -Action $action -Payload $payload
    exit 0
  }
  "fresh_generation" { }
  default { throw "Unsupported daily update action: $action" }
}

$articles = @()
$articles += Get-OpenWorldNewsItems
$aiItems = @(Get-AiItems -TargetCount 4)
$articles += $aiItems | Select-Object -First 2
$paperItems = @(Get-ArxivAppliedPapers)
$selectedPapers = @($paperItems |
  Where-Object { $_ } |
  Sort-Object -Property recommendationScore,publishedAt -Descending |
  Select-Object -First 2)
$articles += $selectedPapers

$paperShortfall = 2 - $selectedPapers.Count
if ($paperShortfall -gt 0) {
  $articles += $aiItems | Select-Object -Skip 2 -First $paperShortfall
}

if ($articles.Count -eq 0) {
  throw "No articles were collected; keeping the existing data file unchanged."
}

$updateStatus = if (@($articles | Where-Object { $_.summarySource -eq "source_extract" }).Count -gt 0) {
  "degraded"
} else {
  "complete"
}
$payload = [ordered]@{
  issueDate = Get-LosAngelesDate
  updateStatus = $updateStatus
  contentFingerprint = Get-ContentFingerprint -Articles $articles
  notes = @(
    "Real news view counts are usually not public; this version uses open RSS sources and avoids paywalled links.",
    "Add comma-separated RSS URLs to NEWS_FEED_URLS in .env.local to include TLDR-style newsletters or other readable feeds.",
    "AI items must pass freshness and evidence-chain gates; application items need at least two anchors with one primary anchor.",
    "First-read summaries and AI application risk analysis use DeepSeek only, not GPT; traceable source extracts are used when DeepSeek is unavailable."
  )
  articles = $articles
}

Assert-DailyPayload -Payload $payload
Publish-DailyPayload -Payload $payload -OutputPath $OutputPath
Write-DailyUpdateSummary -Action $action -Payload $payload
