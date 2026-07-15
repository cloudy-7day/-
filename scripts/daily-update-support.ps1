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

function Get-DailyUpdateAction {
  param(
    [datetime]$LocalNow,
    $CurrentPayload,
    $TodayArchive,
    $PreviousArchive,
    [bool]$ForceRefresh = $false
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
  $newsCount = @($items | Where-Object { $_.category -eq "international" }).Count
  $readingCount = @($items | Where-Object { $_.category -in @("ai", "paper") }).Count
  if ($items.Count -ne 7 -or $newsCount -ne 3 -or $readingCount -ne 4) {
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
