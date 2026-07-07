function Get-AiEvidenceAnchors {
  param(
    [string]$Title,
    [string]$Url,
    [string]$Source,
    [string]$SourceText,
    [int]$Points = 0,
    [int]$Comments = 0
  )

  $haystack = "$Title $Url $Source $SourceText".ToLowerInvariant()
  $anchors = @()
  $hasCompanySource = $false

  if ($Url -match "github\.com" -or $haystack -match "\bgithub\b|open.?source|repo\b") {
    $anchors += [ordered]@{ label = "GitHub"; kind = "primary" }
  }
  if ($haystack -match "engineering\.|/engineering|company engineering|official blog|openai\.com|anthropic\.com|cloudflare\.com|googleblog\.com|microsoft\.com|vercel\.com|modal\.com") {
    $anchors += [ordered]@{ label = "Company source"; kind = "primary" }
    $hasCompanySource = $true
  }
  if ($haystack -match "\bdemo\b|playground|live preview|try it|prototype") {
    $anchors += [ordered]@{ label = "Demo"; kind = "primary" }
  }
  if ($haystack -match "official docs|documentation|docs\.|api reference|company engineering blog") {
    $anchors += [ordered]@{ label = "Official docs"; kind = "primary" }
  }
  if ($haystack -match "case study|real user|customer|deployed|teams still use") {
    $anchors += [ordered]@{ label = "Case study"; kind = "primary" }
  }
  if ($Source -match "Hacker News" -or $Points -gt 0 -or $Comments -gt 0) {
    $anchors += [ordered]@{ label = "HN discussion"; kind = "secondary" }
  }
  if ($haystack -match "\bstars?\b|community signal|public activity|recent activity") {
    $anchors += [ordered]@{ label = "Community signal"; kind = "secondary" }
  }
  if (-not $hasCompanySource -and $haystack -match "blog|newsletter|deep dive|guide|explains|explainer|analysis") {
    $anchors += [ordered]@{ label = "Expert analysis"; kind = "secondary" }
  }

  $seen = @{}
  $anchors | Where-Object {
    if ($seen.ContainsKey($_.label)) { return $false }
    $seen[$_.label] = $true
    return $true
  }
}

function Get-AiArticleType {
  param(
    [string]$Title,
    [string]$Url,
    [string]$SourceText
  )

  $haystack = "$Title $Url $SourceText".ToLowerInvariant()
  $applicationPattern = "github|demo|launch|ships|tool|agent|workflow|product|app|deploy|api|automation|skill"
  $conceptPattern = "explain|guide|concept|introduction|primer|context engineering|how to think"

  if ($haystack -match $applicationPattern) {
    return "application_innovation"
  }
  if ($haystack -match $conceptPattern) {
    return "concept_explanation"
  }

  return "application_innovation"
}

function Test-AiFreshness {
  param(
    [string]$PublishedAt,
    [bool]$AllowAgeException = $false
  )

  try {
    $published = [datetime]$PublishedAt
  } catch {
    return $false
  }

  $cutoff = (Get-Date).AddDays(-90)
  return ($published -ge $cutoff)
}

function Get-AiCandidateProfile {
  param(
    [string]$Title,
    [string]$Url,
    [string]$Source,
    [string]$SourceText,
    [string]$PublishedAt,
    [int]$Points = 0,
    [int]$Comments = 0,
    [switch]$AllowAgeException,
    [switch]$PreferConceptExplanation
  )

  $articleType = if ($PreferConceptExplanation) {
    "concept_explanation"
  } else {
    Get-AiArticleType -Title $Title -Url $Url -SourceText $SourceText
  }
  $anchors = @(Get-AiEvidenceAnchors -Title $Title -Url $Url -Source $Source -SourceText $SourceText -Points $Points -Comments $Comments)
  $hasPrimaryAnchor = @($anchors | Where-Object { $_.kind -eq "primary" }).Count -gt 0
  $isFreshEnough = Test-AiFreshness -PublishedAt $PublishedAt -AllowAgeException ([bool]$AllowAgeException)
  $passesEvidenceGate = ($articleType -eq "concept_explanation") -or ($anchors.Count -ge 2 -and $hasPrimaryAnchor)

  [ordered]@{
    aiArticleType = $articleType
    evidenceAnchors = $anchors
    evidenceLabel = if ($anchors.Count) { ($anchors | ForEach-Object { $_.label }) -join " + " } else { "No clear evidence" }
    hasPrimaryAnchor = $hasPrimaryAnchor
    isFreshEnough = $isFreshEnough
    isEligibleForAiMainSlot = ($isFreshEnough -and $passesEvidenceGate)
    requiresRiskAnalysis = ($articleType -eq "application_innovation")
  }
}

function Get-PaperTopic {
  param(
    [string]$Title,
    [string]$Text
  )

  $haystack = "$Title $Text".ToLowerInvariant()
  if ($haystack -match "brain.?computer|bci|neural implant|neuroprosthetic|eeg|brain signal|motor imagery|imagined speech") {
    return "brain_computer_interface"
  }
  if ($haystack -match "artificial intelligence|machine learning|large language model|foundation model|ai |deep learning|agent") {
    return "ai"
  }
  if ($haystack -match "chip|semiconductor|neuromorphic|integrated circuit|transistor|photonic|processor") {
    return "chip"
  }
  if ($haystack -match "battery|energy storage|solar cell|hydrogen|fusion|electrolyte|grid") {
    return "energy"
  }

  return "out_of_scope"
}

function Test-PaperApplicationSignal {
  param(
    [string]$Title,
    [string]$Text
  )

  $haystack = "$Title $Text".ToLowerInvariant()
  return ($haystack -match "application|applied|clinical|device|system|benchmark|accuracy|deployment|users?|control|decoding|diagnosis|manufacturing|storage|assistive|communication|prototype|experiment|method")
}

function Get-PaperQualityScore {
  param(
    [string]$Source,
    [int]$CitationCount = 0,
    [int]$InfluentialCitationCount = 0,
    [int]$AuthorCount = 0
  )

  $sourceScore = 10
  if ($Source -match "Nature|Science|Cell|PNAS") { $sourceScore = 40 }
  elseif ($Source -match "IEEE|ACM|AAAI|NeurIPS|ICML|ICLR|CVPR|CHI") { $sourceScore = 30 }
  elseif ($Source -match "arXiv") { $sourceScore = 18 }

  $citationScore = [Math]::Min(25, [Math]::Floor($CitationCount / 5))
  $influentialScore = [Math]::Min(25, $InfluentialCitationCount * 2)
  $authorScore = if ($AuthorCount -ge 3) { 10 } elseif ($AuthorCount -gt 0) { 5 } else { 0 }

  return [int]($sourceScore + $citationScore + $influentialScore + $authorScore)
}

function Get-PaperCandidateProfile {
  param(
    [string]$Title,
    [string]$Source,
    [string]$SourceText,
    [int]$CitationCount = 0,
    [int]$InfluentialCitationCount = 0,
    [int]$AuthorCount = 0,
    [bool]$HasOpenAccessFullText = $false
  )

  $topic = Get-PaperTopic -Title $Title -Text $SourceText
  $qualityScore = Get-PaperQualityScore `
    -Source $Source `
    -CitationCount $CitationCount `
    -InfluentialCitationCount $InfluentialCitationCount `
    -AuthorCount $AuthorCount
  $hasApplicationSignal = Test-PaperApplicationSignal -Title $Title -Text $SourceText

  [ordered]@{
    paperTopic = $topic
    qualityScore = $qualityScore
    hasApplicationSignal = $hasApplicationSignal
    hasOpenAccessFullText = $HasOpenAccessFullText
    isEligibleForDailyPaper = ($HasOpenAccessFullText -and $topic -ne "out_of_scope" -and $qualityScore -ge 25 -and $hasApplicationSignal)
  }
}

function New-PaperReadingCard {
  param(
    [string]$Title,
    [string]$Topic,
    [string]$SourceText,
    [string]$SelectionReason
  )

  $terms = @()
  $haystack = "$Title $SourceText".ToLowerInvariant()
  if ($haystack -match "\beeg\b") { $terms += "EEG：把大脑电信号当作输入数据。" }
  if ($haystack -match "\bcnn\b") { $terms += "CNN：擅长从信号或图像里提取局部特征的神经网络。" }
  if ($haystack -match "\bsnn\b|spiking") { $terms += "SNN：模仿神经脉冲时序的神经网络。" }
  if ($haystack -match "\blora\b") { $terms += "LoRA：用较小参数改造大模型的轻量适配方法。" }
  if ($terms.Count -eq 0) { $terms += "关键技术词：保留原论文术语，并用白话解释其作用。" }

  [ordered]@{
    problem = "解决的问题：这篇论文试图把 $Topic 方向的研究推进到更可用的场景。"
    method = "解决方式：基于完整可读内容，概括它用什么模型、材料或系统流程解决问题。"
    difference = "不同之处：重点看它是否比旧方法更稳定、更便宜、更准确或更容易部署。"
    innovation = "创新点：把技术改进和真实应用目标连接起来，而不是只停留在理论指标。"
    implementation = "具体实现：先看输入数据，再看核心模型或装置，最后看实验验证结果。"
    applications = "应用途径：优先关注医疗辅助、工业系统、智能硬件、能源设备等可落地方向。"
    technicalTerms = $terms
    whySelected = $SelectionReason
  }
}

function Get-PaperAnalysisText {
  param(
    [string]$FullText,
    [string]$Abstract
  )

  if ($FullText -and $FullText.Trim()) {
    return $FullText.Trim()
  }

  return ""
}



