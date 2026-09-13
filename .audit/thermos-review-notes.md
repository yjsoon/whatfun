# Thermos review notes

Started: 2026-09-13 (cloud agent on `main` @ `1afd876`)
Branch: `cursor/thermos-review-a77b`

## Scope

Working tree was clean on `main`. No uncommitted diff vs `origin/main`.

Chose **merged PR #10** as the review target (latest substantial code change), plus a glance at **PR #11** (CI-only).

- PR #10: https://github.com/yjsoon/entertainment-value/pull/10
  - Title: `fix(security): close non-HTTP fetches and narrow SwiftData reads`
  - Range: `ee95ad9..deec7a4`
  - 34 files, +558 / -178
- PR #11: https://github.com/yjsoon/entertainment-value/pull/11
  - 1 file: `.github/workflows/claude-code-review.yml` (+3)

Full PR10 diff: `/tmp/thermos/pr10.diff` (1414 lines)

## File sizes (post-PR10)

| File | Lines | Note |
| --- | --- | --- |
| SwiftDataArchiveBridge.swift | 1786 | already over 1k; PR only ±8 |
| StagedImportApplier.swift | 1184 | already over 1k |
| SearchView.swift | 995 | was 987, now one shy of 1k |
| ItemDetailView.swift | 865 | tiny change |
| HomeView.swift | 855 | was 863 (net shrink) |
| ItemEditorView.swift | 658 | was 630 |
| MaintenanceScheduler.swift | 79 | was 70; lock rewrite |

## Units in PR10 (from `.audit/mobile-hardening.tsv`)

1. `RemoteHTTPURL` shared parse; close fetch + persist that accepted file URLs
2. Predicate fetches for Media Value / Settings / Search
3. CoverArtworkView keep-last-image
4. Sensitive podcast feed privacy (`isSensitive`)
5. `setTitle` keeps custom `sortTitle`
6. Trash writes behind restore gate; trash/archive queries by predicate
7. Home rails partitioned once
8. Exclusive restore-gate with waiter handoff
9. Cover keep-last on failed decode; `parsePublic` on attribution Links; episode webpages through `parsePublic`

Skipped (stated): rewrite of 1782-line archive bridge; Keychain accessibility on update.

## PR11

Lets `cursor[bot]` trigger Claude review. Out of thermos correctness scope except as a CI privilege change.

## Candidate findings (parent, pre-subagent)

These are hypotheses for the reviewers to confirm or kill. Not a verdict yet.

### Correctness / security

1. **Ungated trash restore vs exclusive restore gate.** `TrashViews` put `purgeExpired` and `deletePermanently` behind `withRestoreGate`, but `restore(item)` / `restore(list)` still `modelContext.save()` immediately. Archive restore is also ungated. The scheduler comment says a mid-restore save can commit a half-wiped graph. Import/replace-all holds the gate across credential I/O; a Recently Deleted restore during that window is the same hazard class as the ungated purge they just fixed.

2. **Continuation lock has no cancellation handler.** `acquireExclusiveSlot` uses `withCheckedContinuation` and parks waiters in `exclusiveWaiters`. If a gated `Task` is cancelled while waiting, the continuation is not removed. A later `releaseExclusiveSlot` can resume a dead waiter and leave `isGateHeld == true` (or skip a live waiter). Tests never cancel.

3. **`waitForIdle` ignores the exclusive gate.** Callers waiting for "idle" can return while a restore/purge still owns the slot. Only tests use it today.

4. **Public feed refresh uses `parse`, not `parsePublic`.** `PodcastFeedSyncService` public branch: `RemoteHTTPURL.parse(value)`. RSS client is `secretless()`, so disk URLCache is probably fine. Still allows userinfo on a "public" stored URL if classification was skipped (grandfathered).

5. **Grandfathered file feeds persist.** `validateDraftURLs` / `reconcilePodcastFeed` keep existing non-HTTP feed strings. Stated intent. Refresh then throws `missingFeed`. Confirm this is not a silent fetch.

6. **`PodcastFeedPrivacy.isSensitive` treats `URLComponents` failure as sensitive** (`return true`). Good. Query names include `code`, `key` — Apple/CDN URLs with those names get Keychained. Possible over-private, not a leak.

7. **Restore of attribution URLs now drops non-public HTTP.** `SwiftDataArchiveBridge` filters attribution through `parsePublic`. A legitimate `http://` attribution with userinfo is dropped (text remains). File attributions become un-tappable text. Intended.

8. **Cover catch-on-error sets `didFail` but does not clear `image` for the same asset.** Placeholder `wifi.slash` sits under the still-visible last image. Probably OK. Cancellation after clearing for a *new* asset can flash empty.

9. **`TrashPurgeService.purgeExpired` still filters `purgeAfter` in memory** after fetching all trashed rows. Predicate narrowed `trashedAt` only. Not a security bug; leftover full-trash scan.

10. **Search still `@Query`s every non-trashed item.** Filter only dropped trash. SearchView is 995 lines (was 987).

11. **PR #11 CI:** `cursor[bot]` can trigger Claude review. Privilege expansion on GitHub Actions. Out of app correctness; note as CI trust.

### Code quality

- `SearchView.swift` 987 → 995, one shy of the 1k rule.
- `SwiftDataArchiveBridge` 1786, `StagedImportApplier` 1184 already over 1k; PR added branches to both.
- `PodcastFeedPrivacy` split from import helper is the right judo. `MetadataLibraryInserter` still manually restores `sortTitle` after `setTitle` already preserves custom keys — possible redundant branch.
- `MaintenanceScheduler` exclusive-slot + waiter handoff + pending replay is a small state machine with comments carrying the invariant. Cancellation and nested-gate absence are implicit.
- Home rail partition extracted; good. `visibleItems` still computed per body plus `HomeRails.partition`.
- Artwork cache path still `WhatFun` — not in this diff.

## Independent verification (parent, while subagents run)

### Restore-gate completeness

`ImportExportView.performRestore` holds `withRestoreGate` across coordinator restore and credential I/O. The form is `.disabled(isWorking)` with an overlay, but that disable is on Import & Export only. Navigation back to Settings → Recently Deleted is still plausible mid-restore.

Recently Deleted:
- `purgeExpired` and `deletePermanently` take the gate (this PR).
- `restore(item)` / `restore(list)` / Archived `restore` do not.
- `recoverFromTrash` is a synchronous `modelContext.save()` in `ActivityService`.

Same hazard class the exclusive lock was rewritten to close. Reachability is the question: not the happy path, but the lock's whole purpose is the unhappy path.

Cancellation on `exclusiveWaiters`: no `withTaskCancellationHandler`. A cancelled waiter stays parked until the holder resumes it, then still runs `operation()`. Unlikely deadlock; possible post-cancel mutation. Tests never cancel.

Handoff itself looks correct on MainActor: holder leaves `isGateHeld == true` and resumes the next waiter.

### URL enforcement on touched fetch/persist paths

| Boundary | Rule used | Notes |
| --- | --- | --- |
| HTTPClient.send | parse | All metadata/RSS go through `secretless()` — no disk URLCache |
| ArtworkRepository.data | parsePublic | Then `session.data(from:)` on `.shared` |
| CoverArtworkView | parsePublic | File covers fail locally, `didFail` if remoteURLString set |
| RSSPodcastFeedClient.refresh | parse | Duplicate of HTTPClient guard |
| PodcastFeedSyncService feed URL | parse | Public and private |
| Episode webpage / image persist | parsePublic | Tested for file webpage |
| ItemEditor cover persist | parsePublic | Grandfather existing |
| ItemEditor feed persist | parse + isSensitive | File grandfather via `existing != nil` |
| Attribution Link / archive restore | parsePublic | Drops non-public from restored attribution URLs |
| Apple feedURL mapping | metadataFeedURL = parse | Userinfo feeds still discovered, then classify() Keychains them |
| StagedImport feed | parse | isSensitive → Keychain |
| safePublicURL | parsePublic + isSensitive | |

Untouched in this PR (out of scope unless a changed caller uses them): `PodcastFeedParser.resolveURL` still `URL(string:relativeTo:)`. Persist path now filters.

HTTP to RFC1918 is explicitly allowed (`RemoteHTTPURLTests` accepts `http://192.168.1.10:8000/rss`). Local-network podcasts. Not a finding.

### sortTitle

`setTitle` only copies into `sortTitle` when they still match. Tests cover default rename and custom key. `MetadataLibraryInserter.mergeDetails` still snapshots and restores `sortTitle` after `setTitle` — redundant after the Bugbot autofix, not wrong.

### Cover

Same-asset reloads keep `image`. Failed decode keeps last image unless none exists. Cancellation swallows. New-asset still clears. Size 0/missing asset still clears (layout collapse flash).

Error path sets `didFail` without clearing same-asset `image`, so `wifi.slash` sits under the last cover.

### Subagents

Launched:
- thermo-nuclear-review-subagent `bc-0d4032d4-2a5d-5fd0-b88a-22ce9a6e06eb`
- thermo-nuclear-code-quality-review-subagent `bc-1cbc9814-eeb6-5ba2-b3d0-1a8c3285a625`

Waiting on both before the unified verdict.
