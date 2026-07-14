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

function Test-ForbiddenFallbackText {
  param([string]$Text)

  return [bool]($Text -match 'Local fallback|智能总结需要\s+DeepSeek\s+key|candidate collected automatically')
}

function New-SourceExtractAnalysis {
  param(
    [string]$Category,
    [string]$Title,
    [string]$SourceText,
    [bool]$RequiresRiskAnalysis = $false
  )

  $excerpt = Get-SourceExcerpt -Text $SourceText
  if (-not $excerpt) {
    throw "Cannot build a source extract from empty content: $Title"
  }

  return [ordered]@{
    summarySource = 'source_extract'
    sourceExcerpt = $excerpt
    summary = $excerpt
    failureAnalysis = "当前条目仅提供可追溯原文摘录；待 DeepSeek 恢复后自动补充分析。"
    translations = [ordered]@{
      en = [ordered]@{
        title = $Title
        summary = $excerpt
        failureAnalysis = 'This is a traceable source extract pending DeepSeek analysis.'
      }
    }
  }
}

function Get-ContentFingerprint {
  param([object[]]$Articles)

  $urls = @($Articles | ForEach-Object {
    $uri = [uri]([string]$_.url)
    $builder = [System.UriBuilder]::new($uri)
    $builder.Host = $builder.Host.ToLowerInvariant()
    $builder.Scheme = $builder.Scheme.ToLowerInvariant()
    $builder.Path = $builder.Path.TrimEnd('/')
    $builder.Uri.AbsoluteUri
  })
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

  if ($LocalNow.Hour -lt 8) {
    return "before_window"
  }
  if ($ForceRefresh) {
    return "fresh_generation"
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
    $item.failureAnalysis = $analysis.failureAnalysis
    $item.summarySource = $analysis.summarySource
    $item.sourceExcerpt = $analysis.sourceExcerpt
    if ($analysis.translations.en) {
      $item.translations.en = $analysis.translations.en
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
