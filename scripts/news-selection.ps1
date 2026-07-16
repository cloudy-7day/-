$script:RequiredNewsCandidateFields = @(
  "id", "title", "source", "url", "publishedAt", "sourceText", "scope"
)

$script:NewsHardExclusionPattern = @(
  "\b(?:entertainment|celebrity|celebrities|movie|film|television|tv|variety\s+show|box\s+office|sports?|football|basketball|fashion|travel\s+guides?|shopping|promotions?|promotional|discount|sale)\b",
  "\u5a31\u4e50", "\u660e\u661f", "\u7535\u5f71", "\u7535\u89c6", "\u7efc\u827a",
  "\u7968\u623f", "\u4f53\u80b2", "\u8db3\u7403", "\u7bee\u7403", "\u65f6\u5c1a",
  "\u65c5\u6e38\u653b\u7565", "\u8d2d\u7269", "\u4fc3\u9500", "\u4f18\u60e0"
) -join "|"

$script:DomesticPriorityPatterns = @(
  "politics|government|central\s+policy|policy|law|legal|regulation|parliament|\u653f\u6cbb|\u653f\u5e9c|\u4e2d\u592e|\u653f\u7b56|\u6cd5\u5f8b|\u6cd5\u89c4",
  "disaster|earthquake|flood|typhoon|wildfire|emergency|public\s+safety|accident|rescue|\u707e\u5bb3|\u5730\u9707|\u6d2a\u6c34|\u53f0\u98ce|\u5e94\u6025|\u516c\u5171\u5b89\u5168|\u4e8b\u6545|\u6551\u63f4",
  "science|scientific|technology|research|semiconductor|aerospace|quantum|key\s+technology|\u79d1\u5b66|\u79d1\u6280|\u7814\u7a76|\u534a\u5bfc\u4f53|\u822a\u5929|\u91cf\u5b50|\u5173\u952e\u6280\u672f",
  "macroeconomy|economy|economic|finance|financial|industry|central\s+bank|markets?|gdp|trade|\u5b8f\u89c2\u7ecf\u6d4e|\u7ecf\u6d4e|\u91d1\u878d|\u4ea7\u4e1a|\u884c\u4e1a|\u592e\u884c|\u5e02\u573a|\u8d38\u6613",
  "community|education|healthcare|housing|employment|residents?|ordinary|social|public\s+service|\u793e\u533a|\u6559\u80b2|\u533b\u7597|\u4f4f\u623f|\u5c31\u4e1a|\u5c45\u6c11|\u6c11\u751f|\u793e\u4f1a|\u516c\u5171\u670d\u52a1"
)

$script:InternationalPoliticsPattern = "politics|political|government|election|president|minister|parliament|diplomacy|diplomatic|sanction|war|conflict|policy|law|\u653f\u6cbb|\u653f\u5e9c|\u9009\u4e3e|\u603b\u7edf|\u90e8\u957f|\u8bae\u4f1a|\u5916\u4ea4|\u5236\u88c1|\u6218\u4e89|\u51b2\u7a81|\u653f\u7b56|\u6cd5\u5f8b"
$script:InternationalFinancePattern = "finance|financial|economy|economic|markets?|stocks?|bonds?|currency|central\s+bank|interest\s+rates?|earnings|trade|gdp|\u91d1\u878d|\u7ecf\u6d4e|\u5e02\u573a|\u80a1\u7968|\u503a\u5238|\u8d27\u5e01|\u592e\u884c|\u5229\u7387|\u8d38\u6613"

function Get-NewsCandidateText {
  param($Candidate)
  return "$(if ($null -ne $Candidate.title) { $Candidate.title }) $(if ($null -ne $Candidate.sourceText) { $Candidate.sourceText })"
}

function Test-NewsCandidateShape {
  param($Candidate)

  if ($null -eq $Candidate) { return $false }
  foreach ($field in $script:RequiredNewsCandidateFields) {
    if ($Candidate.PSObject.Properties.Name -notcontains $field) { return $false }
  }
  return $true
}

function Test-NewsCandidateFresh {
  param($Candidate, [datetimeoffset]$Now)

  if (-not (Test-NewsCandidateShape -Candidate $Candidate)) { return $false }
  $published = [datetimeoffset]::MinValue
  if (-not [datetimeoffset]::TryParse([string]$Candidate.publishedAt, [ref]$published)) { return $false }
  $age = $Now.ToUniversalTime() - $published.ToUniversalTime()
  return ($age.TotalSeconds -ge 0 -and $age.TotalHours -le 8)
}

function Test-NewsHardExcluded {
  param($Candidate)
  if ($null -eq $Candidate) { return $false }
  return ((Get-NewsCandidateText -Candidate $Candidate) -match $script:NewsHardExclusionPattern)
}

function Get-DomesticNewsPriority {
  param($Candidate)

  if ($null -eq $Candidate -or (Test-NewsHardExcluded -Candidate $Candidate)) { return 0 }
  $text = Get-NewsCandidateText -Candidate $Candidate
  for ($index = 0; $index -lt $script:DomesticPriorityPatterns.Count; $index++) {
    if ($text -match $script:DomesticPriorityPatterns[$index]) {
      return $script:DomesticPriorityPatterns.Count - $index
    }
  }
  return 0
}

function Get-InternationalNewsKind {
  param($Candidate)

  if ($null -eq $Candidate -or (Test-NewsHardExcluded -Candidate $Candidate)) { return $null }
  $text = Get-NewsCandidateText -Candidate $Candidate
  if ($text -match $script:InternationalPoliticsPattern) { return "politics" }
  if ($text -match $script:InternationalFinancePattern) { return "finance" }
  return $null
}

function Add-NewsTierWithSourceDiversity {
  param(
    [object[]]$Tier,
    [System.Collections.ArrayList]$Selected,
    [hashtable]$SelectedSources,
    [int]$TargetCount
  )

  foreach ($candidate in $Tier) {
    if ($Selected.Count -ge $TargetCount) { return }
    $sourceKey = ([string]$candidate.source).ToLowerInvariant()
    if (-not $SelectedSources.ContainsKey($sourceKey)) {
      [void]$Selected.Add($candidate)
      $SelectedSources[$sourceKey] = $true
    }
  }
  foreach ($candidate in $Tier) {
    if ($Selected.Count -ge $TargetCount) { return }
    if ($Selected -contains $candidate) { continue }
    [void]$Selected.Add($candidate)
    $SelectedSources[([string]$candidate.source).ToLowerInvariant()] = $true
  }
}

function Select-DomesticNewsCandidates {
  param([object[]]$Candidates, [datetimeoffset]$Now, [int]$TargetCount)

  if ($TargetCount -le 0) { return @() }
  $eligible = @($Candidates | Where-Object {
    (Test-NewsCandidateFresh -Candidate $_ -Now $Now) -and
    -not (Test-NewsHardExcluded -Candidate $_) -and
    (Get-DomesticNewsPriority -Candidate $_) -gt 0
  })
  $selected = [System.Collections.ArrayList]::new()
  $selectedSources = @{}
  for ($priority = $script:DomesticPriorityPatterns.Count; $priority -ge 1; $priority--) {
    $tier = @($eligible | Where-Object { (Get-DomesticNewsPriority -Candidate $_) -eq $priority })
    Add-NewsTierWithSourceDiversity -Tier $tier -Selected $selected -SelectedSources $selectedSources -TargetCount $TargetCount
    if ($selected.Count -ge $TargetCount) { break }
  }
  return @($selected)
}

function Select-InternationalNewsCandidates {
  param([object[]]$Candidates, [datetimeoffset]$Now, [int]$TargetCount)

  if ($TargetCount -le 0) { return @() }
  $politics = [System.Collections.ArrayList]::new()
  $finance = [System.Collections.ArrayList]::new()
  foreach ($candidate in $Candidates) {
    if (-not (Test-NewsCandidateFresh -Candidate $candidate -Now $Now)) { continue }
    $kind = Get-InternationalNewsKind -Candidate $candidate
    if ($kind -eq "politics") { [void]$politics.Add($candidate) }
    elseif ($kind -eq "finance") { [void]$finance.Add($candidate) }
  }

  $selected = [System.Collections.ArrayList]::new()
  $selectedSources = @{}
  if ($politics.Count -gt 0 -and $finance.Count -gt 0) {
    [void]$selected.Add($politics[0])
    $selectedSources[([string]$politics[0].source).ToLowerInvariant()] = $true
    if ($selected.Count -lt $TargetCount) {
      $financeChoice = @($finance | Where-Object {
        -not $selectedSources.ContainsKey(([string]$_.source).ToLowerInvariant())
      } | Select-Object -First 1)
      if ($financeChoice.Count -eq 0) { $financeChoice = @($finance[0]) }
      [void]$selected.Add($financeChoice[0])
      $selectedSources[([string]$financeChoice[0].source).ToLowerInvariant()] = $true
    }
  }

  if ($selected.Count -lt $TargetCount) {
    $remaining = @(@($politics) + @($finance) | Where-Object { $selected -notcontains $_ })
    Add-NewsTierWithSourceDiversity -Tier $remaining -Selected $selected -SelectedSources $selectedSources -TargetCount $TargetCount
  }
  return @($selected)
}
