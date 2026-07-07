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

$recent = (Get-Date).AddDays(-20).ToUniversalTime().ToString("o")
$old = (Get-Date).AddDays(-160).ToUniversalTime().ToString("o")

$application = Get-AiCandidateProfile `
  -Title "New agent skill ships with GitHub repo and HN discussion" `
  -Url "https://github.com/example/agent-skill" `
  -Source "Hacker News" `
  -SourceText "Demo and official docs show a production workflow." `
  -PublishedAt $recent `
  -Points 420 `
  -Comments 80

Assert-Equal $application.aiArticleType "application_innovation" "Application candidate type mismatch."
Assert-True $application.isEligibleForAiMainSlot "Application candidate should pass evidence gate."
Assert-Equal $application.evidenceLabel "GitHub + Demo + Official docs + HN discussion" "Evidence label mismatch."
Assert-True $application.requiresRiskAnalysis "Application candidate should require risk analysis."

$concept = Get-AiCandidateProfile `
  -Title "A clear explanation of context engineering" `
  -Url "https://example.com/context-engineering-guide" `
  -Source "Engineering Blog" `
  -SourceText "This guide explains the concept using public examples." `
  -PublishedAt $recent

Assert-Equal $concept.aiArticleType "concept_explanation" "Concept candidate type mismatch."
Assert-True (-not $concept.requiresRiskAnalysis) "Concept explanation should not require risk analysis."

$weakApplication = Get-AiCandidateProfile `
  -Title "Amazing new AI app idea" `
  -Url "https://example.com/opinion" `
  -Source "Blog" `
  -SourceText "The author says the idea will change everything." `
  -PublishedAt $recent

Assert-True (-not $weakApplication.isEligibleForAiMainSlot) "Weak application should not pass evidence gate."

$oldCandidate = Get-AiCandidateProfile `
  -Title "Still influential agent workflow with GitHub and official docs" `
  -Url "https://github.com/example/still-influential-agent" `
  -Source "Company Engineering Blog" `
  -SourceText "Official docs describe why teams still use this workflow today." `
  -PublishedAt $old

Assert-True (-not $oldCandidate.isEligibleForAiMainSlot) "AI application candidates older than 3 months should be rejected."

$oldCandidateWithFormerException = Get-AiCandidateProfile `
  -Title "Old agent workflow with GitHub and official docs" `
  -Url "https://github.com/example/old-agent" `
  -Source "Company Engineering Blog" `
  -SourceText "Official docs describe the workflow." `
  -PublishedAt $old `
  -AllowAgeException

Assert-True (-not $oldCandidateWithFormerException.isEligibleForAiMainSlot) "The 3-month AI freshness rule should not allow exceptions."

$githubProject = Get-AiCandidateProfile `
  -Title "example/agent-runtime" `
  -Url "https://github.com/example/agent-runtime" `
  -Source "GitHub Search" `
  -SourceText "GitHub repository with 2400 stars and recent public activity." `
  -PublishedAt $recent

Assert-True $githubProject.isEligibleForAiMainSlot "GitHub project with community signal should pass evidence gate."
Assert-Equal $githubProject.evidenceLabel "GitHub + Community signal" "GitHub project evidence label mismatch."

$companyBlog = Get-AiCandidateProfile `
  -Title "New agent workflow from company engineering" `
  -Url "https://engineering.example.com/blog/agent-workflows" `
  -Source "Hacker News" `
  -SourceText "HN candidate with public discussion metrics. Points: 180. Comments: 60." `
  -PublishedAt $recent `
  -Points 180 `
  -Comments 60

Assert-True $companyBlog.isEligibleForAiMainSlot "Company engineering post with HN discussion should pass evidence gate."
Assert-Equal $companyBlog.evidenceLabel "Company source + HN discussion" "Company post evidence label mismatch."

$curatedConcept = Get-AiCandidateProfile `
  -Title "What changed in AI engineering this month" `
  -Url "https://example.com/ai-engineering-analysis" `
  -Source "Curated engineering feed" `
  -SourceText "A high-quality public analysis from a trusted engineering source." `
  -PublishedAt $recent `
  -PreferConceptExplanation

Assert-Equal $curatedConcept.aiArticleType "concept_explanation" "Curated feed fallback should be concept explanation."
Assert-True $curatedConcept.isEligibleForAiMainSlot "Curated concept explanation should be eligible."
Assert-True (-not $curatedConcept.requiresRiskAnalysis) "Curated concept should not require risk analysis."

Write-Host "AI selection tests passed."

