import re

with open('scripts/update-daily.ps1', 'r', encoding='utf-8-sig') as f:
    content = f.read()

# 1. Add AbstractUrl parameter to New-PaperItem
old_param = '''function New-PaperItem {
  param(
    [string]$Id,
    [string]$Title,
    [string]$Source,
    [string]$Url,
    [string]$PublishedAt,
    [string]$SourceText,
    [int]$CitationCount = 0,
    [int]$InfluentialCitationCount = 0,
    [int]$AuthorCount = 0,
    [bool]$HasOpenAccessFullText = $false
  )'''

new_param = '''function New-PaperItem {
  param(
    [string]$Id,
    [string]$Title,
    [string]$Source,
    [string]$Url,
    [string]$AbstractUrl = '',
    [string]$PublishedAt,
    [string]$SourceText,
    [int]$CitationCount = 0,
    [int]$InfluentialCitationCount = 0,
    [int]$AuthorCount = 0,
    [bool]$HasOpenAccessFullText = $false
  )'''

content = content.replace(old_param, new_param)

# 2. Add abstractUrl to the returned hashtable
old_return = '    url = $Url\n    publishedAt = $PublishedAt'
new_return = '    url = $Url\n    abstractUrl = $AbstractUrl\n    publishedAt = $PublishedAt'
content = content.replace(old_return, new_return)

# 3. In Get-ArxivAppliedPapers, derive abstractUrl and pass it
old_call = '''      New-PaperItem `
        -Id ("paper-" + $arxivId.Replace("v1", "")) `
        -Title ([string]$_.title) `
        -Source "arXiv" `
        -Url $pdfUrl `
        -PublishedAt (([datetime]$_.published).ToUniversalTime().ToString("o")) `
        -SourceText $analysisText `
        -AuthorCount (@($_.author).Count) `
        -HasOpenAccessFullText $true'''

new_call = '''      $arxivBase = $arxivId -replace "v\\d+$", ""
      $abstractUrl = "https://arxiv.org/abs/$arxivBase"
      New-PaperItem `
        -Id ("paper-" + $arxivId.Replace("v1", "")) `
        -Title ([string]$_.title) `
        -Source "arXiv" `
        -Url $pdfUrl `
        -AbstractUrl $abstractUrl `
        -PublishedAt (([datetime]$_.published).ToUniversalTime().ToString("o")) `
        -SourceText $analysisText `
        -AuthorCount (@($_.author).Count) `
        -HasOpenAccessFullText $true'''

content = content.replace(old_call, new_call)

with open('scripts/update-daily.ps1', 'w', encoding='utf-8-sig') as f:
    f.write(content)
print('Done - update-daily.ps1 updated')
