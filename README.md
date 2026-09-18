# Warrant Book

**Pitch:** Local-first mobile app that registers purchases with receipts, tracks warranty and return windows, and alerts before coverage expires — no accounts, no cloud.

## Overview

Warrant Book is a personal purchase registry. When you buy something — an appliance, gadget, tool, or furniture — you record it once: what it was, where and when you bought it, what it cost, how long the warranty and return window run, and (optionally) a photo or PDF of the receipt. Warrant Book then keeps the calendar for you: it surfaces items still under coverage, warns before a return window closes, and alerts before a warranty expires, so warranty claims and returns stop being things you only remember too late.

Everything lives on your device. No account, no server, no subscription.

## Motivation

Paper receipts fade, emails get buried, and warranty terms are impossible to look up when a device fails eleven months in. Existing "warranty tracker" products are cloud-account services that want your email and payment data, and generic reminder apps don't model purchase coverage windows (return period vs. manufacturer warranty vs. extended warranty) at all. People lose money on expired-return purchases and unclaimed warranty repairs simply because the information was disorganized.

## Target users

- Adults who buy appliances, electronics, tools, or furniture and want one place to answer "is this still under warranty?"
- Households that split shopping between people and need a shared, exportable record without a third-party account.
- Privacy-conscious users who refuse to link email inboxes or store cards to a tracker.

## Concrete use cases

1. **Return-window save:** You buy a monitor with a 30-day return window. Warrant Book shows it in a "return window open" list and sends a gentle reminder 5 days before it closes.
2. **Warranty claim:** A drill fails at 14 months. You open Warrant Book, find the purchase, and instantly have the store, date, price, warranty end date, and the stored receipt photo to attach to the claim.
3. **Extended-warranty decision:** Before buying a store extended warranty, you check how long the included manufacturer warranty ends — Warrant Book shows the remaining coverage and lets you compare the extension's added cost/value note.
4. **Insurance / resale evidence:** Export a CSV or full backup of your purchase history when filing a home-insurance claim or proving ownership when selling an item.

## How to use (intended end-to-end workflow)

1. Install the app; grant no mandatory permissions. Optionally allow notifications for reminders.
2. Add an item: name, category, store/seller, purchase date, price and currency (optional), coverage lines (return window, manufacturer warranty, extended warranty — each with duration or end date), and attach a receipt photo or PDF from the gallery/files (optional).
3. Browse views: **Coverage now** (active windows), **Expiring soon** (configurable 7/14/30-day horizon), **Archive** (expired/disposed items).
4. Tap an item for full detail, attached documents, and a notes timeline (e.g., "repair submitted 3 May, RMA 12345").
5. Enable optional local reminders, then set per-item lead days, scheduling horizon, and coverage-line kinds to watch.
6. Export anytime: CSV for spreadsheets, or a versioned ZIP backup containing the database plus all attached documents. Restore from that backup on a new device.

## MVP feature list

- Local item registry with purchase fields, categories, and free-text notes.
- Multiple coverage lines per item (return, manufacturer, extended), each with computed status (active / expiring / expired) and end date derived from purchase date + duration, or explicit end date.
- Attached receipt images/PDFs stored app-private; inline preview.
- "Coverage now" and "Expiring soon" lists plus search and category filter.
- Local notifications for expiring windows, per-item configurable, default off until user opts in.
- CSV export and versioned ZIP backup/restore; full data deletion.
- Accessibility: dynamic type, screen-reader labels on all list/detail/entry controls, sufficient contrast.

### Non-goals

- No email parsing, receipt scraping, store-account linking, or payment/card integration.
- No cloud sync, accounts, analytics, or third-party servers.
- No price tracking, coupon hunting, or shopping recommendations.
- No legal advice about warranty rights; the app only records dates the user enters.
- No shared/multi-user realtime collaboration in MVP (household sharing is via export/restore or a later local-share feature).
- No barcode/OCR auto-fill in MVP (candidate post-MVP enhancement).

## Privacy, permissions, and data storage

- **Data storage:** All items, notes, and attachments are stored in an app-private SQLite database and an app-private attachment directory on the device (receipt files are named by their SHA-256 content hash). Backups and CSV exports the user creates land in the app's documents directory. Nothing leaves the device unless the user explicitly exports a file or shares a single document via the OS share sheet.
- **Permissions:** Notifications (Android `POST_NOTIFICATIONS`, optional, only if reminders are enabled; plus boot-restart for scheduled reminders). Receipt attach opens the platform photo picker (Android Photo Picker / iOS PHPicker — no standing gallery permission) or the system file picker for PDFs; no camera, location, contacts, calendar, or microphone access.
- **Telemetry:** None. No analytics or crash-reporting SDKs that exfiltrate content.
- **Deletion:** Per-item delete removes database rows and sweeps unreferenced attachment files (with a tested orphan sweep). "Erase all data" cancels every scheduled notification, then wipes the database, attachment files, and stored preferences.
- **Encryption:** Relies on OS-managed device encryption; no extra key management in MVP.

## Current status and milestones

**Status: M4 complete.** Attachments (photo/PDF, content-hash storage, inline preview, orphan-free cleanup), CSV export via the share sheet, versioned ZIP backup/restore (manifest + SHA-256 integrity, future-version refusal, destructive-overwrite confirmation, reminder re-schedule on restore), and erase-all are implemented.

- M0 — Documentation & backlog ✅
- M1 — Project skeleton, CI, and local data layer ✅
- M2 — Core registry workflow (add / browse / detail) ✅
- M3 — Coverage math, reminders, and accessible lists ✅
- M4 — Attachments, export/backup/restore, privacy controls ✅
- M5 — Packaging (Android APK / iOS TestFlight candidate), docs, release

## Development quickstart

Requirements: Flutter 3.47.x stable (Dart 3.13+); Android builds need JDK 17 and the Android SDK; iOS builds need Xcode on macOS.

```bash
flutter pub get      # fetch dependencies (runs l10n generation)
flutter analyze      # static analysis — must stay at zero issues
flutter test         # unit + widget tests
flutter run          # run on a connected device or emulator
```

Building the debug app manually:

```bash
flutter build apk --debug              # Android debug APK
flutter build ios --simulator --debug  # iOS simulator build (macOS)
```

CI (GitHub Actions, on every PR and push to `main`): `flutter analyze`, `flutter test`, an Android debug APK build (uploaded as an artifact), and an iOS simulator build. See `.github/workflows/ci.yml`.

See `PLAN.md` for architecture, milestones, testing, packaging, and risks.
Reminder behavior, permissions, platform setup, and rolling OS limits are documented in [`docs/reminders.md`](docs/reminders.md).

## License

MIT — see `LICENSE`.
