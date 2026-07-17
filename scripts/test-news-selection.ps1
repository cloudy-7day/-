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

$lifestyleCandidates = @(
  New-NewsCandidate -Id "lifestyle-policy" -Title "Government policy shapes lifestyle trends"
  New-NewsCandidate -Id "lifestyle-finance" -Title "Financial markets shape lifestyle trends" -Scope "international"
  New-NewsCandidate -Id "lifestyle-cn" -Title ([regex]::Unescape("\u653f\u5e9c\u91d1\u878d\u653f\u7b56\u4e0e\u751f\u6d3b\u65b9\u5f0f\u8d8b\u52bf")) -Scope "international"
)
foreach ($lifestyleCandidate in $lifestyleCandidates) {
  Assert-True (Test-NewsHardExcluded -Candidate $lifestyleCandidate) "Lifestyle content '$($lifestyleCandidate.id)' should be hard excluded before policy or finance classification."
}
$lifestyleDomesticSelected = @(Select-DomesticNewsCandidates -Candidates @($lifestyleCandidates[0]) -Now $now -TargetCount 1)
$lifestyleInternationalSelected = @(Select-InternationalNewsCandidates -Candidates @($lifestyleCandidates[1], $lifestyleCandidates[2]) -Now $now -TargetCount 2)
Assert-Equal $lifestyleDomesticSelected.Count 0 "Lifestyle must override domestic policy priority."
Assert-Equal $lifestyleInternationalSelected.Count 0 "Lifestyle must override international politics and finance classification."

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

$domesticRecentFirst = @(
  New-NewsCandidate -Id "recent-science" -Title "Science research update" -Source "Wire A" -PublishedAt "2026-07-15T16:00:00Z"
  New-NewsCandidate -Id "recent-economy" -Title "Economic industry update" -Source "Wire A" -PublishedAt "2026-07-16T15:00:00Z"
  New-NewsCandidate -Id "older-policy" -Title "Central government policy update" -Source "Wire B" -PublishedAt "2026-07-15T15:59:00Z"
)
$domesticRecentFirstSelected = @(Select-DomesticNewsCandidates -Candidates $domesticRecentFirst -Now $now -TargetCount 2)
Assert-Equal (($domesticRecentFirstSelected.id) -join ",") "recent-science,recent-economy" "Domestic candidates at or within 24 hours must fill the quota before an older higher-priority or alternate-source candidate."

$domesticFreshnessBeforeDiversity = @(
  New-NewsCandidate -Id "fresh-policy-a" -Title "Central policy freshest" -Source "Wire A" -PublishedAt "2026-07-16T15:00:00Z"
  New-NewsCandidate -Id "fresh-policy-b" -Title "Central policy next freshest" -Source "Wire A" -PublishedAt "2026-07-16T14:00:00Z"
  New-NewsCandidate -Id "old-policy-alternate" -Title "Central policy old alternate source" -Source "Wire B" -PublishedAt "2026-07-14T17:00:00Z"
)
$domesticFreshnessBeforeDiversitySelected = @(Select-DomesticNewsCandidates -Candidates $domesticFreshnessBeforeDiversity -Now $now -TargetCount 2)
Assert-Equal (($domesticFreshnessBeforeDiversitySelected.id) -join ",") "fresh-policy-a,fresh-policy-b" "Domestic source diversity must not reach from 1-2-hour items to a 47-hour item."

$tierAndDiversity = @(
  New-NewsCandidate -Id "policy-a1" -Title "Central policy alpha" -Source "Wire A"
  New-NewsCandidate -Id "policy-a2" -Title "Central policy beta" -Source "Wire A"
  New-NewsCandidate -Id "policy-b" -Title "Central policy gamma" -Source "Wire B"
  New-NewsCandidate -Id "disaster-c" -Title "Public safety emergency response" -Source "Wire C"
)
$diverseDomestic = @(Select-DomesticNewsCandidates -Candidates $tierAndDiversity -Now $now -TargetCount 3)
Assert-Equal (($diverseDomestic.id) -join ",") "policy-a1,policy-b,policy-a2" "Same-tier source diversity must not let a lower tier outrank a repeated source."

$mixedDomestic = @(
  New-NewsCandidate -Id "domestic-old" -Title "Central government policy older" -Source "Wire A" -PublishedAt "2026-07-14T17:00:00Z" -Scope "domestic"
  New-NewsCandidate -Id "wrong-scope-new" -Title "Central government policy newest" -Source "Wire B" -PublishedAt "2026-07-16T15:30:00Z" -Scope "international"
  New-NewsCandidate -Id "domestic-new" -Title "Central government policy newer" -Source "Wire A" -PublishedAt "2026-07-16T15:00:00Z" -Scope "domestic"
)
$mixedDomesticSelected = @(Select-DomesticNewsCandidates -Candidates $mixedDomestic -Now $now -TargetCount 2)
Assert-Equal (($mixedDomesticSelected.id) -join ",") "domestic-new,domestic-old" "Domestic selection must reject wrong scope and sort newer first within an equal tier/source."

$internationalBalanced = @(
  New-NewsCandidate -Id "politics-a" -Title "Election and government diplomacy update" -Source "Wire A" -Scope "international"
  New-NewsCandidate -Id "finance-a" -Title "Global markets and central bank finance update" -Source "Wire A" -Scope "international"
  New-NewsCandidate -Id "finance-b" -Title "Global markets and central bank finance outlook" -Source "Wire B" -Scope "international"
)
Assert-Equal (Get-InternationalNewsKind -Candidate $internationalBalanced[0]) "politics" "International politics classification mismatch."
Assert-Equal (Get-InternationalNewsKind -Candidate $internationalBalanced[1]) "finance" "International finance classification mismatch."
$monetaryPolicy = New-NewsCandidate -Id "monetary-policy" -Title "Central bank monetary policy holds interest rates steady" -Scope "international"
$tariffPolicy = New-NewsCandidate -Id "tariff-policy" -Title "Government tariff and trade policy changes import costs" -Scope "international"
$foreignPolicy = New-NewsCandidate -Id "foreign-policy" -Title "Foreign policy guides diplomatic talks between ministers" -Scope "international"
Assert-Equal (Get-InternationalNewsKind -Candidate $monetaryPolicy) "finance" "Specific monetary-policy signals must override generic policy classification."
Assert-Equal (Get-InternationalNewsKind -Candidate $tariffPolicy) "finance" "Tariff/trade policy must classify as finance."
Assert-Equal (Get-InternationalNewsKind -Candidate $foreignPolicy) "politics" "Ordinary foreign policy and diplomacy must remain politics."
$balanced = @(Select-InternationalNewsCandidates -Candidates $internationalBalanced -Now $now -TargetCount 2)
Assert-Equal (($balanced.id) -join ",") "politics-a,finance-b" "International selection should balance kinds and prefer different sources."

$internationalRecentFirst = @(
  New-NewsCandidate -Id "recent-politics" -Title "Election and diplomacy freshest update" -Source "Wire A" -PublishedAt "2026-07-16T15:00:00Z" -Scope "international"
  New-NewsCandidate -Id "recent-finance" -Title "Central bank financial markets fresh update" -Source "Wire A" -PublishedAt "2026-07-16T14:00:00Z" -Scope "international"
  New-NewsCandidate -Id "older-finance-alternate" -Title "Central bank financial markets older update" -Source "Wire B" -PublishedAt "2026-07-15T15:59:00Z" -Scope "international"
)
$internationalRecentFirstSelected = @(Select-InternationalNewsCandidates -Candidates $internationalRecentFirst -Now $now -TargetCount 2)
Assert-Equal (($internationalRecentFirstSelected.id) -join ",") "recent-politics,recent-finance" "International candidates within 24 hours must fill the balanced quota before an older alternate-source candidate."

$internationalFreshnessBeforeDiversity = @(
  New-NewsCandidate -Id "fresh-politics-a" -Title "Election and government diplomacy freshest" -Source "Wire A" -PublishedAt "2026-07-16T15:00:00Z" -Scope "international"
  New-NewsCandidate -Id "fresh-finance-a" -Title "Central bank financial markets next freshest" -Source "Wire A" -PublishedAt "2026-07-16T14:00:00Z" -Scope "international"
  New-NewsCandidate -Id "older-finance-b" -Title "Central bank financial markets alternate source" -Source "Wire B" -PublishedAt "2026-07-16T13:00:00Z" -Scope "international"
)
$internationalFreshnessBeforeDiversitySelected = @(Select-InternationalNewsCandidates -Candidates $internationalFreshnessBeforeDiversity -Now $now -TargetCount 2)
Assert-Equal (($internationalFreshnessBeforeDiversitySelected.id) -join ",") "fresh-politics-a,fresh-finance-a" "International source diversity must only break exact freshness ties while preserving politics/finance balance."

$internationalReversePair = @(
  New-NewsCandidate -Id "reverse-politics-a" -Title "Government election diplomacy update" -Source "Wire A" -Scope "international"
  New-NewsCandidate -Id "reverse-politics-b" -Title "Parliament and minister diplomacy update" -Source "Wire B" -Scope "international"
  New-NewsCandidate -Id "reverse-finance-a" -Title "Central bank and financial markets update" -Source "Wire A" -Scope "international"
)
$reverseBalanced = @(Select-InternationalNewsCandidates -Candidates $internationalReversePair -Now $now -TargetCount 2)
Assert-Equal (($reverseBalanced.id) -join ",") "reverse-politics-b,reverse-finance-a" "International pairing should search both kinds for a different-source combination."

$mixedInternational = @(
  New-NewsCandidate -Id "international-politics-old" -Title "Election and diplomacy older update" -Source "Wire A" -PublishedAt "2026-07-14T17:00:00Z" -Scope "international"
  New-NewsCandidate -Id "wrong-scope-finance" -Title "Central bank interest rates newest" -Source "Wire B" -PublishedAt "2026-07-16T15:30:00Z" -Scope "domestic"
  New-NewsCandidate -Id "international-politics-new" -Title "Election and diplomacy newer update" -Source "Wire A" -PublishedAt "2026-07-16T15:00:00Z" -Scope "international"
  New-NewsCandidate -Id "international-finance" -Title "Central bank interest rates update" -Source "Wire B" -PublishedAt "2026-07-16T14:00:00Z" -Scope "international"
)
$mixedInternationalSelected = @(Select-InternationalNewsCandidates -Candidates $mixedInternational -Now $now -TargetCount 2)
Assert-Equal (($mixedInternationalSelected.id) -join ",") "international-politics-new,international-finance" "International selection must reject wrong scope and sort newer first within a class/source."

$financeOnly = @(
  New-NewsCandidate -Id "finance-one" -Title "Stocks and markets rise after earnings" -Source "Wire A" -Scope "international"
  New-NewsCandidate -Id "finance-two" -Title "Central bank changes interest rates" -Source "Wire B" -Scope "international"
)
$financeSelected = @(Select-InternationalNewsCandidates -Candidates $financeOnly -Now $now -TargetCount 2)
Assert-Equal (($financeSelected.id) -join ",") "finance-one,finance-two" "Two finance items should fill both international slots."

$internationalSports = New-NewsCandidate -Id "sports" -Title "Football team wins championship match" -Scope "international"
Assert-Equal (Get-InternationalNewsKind -Candidate $internationalSports) $null "International sports should not classify as politics or finance."
$namedInternationalSports = @(
  New-NewsCandidate -Id "world-cup-finance" -Title "World Cup finance outlook lifts global markets" -Scope "international"
  New-NewsCandidate -Id "olympic-policy" -Title "Olympic policy changes prompt government debate" -Scope "international"
  New-NewsCandidate -Id "world-cup-finance-cn" -Title ([regex]::Unescape("\u4e16\u754c\u676f\u5546\u4e1a\u4e0e\u91d1\u878d\u5c55\u671b")) -Scope "international"
  New-NewsCandidate -Id "olympics-policy-cn" -Title ([regex]::Unescape("\u5965\u8fd0\u4f1a\u7ecf\u6d4e\u653f\u7b56\u8c03\u6574")) -Scope "international"
)
foreach ($namedSportsCandidate in $namedInternationalSports) {
  Assert-True (Test-NewsHardExcluded -Candidate $namedSportsCandidate) "Named international sports event '$($namedSportsCandidate.id)' should be hard excluded."
  Assert-Equal (Get-InternationalNewsKind -Candidate $namedSportsCandidate) $null "Named international sports event '$($namedSportsCandidate.id)' should not classify as politics or finance."
}
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
