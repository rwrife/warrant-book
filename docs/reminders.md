# Local expiry reminders

Warrant Book schedules notifications entirely on the device. There is no account, telemetry, push provider, or backend. Notifications are advisory: the coverage dates and in-app lists, which are recomputed from the local SQLite database, are always the source of truth.

## Permission and controls

Reminders default to off. Startup, resume, recomputation, and ordinary registry use only check current notification access; they never display the OS permission prompt. The prompt is reached only from the user's action to turn on **Expiry reminders** in Settings. If access is denied initially, reminders remain off. If access is later revoked in system settings, scheduling stops while the user's prior enable intent is retained. Returning to the app after regranting access resumes that intent automatically, without another prompt. Settings reports both denial and the latest notification setup or scheduling failure; the latter clears after a successful rebuild.

Global defaults are 30 and 7 days before an ending coverage line, with a rolling 365-day coverage-end horizon. The Settings dialog persists both values. Each item can override the lead days and horizon, turn its reminders off, and independently watch or ignore return windows, manufacturer warranties, and extended warranties. Removing an item also removes its saved override.

## Scheduling behavior

The scheduler rebuilds the complete upcoming set from the database:

- at app startup when reminders are enabled;
- after every successful aggregate save (including edits, notes, and archive changes);
- after every deletion;
- whenever the app resumes (after refreshing OS permission and the device IANA timezone); and
- through `ReminderScheduler.afterRestore()`, the public hook intended for the M4 restore implementation.

Rebuilds are serialized so overlapping lifecycle and CRUD events cannot interleave cancellation and scheduling. A notification-plugin or permission-channel error is recorded by the reminder service but does not roll back or fail a successful database save/delete.

Coverage remains inclusive through its end date. While the app is foregrounded, its production calendar day advances at local midnight; resume also refreshes the day immediately. Candidate dates use the domain's timezone-free `DayDate` calendar math. Before every rebuild, the platform boundary refreshes the device's current IANA timezone through `flutter_timezone`; each candidate then becomes 9:00 AM in that zone and is scheduled with `timezone`. This avoids converting a coverage date through UTC and accidentally moving it to the prior or next day. Android uses `inexactAllowWhileIdle`; Warrant Book neither declares nor requests exact-alarm permission.

Notification payloads contain only the local item ID. Foreground/warm taps and notification cold starts both resolve that ID against the database before opening detail. If an old notification refers to a removed item, the tap is ignored safely.

## OS limits and delivery caveats

iOS retains at most 64 pending local notifications, and some Android vendors impose their own alarm limits or background restrictions. Warrant Book therefore sorts all candidates by fire date with a stable tie-break and schedules only the earliest 60. Later reminders roll into that window on the next startup, edit/delete, restore, or resume. This is deterministic, but a user who does not reopen the app for a long period may not receive reminders beyond the current rolling window.

The operating system may delay inexact alarms, suppress notifications through Focus/Do Not Disturb, revoke permission, or drop alarms under vendor battery policies. The app cannot guarantee delivery; consult the in-app lists for authoritative dates.

## Platform setup

The implementation targets `flutter_local_notifications 22.3.1`, `timezone 0.11.1`, and `flutter_timezone 5.1.0`.

- Android enables Java 17 core-library desugaring and multidex, declares notification and boot-completed permissions, registers the plugin's scheduled-notification and boot receivers, and uses a dedicated monochrome `drawable` small icon that is explicitly preserved during release resource shrinking. It deliberately omits exact-alarm permissions.
- iOS installs `UNUserNotificationCenter`'s delegate in `AppDelegate`. Dart initialization opts out of alert, badge, and sound permission prompts; those permissions are requested later only through the enable action.

Automated tests verify the Android icon resource contract, timezone refresh boundary, calendar-day resume/midnight transitions, dates, edit replacement, deletion cancellation, restore and startup rebuilds, concurrent serialization, persistence round-trips, deterministic cap selection, plugin-error reporting and clearing, permission revocation/regrant behavior, denial fallback, removed-item handling, and warm/cold tap routing. They do not prove notification delivery on an emulator or physical device. Android and iOS platform builds and real-device delivery remain CI/owner verification because the development host is Linux aarch64 (its available Android `aapt2` binary is x86) and cannot perform iOS builds.
