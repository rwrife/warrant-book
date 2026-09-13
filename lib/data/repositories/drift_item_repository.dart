// Warrant Book — data layer (issue #3).
//
// Drift-backed implementation of [ItemRepository]. Mapping between the
// domain aggregate and the schema lives entirely here:
//
// - `DayDate` <-> ISO `yyyy-MM-dd` TEXT (see app_database.dart header).
// - `CoverageBasis` -> `basis_kind` discriminator + one populated column;
//   inconsistent rows are impossible to write and are reported as
//   [StateError] if they ever appear (corruption must not read as a
//   silently different coverage window).
// - Missing price stays missing: both `price_amount` and `price_currency`
//   are NULL together; 0.0 + code round-trips as a recorded price.
//
// `save` deletes-and-reinserts the child rows inside one transaction —
// lines/notes/attachments have no stable domain-side identity, so the whole
// aggregate boundary is rewritten (bounded by a handful of rows per item).

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../../domain/coverage.dart';
import '../../domain/models/coverage_line.dart';
import '../../domain/models/day_date.dart';
import '../../domain/models/purchase_item.dart';
import '../../domain/repositories/item_repository.dart';
import '../db/app_database.dart';

/// Drift implementation over [WarrantBookDatabase].
class DriftItemRepository implements ItemRepository {
  DriftItemRepository(this._db);

  final WarrantBookDatabase _db;
  static const Uuid _uuid = Uuid();

  @override
  String newItemId() => _uuid.v4();

  @override
  Future<PurchaseItem?> findById(String id) async {
    final row = await (_db.select(_db.items)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return _assemble(row);
  }

  @override
  Future<void> save(PurchaseItem item) => _db.transaction(() async {
    final existing = await (_db.select(_db.items)
          ..where((t) => t.id.equals(item.id))
          ..limit(1))
        .getSingleOrNull();

    final companion = ItemsCompanion.insert(
      id: item.id,
      name: item.name,
      purchaseDate: item.purchaseDate.toString(),
      category: Value(item.category),
      store: Value(item.store),
      priceAmount: Value(item.price.amount),
      priceCurrency: Value(item.price.currencyCode),
      archived: Value(item.archived),
    );
    if (existing == null) {
      await _db.into(_db.items).insert(companion);
    } else {
      await (_db.update(_db.items)
            ..where((t) => t.id.equals(item.id)))
          .write(companion);
      // Child rows have no stable domain identity — rewrite the set.
      await _deleteChildren(item.id);
    }

    await _db.batch((batch) {
      batch.insertAll(_db.coverageLines, [
        for (final line in item.coverageLines)
          CoverageLinesCompanion.insert(
            itemId: item.id,
            kind: line.kind.name,
            basisKind: _basisKindFor(line.basis),
            months: switch (line.basis) {
              final DurationFromPurchase d => Value(d.months),
              ExplicitEndDate() => const Value.absent(),
            },
            endDate: switch (line.basis) {
              final ExplicitEndDate e => Value(e.endDateValue.toString()),
              DurationFromPurchase() => const Value.absent(),
            },
            label: Value(line.label),
          ),
      ]);
      batch.insertAll(_db.notes, [
        for (final note in item.notes)
          NotesCompanion.insert(
            itemId: item.id,
            body: note.text,
            recordedOn: note.recordedOn.toString(),
          ),
      ]);
      batch.insertAll(_db.attachments, [
        for (final ref in item.attachments)
          AttachmentsCompanion.insert(
            itemId: item.id,
            relativePath: ref.relativePath,
            displayName: Value(ref.displayName),
          ),
      ]);
    });
  });

  @override
  Future<bool> delete(String id) async {
    // Children disappear via ON DELETE CASCADE — covered by cascade tests.
    final deleted = await (_db.delete(
      _db.items,
    )..where((t) => t.id.equals(id))).go();
    return deleted > 0;
  }

  @override
  Future<List<PurchaseItem>> list(ItemQuery query) async {
    // Issue #4: search and the category/archived filters are evaluated by
    // SQLite itself (LIKE + correlated EXISTS on notes), never by scanning
    // every row into Dart. Status and the "any active line" criterion are
    // still rolled up in Dart with the single source-of-truth domain math
    // (clamped month arithmetic cannot be expressed losslessly in SQL);
    // they run on the SQL pre-filtered set only.
    final stmt = _db.select(_db.items);
    if (!query.includeArchived && !query.archiveView) {
      stmt.where((t) => t.archived.equals(false));
    }
    if (query.category != null) {
      stmt.where((t) => t.category.equals(query.category!));
    }

    final needleLower = query.search?.trim().toLowerCase();
    final hasSearch = needleLower != null && needleLower.isNotEmpty;
    if (hasSearch) {
      // SQLite LIKE is ASCII-case-insensitive, which already covers the
      // common case; the Dart pass below re-checks exact case-insensitive
      // substring semantics (unicode-safe) on the small candidate set.
      final pattern = '%${_escapeLikePattern(needleLower)}%';
      final noteHits = _db.selectOnly(_db.notes)
        ..addColumns([_db.notes.id])
        ..where(
          _db.notes.itemId.equalsExp(_db.items.id) &
              _db.notes.body.like(pattern, escapeChar: _likeEscapeChar),
        );
      stmt.where((t) =>
          t.name.like(pattern, escapeChar: _likeEscapeChar) |
          t.store.like(pattern, escapeChar: _likeEscapeChar) |
          existsQuery(noteHits));
    }

    final rows = await stmt.get();

    final results = <PurchaseItem>[];
    for (final row in rows) {
      final item = await _assemble(row);
      if (hasSearch && !_matchesSearch(item, needleLower)) {
        continue;
      }
      if (query.status != null &&
          itemCoverageStatus(item, query.today,
                  horizonDays: query.horizonDays) !=
              query.status) {
        continue;
      }
      if (query.coverageNow) {
        // "Coverage now": any line still covering today (active OR
        // expiring — an expiring line still covers until its end day).
        // Plain no-line registry entries stay here too (they can never
        // expire and would otherwise appear in no list at all).
        if (item.coverageLines.isNotEmpty) {
          final statuses = allLineStatuses(item, query.today,
              horizonDays: query.horizonDays);
          final covering = statuses.any((s) =>
              s.status == CoverageLineStatus.active ||
              s.status == CoverageLineStatus.expiring);
          if (!covering) continue;
        }
      }
      if (query.expiringSoon) {
        final statuses = allLineStatuses(item, query.today,
            horizonDays: query.horizonDays);
        if (!statuses.any((s) => s.status == CoverageLineStatus.expiring)) {
          continue;
        }
      }
      if (query.archiveView) {
        final rolledUp = itemCoverageStatus(item, query.today,
            horizonDays: query.horizonDays);
        final fullyExpired = rolledUp == ItemCoverageStatus.expired;
        if (!(item.archived || fullyExpired)) continue;
      }
      results.add(item);
    }
    // Newest purchase first; id breaks date ties deterministically.
    results.sort((a, b) {
      final byDate = b.purchaseDate.compareTo(a.purchaseDate);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return results;
  }

  @override
  Future<List<String>> categories() async {
    final stmt = _db.selectOnly(_db.items, distinct: true)
      ..addColumns([_db.items.category])
      ..where(_db.items.category.isNotNull())
      ..orderBy([OrderingTerm.asc(_db.items.category)]);
    final rows = await stmt.get();
    return [
      for (final row in rows)
        ?row.read(_db.items.category),
    ];
  }

  /// Escape character used with every `LIKE` pattern in [list].
  static const String _likeEscapeChar = r'\';

  /// Escapes `_`, `%` and the escape char itself so user-typed search text
  /// is matched literally (a query for "100%" must not wildcard-match).
  static String _escapeLikePattern(String needle) {
    final buffer = StringBuffer();
    for (final unit in needle.codeUnits) {
      if (unit == 0x5F /* _ */ ||
          unit == 0x25 /* % */ ||
          unit == 0x5C /* \ */) {
        buffer.write(_likeEscapeChar);
      }
      buffer.writeCharCode(unit);
    }
    return buffer.toString();
  }

  Future<void> _deleteChildren(String itemId) async {
    await (_db.delete(
      _db.coverageLines,
    )..where((t) => t.itemId.equals(itemId))).go();
    await (_db.delete(
      _db.notes,
    )..where((t) => t.itemId.equals(itemId))).go();
    await (_db.delete(
      _db.attachments,
    )..where((t) => t.itemId.equals(itemId))).go();
  }

  Future<PurchaseItem> _assemble(ItemRow row) async {
    final lineRows = await (_db.select(
      _db.coverageLines,
    )..where((t) => t.itemId.equals(row.id)))
        .get();
    final noteRows = await (_db.select(
      _db.notes,
    )..where((t) => t.itemId.equals(row.id)))
        .get();
    final attachmentRows = await (_db.select(
      _db.attachments,
    )..where((t) => t.itemId.equals(row.id)))
        .get();

    return PurchaseItem(
      id: row.id,
      name: row.name,
      purchaseDate: DayDate.parseIso(row.purchaseDate),
      category: row.category,
      store: row.store,
      price: row.priceAmount == null
          ? const PurchaseRecordedPrice.missing()
          : PurchaseRecordedPrice.money(
              row.priceAmount!,
              row.priceCurrency ?? 'USD',
            ),
      coverageLines: [for (final l in lineRows) _toLine(l)],
      notes: [
        for (final n in noteRows)
          Note(text: n.body, recordedOn: DayDate.parseIso(n.recordedOn)),
      ],
      attachments: [
        for (final a in attachmentRows)
          AttachmentRef(relativePath: a.relativePath, displayName: a.displayName),
      ],
      archived: row.archived,
    );
  }

  static String _basisKindFor(CoverageBasis basis) => switch (basis) {
    DurationFromPurchase() => 'duration',
    ExplicitEndDate() => 'explicit',
  };

  static CoverageLine _toLine(CoverageLineRow row) {
    final kind = CoverageLineKind.values.byName(row.kind);
    final CoverageBasis basis;
    if (row.basisKind == 'duration') {
      final months = row.months;
      if (months == null) {
        throw StateError(
          'Corrupt coverage_lines row ${row.id}: basis_kind=duration with '
          'NULL months.',
        );
      }
      basis = DurationFromPurchase(months: months);
    } else if (row.basisKind == 'explicit') {
      final end = row.endDate;
      if (end == null) {
        throw StateError(
          'Corrupt coverage_lines row ${row.id}: basis_kind=explicit with '
          'NULL end_date.',
        );
      }
      basis = ExplicitEndDate(endDateValue: DayDate.parseIso(end));
    } else {
      throw StateError(
        'Corrupt coverage_lines row ${row.id}: unknown basis_kind '
        '"${row.basisKind}".',
      );
    }
    return CoverageLine(kind: kind, basis: basis, label: row.label);
  }

  static bool _matchesSearch(PurchaseItem item, String needleLower) =>
      item.name.toLowerCase().contains(needleLower) ||
      (item.store?.toLowerCase().contains(needleLower) ?? false) ||
      item.notes.any((n) => n.text.toLowerCase().contains(needleLower));
}

/// Opens [path] as a background-isolate app database (production wiring for
/// issue #4; tests use `NativeDatabase.memory()` directly).
WarrantBookDatabase openWarrantBookDatabase(String path) {
  return WarrantBookDatabase(
    NativeDatabase.createInBackground(File(path)),
  );
}
