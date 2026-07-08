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
  -Summary "这篇论文解释了一个可应用的脑机接口方案。" `
  -FailureAnalysis "重点检查样本量和真实部署成本。" `
  -PaperCard $paperCard

Assert-True ($translation.summary.Length -gt 0) "English translation should include a summary."
Assert-True ($translation.failureAnalysis.Length -gt 0) "English translation should include the key takeaway."
Assert-Equal $translation.title "Hybrid CNN-SNN EEG speech decoding" "English translation should preserve a title fallback."
Assert-Equal $translation.paperCard.technicalTerms.Count $paperCard.technicalTerms.Count "Paper terms should remain available in English mode."

$analysisWithoutTitle = [ordered]@{
  summary = "Local fallback summary."
  failureAnalysis = "Local fallback takeaway."
}

$fallback = Get-EnglishTranslationForAnalysis `
  -Category "ai" `
  -Title "Example AI Workflow" `
  -Analysis $analysisWithoutTitle

Assert-Equal $fallback.title "Example AI Workflow" "Fallback translation helper should preserve the source title when analysis has no title."

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

Write-Host "Translation tests passed."
