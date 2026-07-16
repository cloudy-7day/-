$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "news-selection.ps1")

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

function New-NewsCandidate {
  param(
    [string]$Id,
    [string]$Title,
    [string]$Source = "Wire A",
    [string]$PublishedAt = "2026-07-16T15:00:00Z",
    [string]$SourceText = "",
    [string]$Scope = "domestic"
  )

  [pscustomobject]@{
    id = $Id
    title = $Title
    source = $Source
    url = "https://example.com/$Id"
    publishedAt = $PublishedAt
    sourceText = $SourceText
    scope = $Scope
  }
}

$now = [datetimeoffset]::Parse("2026-07-16T16:00:00Z")

$domesticOrdering = @(
  New-NewsCandidate -Id "social" -Title "Community services affect ordinary residents"
  New-NewsCandidate -Id "economy" -Title "Central bank publishes macroeconomy and industry data"
  New-NewsCandidate -Id "science" -Title "Science research delivers a key technology breakthrough"
  New-NewsCandidate -Id "disaster" -Title "Flood disaster triggers emergency public safety response"
  New-NewsCandidate -Id "policy" -Title "Government announces central policy and law package"
)
$orderedDomestic = @(Select-DomesticNewsCandidates -Candidates $domesticOrdering -Now $now -TargetCount 5)
Assert-Equal (($orderedDomestic.id) -join ",") "policy,disaster,science,economy,social" "Domestic importance ordering mismatch."
Assert-True ((Get-DomesticNewsPriority -Candidate $domesticOrdering[4]) -gt (Get-DomesticNewsPriority -Candidate $domesticOrdering[3])) "Policy must outrank disaster news."

$entertainment = New-NewsCandidate -Id "entertainment" -Title "Celebrity movie box office entertainment news"
Assert-True (Test-NewsHardExcluded -Candidate $entertainment) "Entertainment news should be hard excluded."
$withEntertainment = @(Select-DomesticNewsCandidates -Candidates @($domesticOrdering[4], $entertainment) -Now $now -TargetCount 3)
Assert-Equal (($withEntertainment.id) -join ",") "policy" "Domestic entertainment should not be selected."
$transportPolicy = New-NewsCandidate -Id "transport-policy" -Title "Government transport policy update"
Assert-True (-not (Test-NewsHardExcluded -Candidate $transportPolicy)) "The sports exclusion must not match the word transport."

$commentAndAdvertorialCandidates = @(
  New-NewsCandidate -Id "opinion-policy" -Title "Opinion: government policy will reshape the country"
  New-NewsCandidate -Id "commentary-industry" -Title "Commentary on the semiconductor industry"
  New-NewsCandidate -Id "editorial-policy" -Title "Editorial: a new central policy direction"
  New-NewsCandidate -Id "advertorial-industry" -Title "Advertorial for an industry product launch"
  New-NewsCandidate -Id "sponsored-policy" -Title "Sponsored policy analysis from a consumer brand"
  New-NewsCandidate -Id "pure-comment-cn" -Title ([regex]::Unescape("\u7eaf\u8bc4\u8bba\uff1a\u4e2d\u592e\u653f\u7b56\u89c2\u70b9"))
  New-NewsCandidate -Id "soft-ad-cn" -Title ([regex]::Unescape("\u884c\u4e1a\u6d88\u8d39\u8f6f\u6587"))
)
foreach ($excludedCandidate in $commentAndAdvertorialCandidates) {
  Assert-True (Test-NewsHardExcluded -Candidate $excludedCandidate) "Commentary and advertorial content '$($excludedCandidate.id)' should be hard excluded."
}
$commentAndAdvertorialSelected = @(Select-DomesticNewsCandidates -Candidates $commentAndAdvertorialCandidates -Now $now -TargetCount 3)
Assert-Equal $commentAndAdvertorialSelected.Count 0 "Policy and industry keywords must not override commentary or advertorial exclusions."

$ageCandidates = @(
  New-NewsCandidate -Id "recent" -Title "Central government policy update"
  New-NewsCandidate -Id "old" -Title "Central government policy archive" -PublishedAt "2026-07-14T04:00:00Z"
  New-NewsCandidate -Id "invalid" -Title "Central government policy invalid date" -PublishedAt "not-a-date"
  New-NewsCandidate -Id "future" -Title "Central government policy future item" -PublishedAt "2026-07-16T16:00:01Z"
)
$ageSelected = @(Select-DomesticNewsCandidates -Candidates $ageCandidates -Now $now -TargetCount 4)
Assert-Equal (($ageSelected.id) -join ",") "recent" "Old, invalid, and future domestic timestamps should be rejected."

$freshnessBoundary = @(
  New-NewsCandidate -Id "age-48h" -Title "Central policy at freshness boundary" -PublishedAt "2026-07-14T16:00:00Z"
  New-NewsCandidate -Id "age-48h-1m" -Title "Central policy beyond freshness boundary" -PublishedAt "2026-07-14T15:59:00Z"
  New-NewsCandidate -Id "age-49h" -Title "Central policy outside freshness window" -PublishedAt "2026-07-14T15:00:00Z"
)
$boundarySelected = @(Select-DomesticNewsCandidates -Candidates $freshnessBoundary -Now $now -TargetCount 3)
Assert-Equal (($boundarySelected.id) -join ",") "age-48h" "Exactly 48 hours should be accepted, while 48 hours plus one minute and 49 hours should be rejected."

$tierAndDiversity = @(
  New-NewsCandidate -Id "policy-a1" -Title "Central policy alpha" -Source "Wire A"
  New-NewsCandidate -Id "policy-a2" -Title "Central policy beta" -Source "Wire A"
  New-NewsCandidate -Id "policy-b" -Title "Central policy gamma" -Source "Wire B"
  New-NewsCandidate -Id "disaster-c" -Title "Public safety emergency response" -Source "Wire C"
)
$diverseDomestic = @(Select-DomesticNewsCandidates -Candidates $tierAndDiversity -Now $now -TargetCount 3)
Assert-Equal (($diverseDomestic.id) -join ",") "policy-a1,policy-b,policy-a2" "Same-tier source diversity must not let a lower tier outrank a repeated source."

$internationalBalanced = @(
  New-NewsCandidate -Id "politics-a" -Title "Election and government diplomacy update" -Source "Wire A" -Scope "international"
  New-NewsCandidate -Id "finance-a" -Title "Global markets and central bank finance update" -Source "Wire A" -Scope "international"
  New-NewsCandidate -Id "finance-b" -Title "Global markets and central bank finance outlook" -Source "Wire B" -Scope "international"
)
Assert-Equal (Get-InternationalNewsKind -Candidate $internationalBalanced[0]) "politics" "International politics classification mismatch."
Assert-Equal (Get-InternationalNewsKind -Candidate $internationalBalanced[1]) "finance" "International finance classification mismatch."
$balanced = @(Select-InternationalNewsCandidates -Candidates $internationalBalanced -Now $now -TargetCount 2)
Assert-Equal (($balanced.id) -join ",") "politics-a,finance-b" "International selection should balance kinds and prefer different sources."

$internationalReversePair = @(
  New-NewsCandidate -Id "reverse-politics-a" -Title "Government election diplomacy update" -Source "Wire A" -Scope "international"
  New-NewsCandidate -Id "reverse-politics-b" -Title "Parliament and minister diplomacy update" -Source "Wire B" -Scope "international"
  New-NewsCandidate -Id "reverse-finance-a" -Title "Central bank and financial markets update" -Source "Wire A" -Scope "international"
)
$reverseBalanced = @(Select-InternationalNewsCandidates -Candidates $internationalReversePair -Now $now -TargetCount 2)
Assert-Equal (($reverseBalanced.id) -join ",") "reverse-politics-b,reverse-finance-a" "International pairing should search both kinds for a different-source combination."

$financeOnly = @(
  New-NewsCandidate -Id "finance-one" -Title "Stocks and markets rise after earnings" -Source "Wire A" -Scope "international"
  New-NewsCandidate -Id "finance-two" -Title "Central bank changes interest rates" -Source "Wire B" -Scope "international"
)
$financeSelected = @(Select-InternationalNewsCandidates -Candidates $financeOnly -Now $now -TargetCount 2)
Assert-Equal (($financeSelected.id) -join ",") "finance-one,finance-two" "Two finance items should fill both international slots."

$internationalSports = New-NewsCandidate -Id "sports" -Title "Football team wins championship match" -Scope "international"
Assert-Equal (Get-InternationalNewsKind -Candidate $internationalSports) $null "International sports should not classify as politics or finance."
$sportsSelected = @(Select-InternationalNewsCandidates -Candidates @($internationalSports, $financeOnly[0]) -Now $now -TargetCount 2)
Assert-Equal (($sportsSelected.id) -join ",") "finance-one" "International sports should be excluded."

$substringCandidates = @(
  New-NewsCandidate -Id "hardware" -Title "A hardware product launch" -Scope "international"
  New-NewsCandidate -Id "flaw" -Title "Researchers disclose a software flaw" -Scope "international"
  New-NewsCandidate -Id "marketing" -Title "A company changes its marketing strategy" -Scope "international"
)
foreach ($substringCandidate in $substringCandidates) {
  Assert-Equal (Get-InternationalNewsKind -Candidate $substringCandidate) $null "English category keywords must not match inside '$($substringCandidate.id)'."
}
$substringSelected = @(Select-InternationalNewsCandidates -Candidates $substringCandidates -Now $now -TargetCount 2)
Assert-Equal $substringSelected.Count 0 "Substring-only international matches should not be selected."

Write-Host "News selection tests passed."
