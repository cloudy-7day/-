$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "article-selection.ps1")

function Assert-Equal {
  param($Actual, $Expected, [string]$Message)
  if ($Actual -ne $Expected) {
    throw "$Message Expected '$Expected', got '$Actual'."
  }
}

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw $Message
  }
}

$paperCard = New-PaperReadingCard `
  -Title "Hybrid CNN-SNN EEG speech decoding" `
  -Topic "brain_computer_interface" `
  -SourceText "A CNN extracts EEG temporal features and an SNN classifies imagined speech for assistive communication." `
  -SelectionReason "Open full text, BCI topic, quality signal, clear application."

$translation = New-ArticleEnglishTranslation `
  -Category "paper" `
  -Title "Hybrid CNN-SNN EEG speech decoding" `
  -Highlight "A hybrid decoder combines temporal features with spike-based classification." `
  -Summary "这篇论文解释了一个可应用的脑机接口方案。" `
  -FailureAnalysis "重点检查样本量和真实部署成本。" `
  -PaperCard $paperCard

Assert-True ($translation.summary.Length -gt 0) "English translation should include a summary."
Assert-Equal $translation.highlight "A hybrid decoder combines temporal features with spike-based classification." "English translation should preserve a source-grounded highlight."
Assert-True ($translation.failureAnalysis.Length -gt 0) "English translation should include the key takeaway."
Assert-Equal $translation.title "Hybrid CNN-SNN EEG speech decoding" "English translation should preserve a title fallback."
Assert-Equal $translation.paperCard.technicalTerms.Count $paperCard.technicalTerms.Count "Paper terms should remain available in English mode."

$analysisWithoutTitle = [ordered]@{
  highlight = "Traceable fallback sentence."
  summary = "Local fallback summary."
  failureAnalysis = "Local fallback takeaway."
}

$fallback = Get-EnglishTranslationForAnalysis `
  -Category "ai" `
  -Title "Example AI Workflow" `
  -Analysis $analysisWithoutTitle

Assert-Equal $fallback.title "Example AI Workflow" "Fallback translation helper should preserve the source title when analysis has no title."
Assert-Equal $fallback.highlight "Traceable fallback sentence." "Fallback translation helper should preserve the source highlight."

$analysisWithTranslationWithoutTitle = [ordered]@{
  summary = "Chinese summary."
  failureAnalysis = "Chinese takeaway."
  translations = [ordered]@{
    en = [ordered]@{
      summary = "English summary from API."
      failureAnalysis = "English takeaway from API."
    }
  }
}

$apiFallback = Get-EnglishTranslationForAnalysis `
  -Category "ai" `
  -Title "API Missing Title" `
  -Analysis $analysisWithTranslationWithoutTitle

Assert-Equal $apiFallback.title "API Missing Title" "Existing English analysis should receive a title fallback when API omits title."

$bilingualAnalysis = [ordered]@{
  title = "六个月增长十倍，Codex 用户数升至七百万"
  highlight = "六个月内使用量增长超过十倍，最近一天新增约一百万用户。"
  summary = "中文摘要。"
  failureAnalysis = "中文判断。"
  translations = [ordered]@{
    en = [ordered]@{
      title = "Codex usage grows tenfold in six months"
      highlight = "Usage grew more than tenfold in six months."
      summary = "English summary."
      failureAnalysis = "English takeaway."
    }
  }
}
$chinese = Get-ChineseTranslationForAnalysis -Category "ai" -Analysis $bilingualAnalysis
Assert-Equal $chinese.title $bilingualAnalysis.title "Chinese translation must use the generated Chinese display title."
Assert-Equal $chinese.highlight $bilingualAnalysis.highlight "Chinese translation must preserve the source-grounded Chinese highlight."

$missingChineseTitle = Get-ChineseTranslationForAnalysis -Category "ai" -Analysis ([ordered]@{
  highlight = "中文原文摘录。"
  summary = "中文摘要。"
  failureAnalysis = "中文判断。"
})
Assert-Equal $missingChineseTitle.title "" "A missing Chinese title must stay empty so validation can fail closed."

Write-Host "Translation tests passed."
