// Warrant Book — data-layer test support (issue #3).
//
// Opens the app schema against SQLite for `flutter test`:
//
// - On Linux/macOS hosts (dev machines, the CI `test` job on
//   ubuntu-24.04), drift's `NativeDatabase` resolves `libsqlite3` from the
//   system libraries — the same engine the app runs on device.
// - On Windows hosts the sqlite3 package needs a DLL on PATH; the CI test
//   job is Linux-only so this does not gate anything today (documented
//   honestly rather than papered over).
//
// `NativeDatabase.memory()` is the same SQLite engine with a file-less
// backing store, so cascade behavior, PRAGMA handling and migrations
// under test match production.

import 'package:drift/native.dart';

import 'package:warrant_book/data/db/app_database.dart';

/// A fresh, schema-v1, in-memory app database. Call [WarrantBookDatabase.close]
/// (or use [withTestDatabase]) when the test ends.
WarrantBookDatabase openTestDatabase() =>
    WarrantBookDatabase(NativeDatabase.memory());

/// Runs [body] against a fresh in-memory database and closes it afterwards,
/// even on failure.
Future<void> withTestDatabase(
  Future<void> Function(WarrantBookDatabase db) body,
) async {
  final db = openTestDatabase();
  try {
    await body(db);
  } finally {
    await db.close();
  }
}
