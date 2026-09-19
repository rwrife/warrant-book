# Privacy declarations (issue #7)

Warrant Book is local-first. It has **no accounts, no cloud backend,
no telemetry, no analytics, no ads, and no tracking** — see the
privacy contract in README.md. Everything below restates that in the
vocabulary the stores require; nothing adds a new behaviour.

## Google Play — Data safety form

Answers to submit in Play Console → App content → Data safety:

| Question | Answer |
|---|---|
| Does this app collect or share user data? | **No.** Warrant Book does not collect or share any user data. |
| Data collected | None. Purchase entries, coverage dates, notes, and receipt attachments are stored only in the app's private on-device database and files directory. |
| Data shared | None. There is no network code in the app; the only way data leaves the device is if the user exports a CSV/ZIP backup or shares an attachment through the OS share sheet, which is a user-initiated action outside the app. |
| Data encrypted in transit | N/A (no data transmitted). |
| Users can request data deletion | N/A (no data held). Users can erase all local data via Settings → Data & privacy → Erase all data. |
| Dangerous permissions | `POST_NOTIFICATIONS` — optional, requested only when the user enables expiry reminders; used solely to schedule local notifications. No location, camera, contacts, or microphone permissions are requested. Photo attachment uses the Android system photo picker (no `READ_MEDIA_IMAGES` grant is requested by the app). |
| Advertisements | No ads. |
| Data safety disclosures | No data sold, no data used for analytics, no account required. |

## Apple — App Store privacy "nutrition label"

Answers to submit in App Store Connect → App Privacy:

- **"Data Used to Track You":** None.
- **"Data Linked to You":** None.
- **"Data Not Linked to You":** None.
- Summary to publish: *“Warrant Book does not collect any data. All
  information you enter — purchases, warranty dates, notes, receipts —
  stays on your device. The app contains no tracking technologies, no
  third-party SDKs that collect data, and no network transmission of
  any user content.”*

App Store also requires the `NSPhotoLibraryUsageDescription`
purpose-string if photo picking were implemented through the photo
library API; Warrant Book uses the system picker instead, so no
additional usage descriptions beyond the notification prompt
(`NSUserNotificationsUsageDescription` — shown when the user enables
reminders) are needed.

## In-app statement

Settings → Data & privacy shows: “Your data never leaves this device
unless you export or share it yourself.” (verified by widget tests in
issue #6.)

## Permissions inventory (source of truth: manifests)

| Permission | Where | Why | When requested |
|---|---|---|---|
| `POST_NOTIFICATIONS` (Android) | `android/app/src/main/AndroidManifest.xml` | Schedule local expiry reminders | Only on explicit user opt-in (issue #5) |
| `RECEIVE_BOOT_COMPLETED` (Android) | same | Re-arm pending reminders after device reboot | Install-time; no personal data involved |
| Notifications (iOS) | `NSUserNotificationsUsageDescription` path via flutter_local_notifications | Same reminder feature | Only on explicit opt-in |
| Photo attachment | system photo picker / file picker (no dedicated permission declared) | Attach a receipt to one item | Per-action, user-driven |

No INTERNET permission is declared on Android, and the app contains no
HTTP/DNS/socket code, so a device firewall with the app blocked has no
observable effect.
