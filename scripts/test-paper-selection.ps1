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

$usablePaperText = @(
  "The full paper describes methods, experiments, accuracy, implementation, benchmark results, and clinical brain-computer interface use.",
  "Method: a complete EEG decoding pipeline extracts signal features and evaluates model behavior with repeatable experiments.",
  "Implementation: the system uses participant data, preprocessing, model adaptation, and accuracy evaluation for assistive communication.",
  "Application: the paper explains clinical device constraints, deployment cost, user control, and practical assistive communication scenarios."
) -join " "
$usablePaperText = (($usablePaperText + " ") * 8).Trim()

$fullTextPaper = Get-PaperCandidateProfile `
  -Title "Adaptive EEG foundation models for brain-computer interface control" `
  -Source "arXiv" `
  -SourceText $usablePaperText `
  -CitationCount 42 `
  -InfluentialCitationCount 8 `
  -AuthorCount 5 `
  -HasOpenAccessFullText $true

Assert-Equal $fullTextPaper.paperTopic "brain_computer_interface" "BCI topic should be detected."
Assert-Equal $fullTextPaper.readabilityStatus "open" "Readable papers should expose readability status."
Assert-True $fullTextPaper.isEligibleForDailyPaper "Full readable BCI paper with application signals should be eligible."

$abstractOnlyPaper = Get-PaperCandidateProfile `
  -Title "Hybrid EEG speech decoding for assistive communication" `
  -Source "Semantic Scholar" `
  -SourceText "Only an abstract is available, even though the topic sounds useful." `
  -CitationCount 90 `
  -InfluentialCitationCount 10 `
  -AuthorCount 6

Assert-True (-not $abstractOnlyPaper.isEligibleForDailyPaper) "Abstract-only papers should not enter daily recommendations."

$openArxivPaper = Get-PaperCandidateProfile `
  -Title "EEG-based imagined speech decoding using a hybrid CNN-SNN architecture" `
  -Source "arXiv" `
  -SourceText $usablePaperText `
  -AuthorCount 4 `
  -HasOpenAccessFullText $true

Assert-True $openArxivPaper.isEligibleForDailyPaper "Open arXiv papers with full text and application signals should not require citation counts."

$unclearApplication = Get-PaperCandidateProfile `
  -Title "A theoretical neural representation model" `
  -Source "arXiv" `
  -SourceText "We present a theoretical model and leave practical validation to future work." `
  -CitationCount 100 `
  -InfluentialCitationCount 30 `
  -AuthorCount 8 `
  -HasOpenAccessFullText $true

Assert-True (-not $unclearApplication.isEligibleForDailyPaper) "Quality alone should not make a paper eligible."

$card = New-PaperReadingCard `
  -Title "Hybrid CNN-SNN EEG speech decoding" `
  -Topic "brain_computer_interface" `
  -SourceText "A CNN extracts EEG temporal features and an SNN classifies imagined speech for assistive communication." `
  -SelectionReason "Open full text, BCI topic, quality signal, clear application."

Assert-True ($card.problem -match "解决") "Reading card should explain the problem in plain Chinese."
Assert-True ($card.technicalTerms.Count -ge 1) "Reading card should keep technical terms with plain explanations."

$analysisText = Get-PaperAnalysisText `
  -FullText "FULL PAPER METHOD SECTION: $usablePaperText" `
  -Abstract "ABSTRACT ONLY"

Assert-True ($analysisText -match "FULL PAPER METHOD SECTION") "Paper AI input should use extracted full text when available."
Assert-True ($analysisText -notmatch "ABSTRACT ONLY") "Paper AI input should not fall back to abstract when full text is available."

$thinAnalysisText = Get-PaperAnalysisText `
  -FullText "Only title, abstract, and references were extracted." `
  -Abstract "ABSTRACT ONLY"

Assert-Equal $thinAnalysisText "" "Paper AI input should reject extracted text that is too thin to support a reading card."

Write-Host "Paper selection tests passed."

