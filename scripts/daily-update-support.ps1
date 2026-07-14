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
    summary = "DeepSeek 暂不可用，当前为公开原文自动摘录：$excerpt"
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

