# life-skills.ps1 — 生活技能(人生基本功)板块:新闻源 + 选稿 + 转换
# 说明:本模块对齐 update-daily.ps1 / news-selection.ps1 / daily-update-support.ps1 的既有约定,
# 请在 update-daily.ps1 顶部 dot-source 本文件,并按 INTEGRATION.md 完成 5 处接入点。
# 兼容 Windows PowerShell 5.1。

$script:LifeSkillsFeeds = @(
  # ---- 已验证 RSS 可用 (2026-08-09 实测) ----
  @{ source = "Lifehacker"; url = "https://lifehacker.com/rss"; scope = "life-skills"; language = "en" },
  @{ source = "The Art of Manliness"; url = "https://www.artofmanliness.com/feed/"; scope = "life-skills"; language = "en" },
  # ---- 待验证(接入后建议逐个 curl 测试,失败会自动跳过) ----
  @{ source = "Lifehack.org"; url = "https://www.lifehack.org/feed"; scope = "life-skills"; language = "en" },
  @{ source = "Mark Manson"; url = "https://markmanson.net/feed"; scope = "life-skills"; language = "en" },
  @{ source = "Ness Labs"; url = "https://nesslabs.com/feed"; scope = "life-skills"; language = "en" },
  @{ source = "Farnam Street"; url = "https://fs.blog/feed/"; scope = "life-skills"; language = "en" },
  @{ source = "The Minimalists"; url = "https://www.theminimalists.com/feed/"; scope = "life-skills"; language = "en" },
  @{ source = "少数派 sspai"; url = "https://sspai.com/feed"; scope = "life-skills"; language = "zh" },
  # ---- 2026-08-11 新增:外刊精选同源英文站(实测 RSS 200 可公开抓取,每日更新)----
  # trusted=$true:来源本身即人工精选,豁免标题关键词门槛(标题文学化,关键词在正文)
  @{ source = "Psyche"; url = "https://psyche.co/feed.rss"; scope = "life-skills"; language = "en"; trusted = $true },
  @{ source = "The Marginalian"; url = "https://www.themarginalian.org/feed/"; scope = "life-skills"; language = "en"; trusted = $true },
  @{ source = "Aeon"; url = "https://aeon.co/feed.rss"; scope = "life-skills"; language = "en"; trusted = $true },
  @{ source = "Scott H Young"; url = "https://www.scotthyoung.com/blog/feed/"; scope = "life-skills"; language = "en"; trusted = $true },
  @{ source = "Barking Up The Wrong Tree"; url = "https://bakadesuyo.com/feed/"; scope = "life-skills"; language = "en"; trusted = $true },
  @{ source = "Gretchen Rubin"; url = "https://gretchenrubin.com/feed"; scope = "life-skills"; language = "en"; trusted = $true }
)

# 生活技能主题关键词(中英),命中越多优先级越高
$script:LifeSkillsKeywordPatterns = @(
  "\b(?:life\s+skills?|adulting|adult\s+skills?)\b|\u751f\u6d3b\u6280\u80fd|\u6210\u5e74\u4eba\u57fa\u672c\u529f",
  "\b(?:budgeting?|personal\s+finance|financial\s+literacy|saving|investing\s+basics)\b|\u7406\u8d22|\u8bb0\u8d26|\u9884\u7b97|\u50a8\u84c4|\u6295\u8d44\u5165\u95e8|\u91cf\u5165\u4e3a\u51fa",
  "\b(?:emotional\s+intelligence|emotional\s+regulation|stress\s+management|mindfulness)\b|\u60c5\u7eea\u7ba1\u7406|\u60c5\u7eea\u8c03\u8282|\u538b\u529b\u7ba1\u7406|\u6b63\u5ff5|\u5185\u8017",
  "\b(?:time\s+management|productivity|habits?|self-discipline|procrastination)\b|\u65f6\u95f4\u7ba1\u7406|\u4e60\u60ef\u517b\u6210|\u81ea\u5f8b|\u62d6\u5ef6|\u6548\u7387",
  "\b(?:cook|cooking|meal\s+prep|laundry|cleaning|declutter|minimalism|organizing?)\b|\u505a\u996d|\u70f9\u996a|\u6d17\u8863|\u6536\u7eb3|\u6574\u7406|\u6781\u7b80|\u65ad\u820d\u79bb",
  "\b(?:first\s+aid|CPR|Heimlich|swimming)\b|\u6025\u6551|\u6d77\u59c6\u7acb\u514b|\u5fc3\u80ba\u590d\u82cf|\u6e38\u6cf3",
  "\b(?:critical\s+thinking|media\s+literacy|scam|problem\s+solving)\b|\u6279\u5224\u6027\u601d\u7ef4|\u5a92\u4f53\u7d20\u517b|\u9632\u8bc8|\u9632\u9a97",
  "\b(?:communication\s+skills?|say\s+no|boundaries?|active\s+listening|negotiation)\b|\u6c9f\u901a\u6280\u5de7|\u8fb9\u754c\u611f|\u804a\u5929|\u5354\u5546",
  "\b(?:self[- ]improvement|self[- ]care|resilience|personal\s+growth)\b|\u81ea\u6211\u63d0\u5347|\u81ea\u6211\u6210\u957f|\u5fc3\u7406\u7d20\u8d28|\u62b1\u8d1f",
  "\b(?:career\s+skills?|soft\s+skills?|professional\s+email|job\s+interview)\b|\u804c\u573a\u8f6f\u6280\u80fd|\u6c42\u804c|\u9762\u8bd5|\u7535\u5b50\u90ae\u4ef6",
  # 休息/精力(2026-08-11 新增,对应"哈佛休息表"类)
  "\b(?:rest|recovery|burnout|energy\s+management|sleep|focus|attention|recharge)\b|\u4f11\u606f|\u7cbe\u529b|\u6062\u590d|\u75b2\u60eb|\u7761\u7720|\u4e13\u6ce8|\u5145\u80fd",
  # 心理/吸引力(对应"人散发吸引力"类)
  "\b(?:psychology|attraction|charisma|presence|confidence|magnetism|personality)\b|\u5fc3\u7406|\u5438\u5f15\u529b|\u9b45\u529b|\u6c14\u573a|\u81ea\u4fe1",
  # 学习/认知(对应"真正的学习从第四遍开始"类)
  "\b(?:learning|memory|study|knowledge|deliberate\s+practice|mastery|curiosity)\b|\u5b66\u4e60|\u8bb0\u5fc6|\u8ba4\u77e5|\u77e5\u8bc6|\u523b\u610f\u7ec3\u4e60|\u7cbe\u901a",
  # 人生阶段/成长(对应"人生始于四十岁"类)
  "\b(?:midlife|aging|second\s+half|purpose|meaning|fulfillment|turning\s+\d{2})\b|\u4e2d\u5e74|\u4eba\u751f\u9636\u6bb5|\u610f\u4e49|\u6ee1\u8db3\u611f",
  # 关系/情感(对应"允许一段关系没有答案"类)
  "\b(?:relationship|love|friendship|intimacy|connection|attachment|loneliness)\b|\u5173\u7cfb|\u7231\u60c5|\u53cb\u8c0a|\u4eb2\u5bc6|\u4f9d\u604b|\u5b64\u72ec"
)

function Test-LifeSkillsTopic {
  param($Candidate)

  if ($null -eq $Candidate) { return $false }
  $text = "$([string]$Candidate.title) $([string]$Candidate.excerpt)"
  foreach ($pattern in $script:LifeSkillsKeywordPatterns) {
    if ($text -match $pattern) { return $true }
  }
  return $false
}

# 生活技能候选时效:7 天窗口(常青内容,不适用新闻的 48h 门槛)
function Test-LifeSkillsCandidateFresh {
  param($Candidate, [datetimeoffset]$Now)

  if ($null -eq $Candidate) { return $false }
  $published = [datetimeoffset]::MinValue
  if (-not [datetimeoffset]::TryParse([string]$Candidate.publishedAt, [ref]$published)) { return $false }
  $age = $Now.ToUniversalTime() - $published.ToUniversalTime()
  return ($age.TotalSeconds -ge 0 -and $age.TotalHours -le 168)
}

function Get-LifeSkillsMatchScore {
  param($Candidate)

  if ($null -eq $Candidate) { return 0 }
  $text = "$([string]$Candidate.title) $([string]$Candidate.excerpt)"
  $score = 0
  foreach ($pattern in $script:LifeSkillsKeywordPatterns) {
    if ($text -match $pattern) { $score += 1 }
  }
  # 标题命中加权
  foreach ($pattern in $script:LifeSkillsKeywordPatterns) {
    if ([string]$Candidate.title -match $pattern) { $score += 2 }
  }
  return $score
}

function Get-LifeSkillsFeeds {
  return @($script:LifeSkillsFeeds)
}

function Get-LifeSkillsCandidates {
  param([object[]]$Feeds = @(Get-LifeSkillsFeeds))

  $candidates = @()
  foreach ($feedInfo in $Feeds) {
    try {
      $feed = Invoke-WithRetry -Operation {
        Invoke-RestMethod -Uri $feedInfo.url -Headers @{ "User-Agent" = "personal-info-library/0.1" } -TimeoutSec 30
      }
      $rank = 0
      foreach ($feedItem in @(Get-FeedItems -Feed $feed | Select-Object -First 15)) {
        $rank += 1
        $title = (Get-FeedText -Value $feedItem.title).Trim()
        $link = (Get-FeedLink -Item $feedItem).Trim()
        $excerpt = Get-FeedItemExcerpt -Item $feedItem
        $dateValue = if ($feedItem.pubDate) {
          $feedItem.pubDate
        } elseif ($feedItem.published) {
          $feedItem.published
        } else {
          $feedItem.updated
        }
        $published = [datetimeoffset]::MinValue
        $uri = $null
        if (-not $title -or -not $excerpt -or
          -not [datetimeoffset]::TryParse((Get-FeedText -Value $dateValue), [ref]$published) -or
          -not [uri]::TryCreate($link, [System.UriKind]::Absolute, [ref]$uri) -or
          $uri.Scheme -notin @("http", "https")) {
          continue
        }

        $candidates += [pscustomobject][ordered]@{
          id = "life-" + ([guid]::NewGuid().ToString("N"))
          title = $title
          source = [string]$feedInfo.source
          url = $uri.AbsoluteUri
          publishedAt = $published.ToUniversalTime().ToString("o")
          excerpt = $excerpt
          sourceText = $excerpt
          scope = [string]$feedInfo.scope
          language = [string]$feedInfo.language
          feedRank = $rank
        }
      }
    } catch {
      Write-Warning "Skipping life-skills feed $($feedInfo.source): $($_.Exception.Message)"
    }
  }

  return @(Select-UniqueArticleCandidates `
    -Articles @($candidates | Sort-Object -Property publishedAt -Descending) `
    -Ledger $script:ArticleLedger)
}

function Select-LifeSkillsCandidates {
  param([object[]]$Candidates, [datetimeoffset]$Now, [int]$TargetCount)

  if ($TargetCount -le 0) { return @() }
  # 生活技能类豁免硬排除(否则 lifestyle/生活方式 关键词会误杀),但仍要求通过主题关键词
  # 时效使用 7 天窗口(生活技能是常青内容,不是 48 小时内的新闻;48h 门槛下真实候选几乎为零)
  # trusted 精选源(Psyche/Aeon/Marginalian 等)标题文学化,关键词藏在正文:
  #   来源本身即人工筛选 → 豁免 Test-LifeSkillsTopic 与匹配分>=2 门槛,仅按时效+去重进入
  $trustedSources = @($script:LifeSkillsFeeds | Where-Object { $_.trusted } | ForEach-Object { [string]$_.source })
  $eligible = @($Candidates | Where-Object {
    [string]$_.scope -eq "life-skills" -and
    (Test-LifeSkillsCandidateFresh -Candidate $_ -Now $Now) -and
    $(
      if ([string]$_.source -in $trustedSources) {
        $true
      } else {
        (Test-LifeSkillsTopic -Candidate $_) -and (Get-LifeSkillsMatchScore -Candidate $_) -ge 2
      }
    )
  } | Sort-Object -Property `
    @{ Expression = { Get-LifeSkillsMatchScore -Candidate $_ }; Descending = $true },
    @{ Expression = { Get-NewsCandidatePublishedTime -Candidate $_ }; Descending = $true })

  $selected = [System.Collections.ArrayList]::new()
  $selectedSources = @{}
  foreach ($candidate in $eligible) {
    if ($selected.Count -ge $TargetCount) { break }
    $sourceKey = ([string]$candidate.source).ToLowerInvariant()
    if (-not $selectedSources.ContainsKey($sourceKey)) {
      [void]$selected.Add($candidate)
      $selectedSources[$sourceKey] = $true
    }
  }
  foreach ($candidate in $eligible) {
    if ($selected.Count -ge $TargetCount) { break }
    if ($selected -contains $candidate) { continue }
    [void]$selected.Add($candidate)
    $selectedSources[([string]$candidate.source).ToLowerInvariant()] = $true
  }
  return @($selected)
}

function ConvertTo-LifeSkillsArticle {
  param($Candidate)

  $scoreLabel = "Life-skills RSS source"
  $selectionReason = "Life-skills match score: $(Get-LifeSkillsMatchScore -Candidate $Candidate)"
  $sourceText = [string]$Candidate.excerpt
  $analysis = New-ArticleAnalysis `
    -Category "life-skills" `
    -Title ([string]$Candidate.title) `
    -Source ([string]$Candidate.source) `
    -Url ([string]$Candidate.url) `
    -SourceText $sourceText `
    -ScoreLabel $scoreLabel

  return [ordered]@{
    id = [string]$Candidate.id
    category = "life-skills"
    title = [string]$Candidate.title
    source = [string]$Candidate.source
    url = [string]$Candidate.url
    publishedAt = [string]$Candidate.publishedAt
    scoreLabel = $scoreLabel
    selectionReason = $selectionReason
    highlight = $analysis.highlight
    summary = $analysis.summary
    failureAnalysis = $analysis.failureAnalysis
    summarySource = $analysis.summarySource
    sourceExcerpt = $analysis.sourceExcerpt
    translations = [ordered]@{
      zh = Get-ChineseTranslationForAnalysis -Category "life-skills" -Analysis $analysis
      en = Get-EnglishTranslationForAnalysis -Category "life-skills" -Analysis $analysis
    }
  }
}

function Get-LifeSkillsItems {
  param([int]$TargetCount = 2)

  $candidates = @(Get-LifeSkillsCandidates)
  $now = (Get-Date).ToUniversalTime()
  $probe = @(Select-LifeSkillsCandidates -Candidates $candidates -Now $now -TargetCount $TargetCount)
  if ($probe.Count -lt 1) {
    Write-Warning "Life-skills quota shortfall: $($probe.Count)/$TargetCount; skipping life-skills block this round."
    return @()
  }
  $selected = @(Select-LifeSkillsCandidates -Candidates $candidates -Now $now -TargetCount $TargetCount)
  $articles = @()
  foreach ($candidate in $selected) {
    try {
      $article = ConvertTo-LifeSkillsArticle -Candidate $candidate
      if (-not (Test-NewsArticleConversionComplete -Article $article -Category "life-skills")) {
        throw "Life-skills conversion returned an incomplete item."
      }
      $articles += $article
    } catch {
      Write-Warning "Skipping life-skills candidate after conversion failure '$($candidate.id)': $($_.Exception.Message)"
    }
  }
  return @($articles)
}
