function Get-SourceExcerpt {
  param(
    [string]$Text,
    [int]$MaxSentences = 3,
    [int]$MaxCharacters = 1800
  )

  $clean = (($Text -replace '\s+', ' ').Trim())
  if (-not $clean) {
    return ""
  }

  $sentences = @(
    [regex]::Split($clean, '(?<=[.!?。！？])\s+') |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_.Length -ge 24 }
  )
  $excerpt = (@($sentences | Select-Object -First $MaxSentences) -join ' ').Trim()
  if (-not $excerpt) {
    $excerpt = $clean
  }

  return $excerpt.Substring(0, [Math]::Min($MaxCharacters, $excerpt.Length)).Trim()
}

function Get-SourceHighlight {
  param(
    [string]$Text,
    [int]$MaxCharacters = 260
  )

  $clean = (($Text -replace '\s+', ' ').Trim())
  if (-not $clean) {
    return ""
  }

  $sentences = @(
    [regex]::Split($clean, '(?<=[.!?。！？])\s+') |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ }
  )
  for ($index = 0; $index -lt $sentences.Count; $index += 1) {
    $sentence = [string]$sentences[$index]
    if ($sentence -match '^(Home|Menu|Skip|Subscribe|Sign in|Advertisement|Cookie)[.!?:：]?\s*$') {
      continue
    }
    if ($sentence -match '^(Abstract|Summary|Method|Results|Conclusion)\.$' -and $index + 1 -lt $sentences.Count) {
      $sentence = "$sentence $($sentences[$index + 1])"
    }
    if ($sentence.Length -ge 24) {
      return $sentence.Substring(0, [Math]::Min($MaxCharacters, $sentence.Length)).Trim()
    }
  }

  return $clean.Substring(0, [Math]::Min($MaxCharacters, $clean.Length)).Trim()
}

function Test-ForbiddenFallbackText {
  param([string]$Text)

  return [bool]($Text -match 'Local fallback|智能总结需要\s+DeepSeek\s+key|candidate collected automatically')
}

function Test-ForbiddenHighlightOpening {
  param([string]$Text)

  return [bool]($Text -match '^\s*(本文介绍|文章指出|值得阅读|这篇论文提出)')
}

function Test-ChineseDisplayTitle {
  param([string]$Title)

  if ([string]::IsNullOrWhiteSpace($Title)) {
    return $false
  }
  $hanCount = [regex]::Matches($Title, '[\u3400-\u9fff]').Count
  $latinCount = [regex]::Matches($Title, '[A-Za-z]').Count
  return $hanCount -ge 4 -and $hanCount -ge $latinCount
}

function Get-CanonicalArticleUrl {
  param([string]$Url)

  $uri = $null
  if (-not [uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @("http", "https")) {
    return ""
  }

  $trackingNames = @(
    "fbclid", "gclid", "mc_cid", "mc_eid", "ref", "ref_src", "source"
  )
  $queryPairs = @(
    $uri.Query.TrimStart("?").Split("&", [System.StringSplitOptions]::RemoveEmptyEntries) |
      Where-Object {
        $name = [uri]::UnescapeDataString(([string]$_).Split("=", 2)[0]).ToLowerInvariant()
        -not ($name.StartsWith("utm_") -or $trackingNames -contains $name)
      } |
      Sort-Object
  )

  $normalizedHost = $uri.Host.ToLowerInvariant()
  if ($uri.HostNameType -eq [System.UriHostNameType]::IPv6) {
    $normalizedHost = "[$normalizedHost]"
  }
  $authority = "$($uri.Scheme.ToLowerInvariant())://$normalizedHost"
  if (-not $uri.IsDefaultPort) {
    $authority += ":$($uri.Port)"
  }
  $path = $uri.AbsolutePath.TrimEnd("/")
  $query = if ($queryPairs.Count -gt 0) { "?" + ($queryPairs -join "&") } else { "" }
  return "$authority$path$query"
}

function Get-NormalizedArticleTitle {
  param([string]$Title)

  if ([string]::IsNullOrWhiteSpace($Title)) {
    return ""
  }
  return (($Title.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant()) -replace '[^\p{L}\p{N}]', '')
}

function Read-ArticleLedger {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return [pscustomobject][ordered]@{ version = 1; urls = @(); titles = @() }
  }
  $ledger = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
  return [pscustomobject][ordered]@{
    version = if ($ledger.version) { [int]$ledger.version } else { 1 }
    urls = @($ledger.urls | Where-Object { $_ } | Sort-Object -Unique)
    titles = @($ledger.titles | Where-Object { $_ } | Sort-Object -Unique)
  }
}

function Add-ArticlesToLedger {
  param(
    $Ledger,
    [object[]]$Articles
  )

  $urls = @($Ledger.urls)
  $titles = @($Ledger.titles)
  foreach ($article in @($Articles)) {
    $url = Get-CanonicalArticleUrl -Url ([string]$article.url)
    $title = Get-NormalizedArticleTitle -Title ([string]$article.title)
    if ($url) { $urls += $url }
    if ($title) { $titles += $title }
  }

  return [pscustomobject][ordered]@{
    version = if ($Ledger.version) { [int]$Ledger.version } else { 1 }
    urls = @($urls | Where-Object { $_ } | Sort-Object -Unique)
    titles = @($titles | Where-Object { $_ } | Sort-Object -Unique)
  }
}

function Test-ArticleSeen {
  param(
    $Article,
    $Ledger
  )

  $canonicalUrl = Get-CanonicalArticleUrl -Url ([string]$Article.url)
  $normalizedTitle = Get-NormalizedArticleTitle -Title ([string]$Article.title)
  return ($canonicalUrl -and @($Ledger.urls) -contains $canonicalUrl) -or
    ($normalizedTitle -and @($Ledger.titles) -contains $normalizedTitle)
}

function Test-ArticleCandidate {
  param(
    $Article,
    $Ledger
  )

  return -not (Test-ArticleSeen -Article $Article -Ledger $Ledger)
}

function Get-ArticleTitleTokens {
  param([string]$Title)

  $stopWords = @(
    "a", "an", "and", "are", "as", "at", "be", "by", "did", "do", "does", "for", "from", "how", "in", "into", "is", "it", "its", "new", "news", "of", "on", "or", "paper", "study", "that", "the", "this", "title", "to", "up", "was", "what", "when", "where", "which", "who", "why", "with"
  )
  @(
    $Title.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant() -split '[^\p{L}\p{N}]+' |
      Where-Object { $_ -and $_.Length -ge 2 -and $_ -notmatch '^\d+$' -and $stopWords -notcontains $_ } |
      Sort-Object -Unique
  )
}

function Get-ChineseTitleNgrams {
  param([string]$Title, [int]$Size = 2)

  $topicText = $Title.Normalize([Text.NormalizationForm]::FormKC)
  foreach ($boilerplate in @("国务院", "发布", "关于", "重要", "政策", "促进", "加强", "发展", "工作", "通知")) {
    $topicText = $topicText -replace [regex]::Escape($boilerplate), ""
  }
  $han = ([regex]::Matches($topicText, '[\u3400-\u9fff]') |
    ForEach-Object { $_.Value }) -join ''
  if ($han.Length -lt $Size) { return @() }
  return @(0..($han.Length - $Size) |
    ForEach-Object { $han.Substring($_, $Size) } |
    Sort-Object -Unique)
}

function Test-ArticlesSameTopic {
  param(
    $First,
    $Second,
    [double]$Threshold = 0.6
  )

  $firstChinese = @(Get-ChineseTitleNgrams -Title ([string]$First.title))
  $secondChinese = @(Get-ChineseTitleNgrams -Title ([string]$Second.title))
  if ($firstChinese.Count -ge 3 -and $secondChinese.Count -ge 3) {
    $sharedChinese = @($firstChinese | Where-Object { $secondChinese -contains $_ }).Count
    $smallerChineseCount = [Math]::Min($firstChinese.Count, $secondChinese.Count)
    if ($sharedChinese -ge 3 -and ($sharedChinese / $smallerChineseCount) -ge 0.3) {
      return $true
    }
  }

  $firstTokens = @(Get-ArticleTitleTokens -Title ([string]$First.title))
  $secondTokens = @(Get-ArticleTitleTokens -Title ([string]$Second.title))
  $minimumCount = [Math]::Min($firstTokens.Count, $secondTokens.Count)
  if ($minimumCount -lt 3) {
    return $false
  }
  $sharedCount = @($firstTokens | Where-Object { $secondTokens -contains $_ }).Count
  return ($sharedCount / $minimumCount) -ge $Threshold
}

function Assert-ArticleSetUnique {
  param(
    [object[]]$Articles,
    $Ledger = $null
  )

  $seenUrls = @{}
  $seenTitles = @{}
  $accepted = @()
  foreach ($article in @($Articles)) {
    if ($Ledger -and (Test-ArticleSeen -Article $article -Ledger $Ledger)) {
      throw "Article was already published: $($article.title)"
    }
    $url = Get-CanonicalArticleUrl -Url ([string]$article.url)
    $title = Get-NormalizedArticleTitle -Title ([string]$article.title)
    if (-not $url -or -not $title) {
      throw "Article identity is incomplete: $($article.title)"
    }
    if ($seenUrls.ContainsKey($url) -or $seenTitles.ContainsKey($title)) {
      throw "Article URL or title is duplicated: $($article.title)"
    }
    foreach ($previous in $accepted) {
      if (Test-ArticlesSameTopic -First $previous -Second $article) {
        throw "Articles cover the same topic: '$($previous.title)' and '$($article.title)'"
      }
    }
    $seenUrls[$url] = $true
    $seenTitles[$title] = $true
    $accepted += $article
  }
}

function Select-UniqueArticleCandidates {
  param(
    [object[]]$Articles,
    $Ledger = $null,
    [int]$MaxCount = [int]::MaxValue
  )

  $accepted = @()
  foreach ($article in @($Articles)) {
    if ($accepted.Count -ge $MaxCount) {
      break
    }
    try {
      $trial = @($accepted) + @($article)
      Assert-ArticleSetUnique -Articles $trial -Ledger $Ledger
      $accepted += $article
    } catch {
      continue
    }
  }
  return $accepted
}

function New-SourceExtractAnalysis {
  param(
    [string]$Category,
    [string]$Title,
    [string]$SourceText,
    [bool]$RequiresRiskAnalysis = $false
  )

  $excerpt = Get-SourceExcerpt -Text $SourceText
  $highlight = Get-SourceHighlight -Text $SourceText
  if (-not $excerpt) {
    throw "Cannot build a source extract from empty content: $Title"
  }

  return [ordered]@{
    summarySource = 'source_extract'
    sourceExcerpt = $excerpt
    highlight = $highlight
    summary = $excerpt
    failureAnalysis = "当前条目仅提供可追溯原文摘录；待 DeepSeek 恢复后自动补充分析。"
    translations = [ordered]@{
      zh = [ordered]@{
        title = ""
        highlight = $highlight
        summary = $excerpt
        failureAnalysis = "当前条目仅提供可追溯原文摘录；待 DeepSeek 恢复后自动补充分析。"
      }
      en = [ordered]@{
        title = $Title
        highlight = $highlight
        summary = $excerpt
        failureAnalysis = 'This is a traceable source extract pending DeepSeek analysis.'
      }
    }
  }
}

function Get-ContentFingerprint {
  param([object[]]$Articles)

  $urls = @($Articles | ForEach-Object { Get-CanonicalArticleUrl -Url ([string]$_.url) })
  $bytes = [System.Text.Encoding]::UTF8.GetBytes(($urls -join "`n"))
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }
  return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-DailyComposition {
  param([object[]]$Articles)

  $items = @($Articles)
  $domesticCount = @($items | Where-Object { $_.category -eq "domestic" }).Count
  $internationalCount = @($items | Where-Object { $_.category -eq "international" }).Count
  $aiCount = @($items | Where-Object { $_.category -eq "ai" }).Count
  $paperCount = @($items | Where-Object { $_.category -eq "paper" }).Count
  return [pscustomobject][ordered]@{
    total = $items.Count
    domestic = $domesticCount
    international = $internationalCount
    ai = $aiCount
    paper = $paperCount
    reading = $aiCount + $paperCount
    isValid = $items.Count -eq 9 -and
      $domesticCount -eq 3 -and
      $internationalCount -eq 2 -and
      $aiCount -ge 2 -and $aiCount -le 4 -and
      $paperCount -ge 0 -and $paperCount -le 2 -and
      ($aiCount + $paperCount) -eq 4
  }
}

function Get-PublishedArchiveShape {
  param([object[]]$Articles)

  $items = @($Articles)
  $daily = Get-DailyComposition -Articles $items
  $legacyInternational = @($items | Where-Object { $_.category -eq "international" }).Count
  $legacyReading = @($items | Where-Object { $_.category -in @("ai", "paper") }).Count
  $isDomesticEra = $daily.domestic -gt 0
  return [pscustomobject][ordered]@{
    era = if ($isDomesticEra) { "domestic" } else { "legacy" }
    total = $items.Count
    domestic = $daily.domestic
    international = $legacyInternational
    reading = $legacyReading
    isValid = if ($isDomesticEra) {
      $daily.isValid
    } else {
      $items.Count -eq 7 -and $legacyInternational -eq 3 -and $legacyReading -eq 4
    }
  }
}

function Get-DailyUpdateAction {
  param(
    [datetime]$LocalNow,
    $CurrentPayload,
    $TodayArchive,
    $PreviousArchive,
    [bool]$ForceRefresh = $false,
    $Ledger = $null
  )

  if ($ForceRefresh) {
    return "fresh_generation"
  }
  if ($LocalNow.Hour -lt 8) {
    return "before_window"
  }

  $today = $LocalNow.ToString("yyyy-MM-dd")
  if (-not $TodayArchive -or $TodayArchive.issueDate -ne $today) {
    return "fresh_generation"
  }

  $items = @($TodayArchive.articles)
  if ($Ledger -and @($items | Where-Object { Test-ArticleSeen -Article $_ -Ledger $Ledger }).Count -gt 0) {
    return "fresh_generation"
  }
  $composition = Get-DailyComposition -Articles $items
  if (-not $composition.isValid) {
    return "fresh_generation"
  }

  if (-not $TodayArchive.contentFingerprint -or $TodayArchive.contentFingerprint -ne (Get-ContentFingerprint $items)) {
    return "fresh_generation"
  }
  if ($PreviousArchive -and $TodayArchive.contentFingerprint -eq $PreviousArchive.contentFingerprint) {
    return "fresh_generation"
  }

  $currentJson = if ($CurrentPayload) { $CurrentPayload | ConvertTo-Json -Compress -Depth 20 } else { "" }
  $archiveJson = $TodayArchive | ConvertTo-Json -Compress -Depth 20
  if (-not $CurrentPayload -or $currentJson -ne $archiveJson) {
    return "repair_publish"
  }
  if ($TodayArchive.updateStatus -eq "degraded") {
    return "summary_upgrade"
  }
  if ($TodayArchive.updateStatus -eq "complete") {
    return "already_complete"
  }
  return "fresh_generation"
}

function Update-DegradedPayload {
  param(
    $Payload,
    [scriptblock]$AnalyzeItem
  )

  $before = [string]$Payload.contentFingerprint
  foreach ($item in @($Payload.articles | Where-Object { $_.summarySource -eq "source_extract" })) {
    $analysis = & $AnalyzeItem $item
    $item.summary = $analysis.summary
    $item.highlight = $analysis.highlight
    $item.failureAnalysis = $analysis.failureAnalysis
    $item.summarySource = $analysis.summarySource
    $item.sourceExcerpt = $analysis.sourceExcerpt
    if ($analysis.translations.en) {
      $item.translations.en = $analysis.translations.en
    }
    if ($analysis.translations.zh) {
      $item.translations.zh = $analysis.translations.zh
    }
    if ($item.category -eq "paper" -and $analysis.paperCard) {
      $item.paperCard = $analysis.paperCard
      $item.translations.en.paperCard = $analysis.translations.en.paperCard
    }
  }

  $Payload.contentFingerprint = Get-ContentFingerprint $Payload.articles
  if ($Payload.contentFingerprint -ne $before) {
    throw "Summary upgrade changed article selection."
  }
  $Payload.updateStatus = if (@($Payload.articles | Where-Object { $_.summarySource -eq "source_extract" }).Count -gt 0) {
    "degraded"
  } else {
    "complete"
  }
  return $Payload
}
