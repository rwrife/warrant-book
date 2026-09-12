// Schema & migration-scaffold tests (issue #3).
//
// Exercises real database opens against file-backed SQLite (same engine as
// production, per db_test_support.dart):
//
// - migration-from-empty: a brand-new file gains all four tables at
//   schema version 1; reopening is a no-op (data survives).
// - the v1 -> v2+ upgrade scaffold fails loudly until a real step is
//   implemented (no silent half-migrations).
// - downgrades are refused so a newer database can never be wiped by an
//   older app build.
//
// A test-only subclass raises `schemaVersion` to simulate an app build from
// the future.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/data/db/app_database.dart';

class _FutureSchemaDatabase extends WarrantBookDatabase {
  _FutureSchemaDatabase(super.executor);

  @override
  int get schemaVersion => 2;
}

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('warrantbook'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  String dbPath(String name) => '${tempDir.path}/$name.sqlite';

  test('migration from empty: fresh file gets schema v1 with all tables',
      () async {
    final db = WarrantBookDatabase(NativeDatabase(File(dbPath('fresh'))));
    addTearDown(db.close);

    // user_version is how SQLite tracks the drift schema version.
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 1);

    // All four tables exist and are usable.
    await db.customStatement(
      'INSERT INTO items (id, name, purchase_date, archived) '
      "VALUES ('x', 'x', '2026-01-01', 0)",
    );
    final count =
        await db.customSelect('SELECT COUNT(*) AS c FROM items').getSingle();
    expect(count.data['c'], 1);

    final tableNames = (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table'",
                )
                .get())
            .map((row) => row.data['name'] as String)
            .toSet();
    expect(
      tableNames,
      containsAll(<String>{'items', 'coverage_lines', 'notes', 'attachments'}),
    );
  });

  test('data survives close and reopen at the same version', () async {
    final path = dbPath('reopen');
    final db = WarrantBookDatabase(NativeDatabase(File(path)));
    await db.customStatement(
      'INSERT INTO items (id, name, purchase_date, archived) '
      "VALUES ('keep', 'keep', '2026-01-01', 0)",
    );
    await db.close();

    final reopened = WarrantBookDatabase(NativeDatabase(File(path)));
    addTearDown(reopened.close);
    final count = await reopened
        .customSelect("SELECT COUNT(*) AS c FROM items WHERE id='keep'")
        .getSingle();
    expect(count.data['c'], 1, reason: 're-open must not recreate or wipe');
  });

  test('upgrade scaffold refuses an unimplemented v1 -> v2 step', () async {
    final path = dbPath('upgrade');
    final v1 = WarrantBookDatabase(NativeDatabase(File(path)));
    await v1.customSelect('SELECT 1').getSingle(); // forces onCreate
    await v1.close();

    Object? openError;
    final future = _FutureSchemaDatabase(NativeDatabase(File(path)));
    try {
      await future.customSelect('SELECT 1').getSingle();
    } catch (error) {
      openError = error;
    } finally {
      await future.close();
    }
    expect(openError, isNotNull,
        reason: 'schema v2+ must fail loudly until a migration step exists');
    expect(openError.toString(), contains('No migration path defined'));
  });

  test('downgrade from a future schema is refused, not destructive',
      () async {
    final path = dbPath('downgrade');
    final future = _FutureSchemaDatabase(NativeDatabase(File(path)));
    await future.customSelect('SELECT 1').getSingle(); // fresh file -> v2
    await future.close();

    Object? openError;
    final older = WarrantBookDatabase(NativeDatabase(File(path)));
    try {
      await older.customSelect('SELECT 1').getSingle();
    } catch (error) {
      openError = error;
    } finally {
      await older.close();
    }
    expect(openError, isNotNull, reason: 'downgrades must be refused');
    expect(openError.toString(), contains('Refusing to downgrade'));
  });
}
