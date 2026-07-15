# B Motion and Source Highlights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the user-selected B homepage motion, remove redundant interface copy, merge article detail content, and show a source-grounded one-sentence highlight beneath every category title without weakening the existing full summaries.

**Architecture:** Keep `summary` as the long-form detail field and add `highlight` as a separate list-only field. Put legacy fallback selection in the pure `SiteCore` module, put generation and validation in the existing PowerShell daily-update pipeline, and put the approved B timing in a small testable `motion-core.js` model consumed by `app.js`. Preserve the hash router, existing JSON files, 08:00/09:00 recovery flow, bilingual behavior, and no-build GitHub Pages deployment.

**Tech Stack:** HTML, CSS, vanilla JavaScript, Node.js contract tests, PowerShell data-generation tests, GitHub Actions, GitHub Pages.

## Global Constraints

- B uses one cancelable `requestAnimationFrame` scene controller with a `1150ms` transition; do not combine it with CSS scroll snap.
- The title fully fades and flies to `-38vh`; cards enter from `34vh` with staggered saturation and blur recovery.
- Delete “异闻、机巧与格物，藏入每日七篇。”, category kickers, “启封细读”, detail pagination, and the split detail pages.
- `highlight` is list-only; `summary` remains the complete detail summary.
- Chinese highlights target 25–55 Han characters; English highlights target 12–30 words and both render in at most two visual lines.
- Reject template openings including “本文介绍”, “文章指出”, “值得阅读”, and “这篇论文提出”.
- DeepSeek failure must produce a traceable source sentence; old archives without `highlight` must remain usable through a frontend fallback.
- 08:00 generation, 09:00 recovery, and degraded-summary upgrades must all preserve and validate highlights.
- Keep reduced-motion, keyboard navigation, safe outbound links, bilingual UI, archives, and local font fallbacks.

---

### Task 1: Pure highlight and motion models

**Files:**
- Create: `motion-core.js`
- Modify: `site-core.js`
- Modify: `scripts/test-site-core.js`
- Create: `scripts/test-motion-core.js`

**Interfaces:**
- `SiteCore.getArticleHighlight(article, language): string` returns `localized.highlight` or a cleaned first sentence from `localized.summary`.
- `MotionCore.heroFrame(progress): { opacity, yVh, scale, blurPx }` returns the approved title frame.
- `MotionCore.cardFrame(progress, index): { opacity, yVh, scale, saturation, blurPx }` returns a staggered card frame.
- `MotionCore.durationMs` is exactly `1150`.

- [ ] **Step 1: Write failing highlight tests**

Add assertions proving an explicit bilingual `highlight` wins, a legacy summary falls back to its first meaningful sentence, and template openings are removed rather than displayed.

```js
assert.equal(core.getArticleHighlight({ highlight: "来源摘句", summary: "完整摘要。" }, "zh"), "来源摘句");
assert.equal(core.getArticleHighlight({ summary: "文章指出，边境之外仍在寻找更快路径。第二句。" }, "zh"), "边境之外仍在寻找更快路径。");
assert.equal(core.getArticleHighlight({ highlight: "中文", translations: { en: { highlight: "The original sentence remains intact." } } }, "en"), "The original sentence remains intact.");
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `node scripts/test-site-core.js`

Expected: FAIL because `getArticleHighlight` does not exist.

- [ ] **Step 3: Implement the minimal highlight selector**

Add sentence splitting, template-prefix removal, whitespace normalization, and a bounded fallback in `site-core.js`; export `getArticleHighlight` without changing `getLocalizedArticle`.

- [ ] **Step 4: Write and verify RED motion tests**

Create tests for `durationMs === 1150`, title completion at progress `0.46`, card saturation reaching `1`, later cards starting after earlier cards, and all outputs staying finite and bounded.

Run: `node scripts/test-motion-core.js`

Expected: FAIL because `motion-core.js` does not exist.

- [ ] **Step 5: Implement the minimal UMD motion model and verify GREEN**

Use the approved V2 formulas: title progress `0..0.46`, `yVh 0..-38`, `scale 1..0.93`, `blur 0..4`; card index start `0.28 + 0.075 * index`, end `0.79 + 0.08 * index`, `yVh 34..0`, `scale 0.94..1`, `saturation 0.08..1`, `blur 5..0`.

Run: `node scripts/test-site-core.js; node scripts/test-motion-core.js`

Expected: both scripts print their passing messages and exit 0.

- [ ] **Step 6: Commit the pure models**

```powershell
git add site-core.js motion-core.js scripts/test-site-core.js scripts/test-motion-core.js
git commit -m "feat: add source highlight and motion models"
```

### Task 2: Daily highlight generation and validation

**Files:**
- Modify: `scripts/daily-update-support.ps1`
- Modify: `scripts/update-daily.ps1`
- Modify: `scripts/test-daily-update-support.ps1`
- Modify: `scripts/test-update-daily-rules.ps1`

**Interfaces:**
- `Get-SourceHighlight -Text <string>` returns one traceable, independently readable source sentence.
- `New-ArticleAnalysis` returns `highlight` and `translations.en.highlight` alongside existing fields.
- `Assert-DailyPayload` rejects missing, template-style, or implausibly long new highlights.
- `Update-DegradedPayload` copies new highlight fields without changing article selection or fingerprint.

- [ ] **Step 1: Write failing fallback-generation tests**

Assert that `Get-SourceHighlight` selects the first complete usable sentence, skips feed/navigation fragments, and `New-SourceExtractAnalysis` supplies both highlight fields.

- [ ] **Step 2: Run fallback tests and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-daily-update-support.ps1`

Expected: FAIL because the highlight helper and fields are absent.

- [ ] **Step 3: Implement source-grounded fallback**

Add `Get-SourceHighlight`, reuse it from `New-SourceExtractAnalysis`, and copy highlights during `Update-DegradedPayload`. The English fallback must preserve the traceable source sentence rather than inventing a translation while DeepSeek is unavailable.

- [ ] **Step 4: Write failing DeepSeek-contract and payload tests**

Extend the strict JSON contract to require top-level `highlight` and `translations.en.highlight`. Extend `New-TestArticle` with valid highlights; add rejection cases for empty highlights and template openings.

- [ ] **Step 5: Run update rules and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1`

Expected: FAIL until prompt parsing, result propagation, and validation use the new fields.

- [ ] **Step 6: Implement generation, parsing, propagation, and validation**

Request one 25–55-character faithful Chinese source rendering and one 12–30-word English original/translation. Add fields to every article construction path and degraded upgrade path. Validate non-empty fields and reject the four forbidden template openings without altering fingerprint computation.

- [ ] **Step 7: Verify GREEN and commit**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-daily-update-support.ps1`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-update-daily-rules.ps1`

Expected: both suites pass.

```powershell
git add scripts/daily-update-support.ps1 scripts/update-daily.ps1 scripts/test-daily-update-support.ps1 scripts/test-update-daily-rules.ps1
git commit -m "feat: generate source-grounded article highlights"
```

### Task 3: Production interface simplification and B motion

**Files:**
- Modify: `index.html`
- Modify: `app.js`
- Modify: `styles.css`
- Modify: `scripts/sync-public.ps1`
- Modify: `scripts/test-app-contract.ps1`
- Modify: `scripts/test-visual-contract.ps1`
- Modify: `scripts/test-site-shell.ps1`
- Add: `assets/fonts/lxgw-wenkai-screen.css`
- Add: `assets/fonts/lxgwwenkaigbscreen-subset-*.woff2` (the complete 97-file subset set referenced by the pinned local CSS)

**Interfaces:**
- `app.js` calls `SiteCore.getArticleHighlight(article, state.language)` for index-card copy.
- `app.js` calls `MotionCore.heroFrame` and `MotionCore.cardFrame` only inside one cancelable scene controller.
- Article detail uses one `.detail-content` section containing summary, associations, and source actions.

- [ ] **Step 1: Write failing structural and visual contracts**

Require `motion-core.js`, local font CSS, `getArticleHighlight`, the single cancelable RAF controller, B duration, merged detail DOM, and the absence of the subtitle, kickers, “启封细读”, `setDetailPage`, hidden detail pages, and CSS scroll snap.

- [ ] **Step 2: Run frontend contracts and verify RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-app-contract.ps1`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-visual-contract.ps1`

Expected: both fail on the old structure.

- [ ] **Step 3: Implement semantic simplification**

Remove the hero subtitle, card and category kickers, browse heading copy, index CTA, detail pagination/progress, and duplicate illustration. Render one asymmetrical detail grid with the summary at roughly 58% and associations/actions at roughly 42%; stack naturally on mobile.

- [ ] **Step 4: Implement the approved motion controller**

Load `motion-core.js` before `app.js`. One wheel gesture, touch swipe, keyboard PageDown/Space, or entry control calls `animateHomeScene(1)`. Start by cancelling the previous RAF; update title and cards from the pure model; finish in the fully clickable themes scene. Support reverse navigation and immediately show the complete themes scene under `prefers-reduced-motion: reduce`.

- [ ] **Step 5: Install the local screen-reading font and finish responsive CSS**

Use LXGW WenKai Screen only for body/supporting copy with `font-display: swap`; keep the Song/Ming display stack for large titles. Ensure highlight copy is two lines, category headings are simplified, and mobile has no clipped title or inaccessible controls.

- [ ] **Step 6: Verify GREEN and commit**

Run all Node and frontend PowerShell contract tests. Expected: every suite exits 0.

```powershell
git add index.html app.js site-core.js motion-core.js styles.css assets/fonts scripts/sync-public.ps1 scripts/test-app-contract.ps1 scripts/test-visual-contract.ps1 scripts/test-site-shell.ps1
git commit -m "feat: ship selected immersive reading interface"
```

### Task 4: Backfill the current issue and verify bilingual legacy behavior

**Files:**
- Modify: `data/articles.json`
- Modify: `data/archive/2026-07-14.json`
- Modify: `scripts/test-frontend-language.js`
- Modify: `scripts/test-site-core.js`

**Interfaces:**
- Each current article has top-level `highlight` and `translations.en.highlight`.
- Current live and same-day archive JSON remain byte-equivalent after serialization.
- Legacy archives deliberately remain without the field and use `SiteCore.getArticleHighlight` fallback.

- [ ] **Step 1: Write failing bilingual data tests**

Require seven non-empty highlights, reject the four template openings, verify Chinese/English localization, and assert a legacy fixture still produces a usable first sentence.

- [ ] **Step 2: Run tests and verify RED**

Run: `node scripts/test-frontend-language.js`

Expected: FAIL because current data lacks `highlight`.

- [ ] **Step 3: Add seven source-grounded bilingual highlights**

Derive each English line from `sourceExcerpt`; write a faithful concise Chinese rendering. Keep `summary`, `failureAnalysis`, URLs, article order, and `contentFingerprint` unchanged because selection has not changed.

- [ ] **Step 4: Verify current and archive data**

Run frontend language, site-core, daily update, and JSON parse checks. Compare `data/articles.json` with `data/archive/2026-07-14.json` structurally.

- [ ] **Step 5: Commit current content migration**

```powershell
git add data/articles.json data/archive/2026-07-14.json scripts/test-frontend-language.js scripts/test-site-core.js
git commit -m "content: add source highlights to current issue"
```

### Task 5: Full regression, dynamic preview, and release

**Files:**
- Generated/ignored: `public/`
- No production source changes unless a failing check identifies a scoped defect.

**Interfaces:**
- Local root and `public/` serve the same app and data.
- GitHub Pages main branch contains all committed source changes.

- [ ] **Step 1: Run the complete regression suite**

Run every `scripts/test-*.js` with Node and every `scripts/test-*.ps1` with PowerShell. Run PowerShell AST parsing for changed scripts and `git diff --check`.

- [ ] **Step 2: Sync and verify the deployment folder**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-public.ps1`

Expected: “Synced public website folder.” Then compare the root/public frontend files and data hashes.

- [ ] **Step 3: Start local preview and inspect desktop/mobile**

Verify the B animation, no jitter under repeated wheel input, deleted copy, seven highlights, bilingual switch, merged detail, reduced motion, legacy archive fallback, and 390px mobile layout. Save a visual screenshot or leave the live preview open for user review.

- [ ] **Step 4: Review commit scope and push**

Confirm unrelated `scripts/start-web-server.ps1`, `scripts/edit_template.py`, and the pre-existing untracked redesign plan were never staged. Push `main` only after all checks pass.

- [ ] **Step 5: Verify GitHub Pages**

Open the deployed URL without cache, verify the current issue and one legacy archive, and confirm the published HTML references `motion-core.js` and the local font assets.
