# Daily News Hardening Design

## Goal

Harden the nine-item daily-news implementation before merge by fixing three confirmed failure modes and adding pull-request validation that never performs live collection or publication.

## Confirmed defects

1. The configured Reuters World RSS endpoint no longer completes a TLS connection, so every update wastes a retry and loses one international source.
2. News conversion refill accepts any non-empty bilingual fields. Invalid Chinese display titles, template-style highlights, overlong highlights, forbidden fallback text, or inconsistent source-extract metadata can therefore survive refill and fail only during final payload validation, aborting the whole nine-item update despite eligible alternatives.
3. The hard sports exclusion does not cover common event names such as World Cup, FIFA World Cup, Olympics, 世界杯, and 奥运. Business coverage of those events can be misclassified as international finance.

The current pull request also has no status checks because the daily workflow does not listen to `pull_request` events. This weakens the review path even though the local suite is comprehensive.

## Source replacement

Replace the inactive Reuters World entry with the public BBC Business RSS feed:

`https://feeds.bbci.co.uk/news/business/rss.xml`

The feed is directly accessible, returns RSS 2.0, includes publication dates, public article links, and non-empty excerpts, and works with the existing parser. It remains subject to the same 48-hour freshness rule, sports/lifestyle exclusions, politics-or-finance classification, topic deduplication, and conversion quality checks as every other international source. No article pages are fetched.

## Conversion-quality refill

Extend `Test-NewsArticleConversionComplete` so candidate acceptance checks the news-specific subset of the final publication contract:

- required article and bilingual fields are non-empty;
- `summarySource` is `deepseek` or `source_extract`;
- a source extract includes `sourceExcerpt`;
- the Simplified Chinese display title is predominantly Chinese;
- original, Chinese, and English highlights are no longer than 260 characters;
- original and Chinese highlights do not use forbidden template openings;
- summaries and analyses do not contain forbidden fallback text.

If any check fails, `Convert-NewsCandidateQuota` marks that URL unavailable and selects the next eligible candidate. Final payload validation remains authoritative and unchanged.

## Sports exclusions

Add precise English and Chinese event terms to the existing hard-exclusion pattern: World Cup, FIFA World Cup, Olympics/Olympic, 世界杯, 奥运, and 奥运会. Avoid generic words such as `match`, which have non-sports meanings and would create false positives.

## Pull-request validation

Add a `pull_request` trigger limited to relevant scripts, frontend files, workflow files, documentation, and published-data fixtures. Add a validation job that:

- checks out the pull-request commit;
- sets up Python 3.12 and installs the pinned PDF dependency;
- runs the ten PowerShell regression scripts and two Node tests;
- never invokes `scripts/update-daily.ps1` directly;
- never stages, commits, pushes, or writes published JSON.

Keep the existing scheduled/manual/main-push update job, but guard it so it does not run for pull requests. Give the validation job read-only repository permissions and retain write/model permissions only for the real update job.

## Test strategy

Follow red-green-refactor for each defect:

1. Add a source-contract assertion that rejects Reuters and requires BBC Business; observe failure, then update the feed list and documentation.
2. Add selector fixtures for World Cup/Olympics terms; observe selection failure, then extend the hard exclusions.
3. Add a conversion-refill fixture whose first candidate has invalid bilingual quality and whose second candidate is valid; observe that the invalid candidate is accepted or the batch aborts, then tighten the conversion predicate.
4. Add workflow assertions for a pull-request validation job, read-only permissions, all twelve tests, and an update-job PR guard; observe failure, then update the workflow.
5. Run all twelve tests, PowerShell AST checks, YAML parsing, workflow order checks, diff checks, and a clean-worktree check before pushing the updated branch.

## Out of scope

- Fetching full news article pages.
- Changing the 3 domestic / 2 international / 4 AI-or-paper quota.
- Adding a source-health database or monitoring service.
- Rewriting historical JSON archives or generating live daily data during verification.
