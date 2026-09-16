# Warrant Book — PLAN

## Scope

Warrant Book is a single-user, local-first mobile app that registers purchases, tracks coverage windows (return period, manufacturer warranty, extended warranty), and alerts before those windows expire. MVP is the full vertical slice: entry → storage → coverage computation → reminders → attachments → export/backup → packaging. Deliberately excluded: email receipt parsing, cloud sync, accounts, price tracking, OCR/barcode, and legal-right advice (see README non-goals).

## Architecture

```
lib/
  main.dart                 # app bootstrap, theme, routing
  domain/                   # pure Dart models + coverage-status logic (no Flutter deps)
    models/                 # PurchaseItem, CoverageLine, Note, AttachmentRef
    coverage.dart           # window status math (active/expiring/expired), date math
    validation.dart         # field rules, currency handling
  data/                     # persistence
    db/                     # Drift (SQLite) tables, DAOs, migrations
    documents/              # app-private attachment store (photos/PDFs), hashing, deletion
    repositories/           # repository impls bridging domain <-> data
  features/                 # feature-first UI slices
    items/                  # list views (coverage now, expiring soon, archive), search/filter
    item_detail/            # detail, notes timeline, attachments, coverage editor
    add_edit/               # add/edit forms with date+duration helpers
    reminders/              # notification scheduling + settings
    backup/                 # CSV export, ZIP backup, restore, erase-all
  l10n/                     # internationalization scaffolding (strings only for MVP)
test/                       # unit + widget tests mirroring lib/
integration_test/           # end-to-end add->alert->export flow (post-M2)
```

### Technology choices

| Choice | Rationale |
|---|---|
| Flutter + Dart (Android & iOS) | One codebase for the two mainstream mobile platforms; strong local-notification and file-picker ecosystems; matches other tool-lab lifestyle apps (kit-check, cutting-log, tail-tally) so tooling and CI patterns are reusable. |
| Drift (SQLite) | Typed, transactional, migration-friendly local SQL; file is portable inside ZIP backups; no cloud dependency. |
| `flutter_local_notifications` + `timezone` | Device-side reminder scheduling without any push service; degrades gracefully when notifications denied. |
| `image_picker` / `file_picker` | Attach receipts from camera, gallery, or files only on explicit user action. |
| `share_plus` + `path_provider` | User-initiated CSV export, ZIP backup/restore, and single-document sharing via OS share sheet. |
| No backend at all | Local-first is the product promise; removes hosting, auth, and privacy surface entirely. |

### Key domain rules

- A coverage line is `(kind, basis)` where basis is either `duration_from_purchase` (e.g., 24 months) or `explicit_end_date`. Status is computed against today's date: `active`, `expiring` (within user horizon), `expired`.
- Item status = max severity across its lines. Items with no coverage lines are allowed (plain registry).
- Purchase date is required; price/currency optional; unknown-vs-missing is modeled explicitly (missing ≠ zero).
- Reminder rules are per-item-with-defaults: which line kinds to watch, days-before (default 30 & 7), once vs. repeat. All scheduling recomputed from the database on app start and after edits to survive OS-schedule caps.

## Milestones & dependency order

1. **M1 Skeleton + data layer** — Flutter workspace, CI (analyze/test/build), Drift schema (items, coverage_lines, notes, attachments), repository interfaces, domain coverage math with exhaustive unit tests. *(Depends on: nothing)*
2. **M2 Core workflow UI** — add/edit form, coverage-now list, detail view, search. First end-to-end user-visible value. *(Depends on M1)*
3. **M3 Reminders** ✅ — notification permission flow, serialized scheduler recomputation, per-item settings, notification routing, and expiring-soon list. *(Depends on M2)*
4. **M4 Attachments + backup** — receipt capture/storage/preview/deletion, CSV export, versioned ZIP backup + restore, erase-all. *(Depends on M2; restore also depends on M1 schema versioning)*
5. **M5 Packaging + polish** — accessibility pass, app icons/splash, signed debug + release APK, iOS build + TestFlight candidate, store-listing text, privacy label documenting zero data collection. *(Depends on M2–M4)*

## Testing strategy

- **Unit (domain):** date math across month/year boundaries, leap days, duration-vs-explicit bases, timezone/day-boundary behavior, currency rounding, validation. Property-style tests for status monotonicity (an active line cannot become active again after expiring for a fixed date).
- **Unit (data):** Drift migrations forward/back-guard, repository CRUD, cascade delete of notes/attachments, ZIP backup round-trip byte-logic.
- **Widget tests:** add→list→detail flow, expiring-soon filtering, reminder settings persistence, attachment lifecycle, restore-from-backup with confirmation dialog.
- **Integration (post-M2):** full vertical flow on emulator: create item with coverage, verify scheduled reminders exist (queried via plugin test hook), export CSV, wipe, restore.
- **CI gates:** `flutter analyze` clean, `flutter test` green, debug builds for Android (APK artifact) and iOS (simulator build) on every PR. Reminder firing on real devices is verified manually and documented per device — emulator-only tests are labeled as such.

## Packaging / distribution

- **Android:** signed release APK published on GitHub Releases; optional Play Store closed track later. Versioning via `pubspec.yaml` + CI-injected build numbers.
- **iOS:** unsigned simulator builds in CI; release builds require Apple developer account (user-provided, out-of-repo signing secrets). Not claimed until actually produced.
- No telemetry, no third-party SDKs with data collection — Google Play Data-Safety form and Apple privacy nutrition labels will state "data not collected."

## Risks

| Risk | Mitigation |
|---|---|
| OS notification-schedule limits and aggressive battery managers drop reminders | Recompute full schedule on app start/edit from DB; document OEM battery-exception caveats; treat notifications as advisory, list is source of truth. |
| Date/duration math errors mislead on coverage | Exhaustive pure-Dart unit tests + property tests; coverage math isolated in dependency-free `domain/`. |
| Attachment store bloat / orphaned files | Size warning thresholds, cascade deletion on item delete, backup-integrity check on restore, orphan sweep command in backup feature. |
| iOS signing unavailable in headless CI | Scope iOS CI to simulator builds only; real signing documented as owner task. |
| Scope creep toward email parsing / sync | Hard non-goals in README; any expansion requires a new issue with explicit re-scope. |

## Explicit non-goals

(As README.) No cloud sync/accounts, no email inbox parsing, no OCR/barcode in MVP, no price/coupon tracking, no legal warranty-rights advice, no multi-device realtime collaboration, no web backend.
