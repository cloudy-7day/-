# Article Library Rebuild Design

## Context

The visible library contains 63 archived rows. Every row lacks a Simplified Chinese title translation, 35 rows reuse an exact URL, and the files named 2026-07-08, 2026-07-10, and 2026-07-11 contain copied 2026-07-12 payloads. The UI therefore falls back to English source titles in Chinese mode and exposes repeated or placeholder content.

## Chosen approach

Reset the visible library and start a new issue today. Before deleting the old payloads, persist only their canonical URL and normalized-title identities in `data/seen-articles.json`. This tombstone ledger is not displayed, but prevents any removed article from returning.

Alternatives rejected:

- Rebuild every historical date: this would create synthetic history and spend generation time on content users already asked to remove.
- Replace only today's issue: broken archives and their duplicates would remain reachable.

## Data contract

Each published article keeps the source title at top level for traceability and must include complete `translations.zh` and `translations.en` objects. Both translations require `title`, `highlight`, `summary`, and `failureAnalysis`; papers also require a localized `paperCard`. Chinese titles must contain at least one Han character. Highlights must be source-grounded and may not use template openings.

`data/seen-articles.json` contains versioned canonical URL and normalized-title arrays. Canonicalization lowercases scheme/host, removes fragments and tracking parameters, normalizes the path, and sorts remaining query parameters.

## Selection and duplicate prevention

Candidates are rejected before analysis when their canonical URL or normalized title appears in the tombstone ledger. A second pass removes duplicates within the candidate pool. The final seven items are rejected if any pair has an equal URL/title identity or a high title-token containment score, which catches different headlines describing the same event.

The published mix remains exactly three international items, two AI items, and two open papers. If two qualifying papers cannot be found, existing AI shortfall behavior remains available, but the preferred rebuilt issue is 3/2/2.

## Failure behavior

Publishing is fail-closed. Missing Chinese translations, English-only Chinese titles, duplicate identities, ledger collisions, malformed URLs, or invalid category counts stop the write and leave the previous payload intact. The 09:00 recovery run sees no valid changed issue and retries generation.

## Reset and release

The reset script first derives the tombstone ledger from every current and archived article, then removes all dated archive payloads and creates an empty archive index. A forced generation produces a new seven-item issue, validates it, archives it under today's date, and synchronizes the visual site. Local and live pages are checked in both languages before release.
