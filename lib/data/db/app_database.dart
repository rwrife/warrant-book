// Warrant Book — data layer (issue #3).
//
// Drift (SQLite) schema for the local registry: `items` is the aggregate
// root table; `coverage_lines`, `notes` and `attachments` hang off it with
// foreign keys and ON DELETE CASCADE, so deleting an item removes its child
// rows inside the database itself (attachment *files* are cleaned up by the
// document store in issue #6).
//
// Dates are stored as ISO-8601 `yyyy-MM-dd` strings (the `DayDate`
// canonical form): lexicographic order == chronological order, which keeps
// `ORDER BY purchase_date DESC` trivial, and a stored day can never be
// shifted by a device time zone.
//
// Price semantics: a missing price is `price_amount IS NULL AND
// price_currency IS NULL`. An amount of exactly 0.0 with a currency is a
// *recorded* free/zero price and is distinct from missing (issue #2 rule,
// enforced round-trip by `PurchaseRecordedPrice`).
//
// Row classes carry explicit `DataClassName`s so they never collide with the
// pure-Dart domain types (`Note`, `CoverageLine`, ...) that share those
// names — the repository file imports both layers side by side.

import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Registry rows — one per domain `PurchaseItem`.
@DataClassName('ItemRow')
class Items extends Table {
  /// Stable id minted by the repository (UUID v4).
  TextColumn get id => text()();

  TextColumn get name => text()();

  /// ISO `yyyy-MM-dd` — see file header.
  TextColumn get purchaseDate => text().named('purchase_date')();

  TextColumn get category => text().nullable()();

  TextColumn get store => text().nullable()();

  /// Null == price deliberately not recorded (never 0.0).
  RealColumn get priceAmount => real().nullable().named('price_amount')();

  /// ISO-4217 code, null together with [priceAmount].
  TextColumn get priceCurrency => text().nullable().named('price_currency')();

  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Coverage windows belonging to an item; cascade-deleted with it.
@DataClassName('CoverageLineRow')
class CoverageLines extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get itemId =>
      text()
          .named('item_id')
          .references(Items, #id, onDelete: KeyAction.cascade)();

  /// `CoverageLineKind.name` — stable text, not an ordinal, so enum
  /// reordering in code cannot silently reinterpret stored rows.
  TextColumn get kind => text()();

  /// 'duration' | 'explicit' — which of the two nullable basis columns is
  /// populated (the repository enforces the pairing on write and throws
  /// [StateError] on impossible combinations).
  TextColumn get basisKind => text().named('basis_kind')();

  /// Populated when [basisKind] == 'duration'; always >= 1.
  IntColumn get months => integer().nullable()();

  /// Populated when [basisKind] == 'explicit'; ISO `yyyy-MM-dd`.
  TextColumn get endDate => text().named('end_date').nullable()();

  TextColumn get label => text().nullable()();
}

/// Timeline notes belonging to an item; cascade-deleted with it.
@DataClassName('NoteRow')
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get itemId =>
      text()
          .named('item_id')
          .references(Items, #id, onDelete: KeyAction.cascade)();

  /// Note body. The Dart getter is `body` (not `text`) because a getter
  /// named `text` shadows Drift's `text()` column builder and crashes
  /// drift_dev's parser; the SQL column keeps the plain name.
  TextColumn get body => text().named('text')();

  /// ISO `yyyy-MM-dd` day the note was written.
  TextColumn get recordedOn => text().named('recorded_on')();
}

/// Attachment *references* (paths, not bytes) belonging to an item; the
/// rows cascade-delete with the item, file cleanup lands with issue #6.
@DataClassName('AttachmentRow')
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get itemId =>
      text()
          .named('item_id')
          .references(Items, #id, onDelete: KeyAction.cascade)();

  TextColumn get relativePath => text().named('relative_path')();

  TextColumn get displayName => text().nullable().named('display_name')();
}

/// The app database.
///
/// Schema version 1 (issue #3). [migration] carries the scaffold for future
/// versions: unimplemented forward upgrades and *all* downgrades fail
/// loudly at open time — a half-migrated or silently wiped database is
/// unacceptable in a single-copy local-first app.
@DriftDatabase(tables: [Items, CoverageLines, Notes, Attachments])
class WarrantBookDatabase extends _$WarrantBookDatabase {
  /// Wrap an executor (production: `NativeDatabase.createInBackground` with
  /// a file under app-private storage; tests: `NativeDatabase.memory()`).
  WarrantBookDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    // Drift routes BOTH directions through onUpgrade; `from > to` means the
    // file on disk was written by a newer app build.
    onUpgrade: (m, from, to) async {
      if (from > to) {
        // Refuse by default: a downgraded app must not wipe or corrupt a
        // newer schema. Future steps may opt in explicitly, one tested
        // path at a time.
        throw UnsupportedError(
          'Refusing to downgrade the database from schema version $from '
          'to $to; the data layer never destroys user data silently.',
        );
      }
      // Migration scaffold for schema v2+: add one `if (from < n)` block
      // per version step and bump schemaVersion when the step lands. Each
      // step must be additive or a tested data transform — never a drop +
      // recreate that discards user data without an explicit issue.
      if (from < 2 && 2 <= to) {
        throw UnsupportedError(
          'No migration path defined from schema version 1 to 2; '
          'add one here when v2 lands (issue #3 scaffold).',
        );
      }
      // Deliberately no catch-all: any unhandled step falls through to
      // drift's own MigrationError, so an unexpected version jump can never
      // pass unnoticed.
    },
    beforeOpen: (details) async {
      // SQLite enforces foreign keys per-connection; cascade deletes and
      // reference checks depend on this pragma.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
