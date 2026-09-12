// Data-layer tests for DriftItemRepository (issue #3).
//
// Requirement coverage from the issue:
// - full CRUD round-trips (aggregate: item + lines + notes + attachments)
// - deleting an item cascades coverage lines and notes in the DB
// - list-by-status (active/expiring/expired) at synthetic "today" values
// - search by name / notes / store, category filter
// - missing ≠ zero price round-trip
//
// Everything runs against `NativeDatabase.memory()` — the same SQLite
// engine the app uses on device, in a file-less store (see
// test/data/support/db_test_support.dart).


import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/data/db/app_database.dart';
import 'package:warrant_book/data/repositories/drift_item_repository.dart';
import 'package:warrant_book/domain/coverage.dart';
import 'package:warrant_book/domain/models/coverage_line.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/domain/models/purchase_item.dart';
import 'package:warrant_book/domain/repositories/item_repository.dart';

import 'support/db_test_support.dart';
import 'support/fixtures.dart';

void main() {
  group('CRUD round-trips', () {
    test('save + findById restores the full aggregate', () async {
      await withTestDatabase((db) async {
        final repo = DriftItemRepository(db);
        final item = fullItem(
          price: PurchaseRecordedPrice.money(199.99, 'USD'),
        );
        await repo.save(item);

        final loaded = await repo.findById(item.id);
        expect(loaded, isNotNull);
        expect(loaded!.id, item.id);
        expect(loaded.name, item.name);
        expect(loaded.purchaseDate, item.purchaseDate);
        expect(loaded.category, 'tools');
        expect(loaded.store, 'Home Depot');
        expect(loaded.price, PurchaseRecordedPrice.money(199.99, 'USD'));
        expect(loaded.archived, isFalse);
        expect(loaded.coverageLines, hasLength(3));
        expect(loaded.coverageLines[0], item.coverageLines[0]);
        expect(loaded.coverageLines[1], item.coverageLines[1]);
        expect(loaded.coverageLines[2], item.coverageLines[2]);
        expect(loaded.notes, hasLength(2));
        expect(loaded.notes[0], item.notes[0]);
        expect(loaded.attachments, hasLength(1));
        expect(loaded.attachments.single, item.attachments.single);
      });
    });

    test('missing price round-trips as missing, zero price as recorded',
        () async {
      await withTestDatabase((db) async {
        final repo = DriftItemRepository(db);
        await repo.save(fullItem(id: 'missing'));
        await repo.save(
          fullItem(
            id: 'zero',
            price: PurchaseRecordedPrice.money(0.0, 'USD'),
          ),
        );

        final missing = await repo.findById('missing');
        final zero = await repo.findById('zero');
        expect(missing!.price.isMissing, isTrue);
        expect(missing.price.amount, isNull);
        expect(zero!.price.isMissing, isFalse,
            reason: '0.0 is a recorded price, never "missing"');
        expect(zero.price.amount, 0.0);
        expect(zero.price.currencyCode, 'USD');
      });
    });

    test('findById returns null for unknown ids', () async {
      await withTestDatabase((db) async {
        final repo = DriftItemRepository(db);
        expect(await repo.findById('nope'), isNull);
      });
    });

    test('save updates an existing item and replaces its child rows',
        () async {
      await withTestDatabase((db) async {
        final repo = DriftItemRepository(db);
        await repo.save(fullItem());

        final edited = fullItem().copyForTest(
          name: 'Dewalt drill (edited)',
          coverageLines: [
            CoverageLine(
              kind: CoverageLineKind.manufacturerWarranty,
              basis: DurationFromPurchase(months: 12),
            ),
          ],
          notes: [
            Note(text: 'only note now', recordedOn: DayDate(2026, 2, 1)),
          ],
          attachments: const [],
          archived: true,
        );
        await repo.save(edited);

        final loaded = await repo.findById('item-full');
        expect(loaded!.name, 'Dewalt drill (edited)');
        expect(loaded.archived, isTrue);
        expect(loaded.coverageLines, hasLength(1));
        expect(loaded.coverageLines.single.basis,
            DurationFromPurchase(months: 12));
        expect(loaded.notes.single.text, 'only note now');
        expect(loaded.attachments, isEmpty);

        // No stale child rows left behind for the item.
        expect(await db.select(db.coverageLines).get(), hasLength(1));
        expect(await db.select(db.notes).get(), hasLength(1));
        expect(await db.select(db.attachments).get(), isEmpty);
      });
    });

    test('delete removes the item; delete of unknown id returns false',
        () async {
      await withTestDatabase((db) async {
        final repo = DriftItemRepository(db);
        await repo.save(fullItem());
        expect(await repo.delete('item-full'), isTrue);
        expect(await repo.findById('item-full'), isNull);
        expect(await repo.delete('item-full'), isFalse);
      });
    });

    test('newItemId mints unique ids', () async {
      await withTestDatabase((db) async {
        final repo = DriftItemRepository(db);
        final ids = {for (var i = 0; i < 50; i++) repo.newItemId()};
        expect(ids, hasLength(50));
      });
    });
  });

  group('cascade delete', () {
    test('deleting an item cascades lines, notes and attachments in the DB',
        () async {
      await withTestDatabase((db) async {
        final repo = DriftItemRepository(db);
        await repo.save(fullItem());
        expect(await db.select(db.coverageLines).get(), hasLength(3));
        expect(await db.select(db.notes).get(), hasLength(2));
        expect(await db.select(db.attachments).get(), hasLength(1));

        expect(await repo.delete('item-full'), isTrue);

        expect(await db.select(db.coverageLines).get(), isEmpty,
            reason: 'ON DELETE CASCADE, not repository bookkeeping');
        expect(await db.select(db.notes).get(), isEmpty);
        expect(await db.select(db.attachments).get(), isEmpty);
      });
    });

    test('child rows cannot exist without a parent (foreign keys on)',
        () async {
      await withTestDatabase((db) async {
        await expectLater(
          db.into(db.notes).insert(
                NotesCompanion.insert(
                  itemId: 'ghost',
                  body: 'orphan',
                  recordedOn: '2026-01-01',
                ),
              ),
          throwsA(isA<SqliteException>()),
        );
      });
    });
  });

  group('status queries at synthetic today', () {
    // One item per rolled-up status, all anchored on 2026-01-01:
    // - active:    warranty ends 2028-01-01 (far out)
    // - expiring:  return window ends 2026-01-15 (within horizon 30 of
    //              today 2026-01-01)
    // - expired:   line ended 2025-12-01 (before today)
    // - none:      no lines at all
    Future<void> seedStatuses(WarrantBookDatabase db) async {
      final repo = DriftItemRepository(db);
      final purchase = day(2026, 1, 1);
      await repo.save(PurchaseItem(
        id: 'active',
        name: 'Active thing',
        purchaseDate: purchase,
        coverageLines: [
          CoverageLine(
            kind: CoverageLineKind.manufacturerWarranty,
            basis: DurationFromPurchase.years(2),
          ),
        ],
      ));
      await repo.save(PurchaseItem(
        id: 'expiring',
        name: 'Expiring thing',
        purchaseDate: purchase,
        coverageLines: [
          CoverageLine(
            kind: CoverageLineKind.returnWindow,
            basis: ExplicitEndDate(endDateValue: DayDate(2026, 1, 15)),
          ),
        ],
      ));
      await repo.save(PurchaseItem(
        id: 'expired',
        name: 'Expired thing',
        purchaseDate: day(2024, 11, 1),
        coverageLines: [
          CoverageLine(
            kind: CoverageLineKind.returnWindow,
            basis: ExplicitEndDate(endDateValue: DayDate(2025, 12, 1)),
          ),
        ],
      ));
      await repo.save(PurchaseItem(
        id: 'plain',
        name: 'Plain registry entry',
        purchaseDate: purchase,
      ));
    }

    test('each status filter returns exactly its item', () async {
      await withTestDatabase((db) async {
        await seedStatuses(db);
        final repo = DriftItemRepository(db);
        final today = day(2026, 1, 1);

        Future<Set<String>> idsFor(ItemCoverageStatus status) async => {
              for (final i in await repo.list(
                ItemQuery(today: today, status: status),
              ))
                i.id,
            };

        expect(await idsFor(ItemCoverageStatus.active), {'active'});
        expect(await idsFor(ItemCoverageStatus.expiring), {'expiring'});
        expect(await idsFor(ItemCoverageStatus.expired), {'expired'});
        expect(await idsFor(ItemCoverageStatus.none), {'plain'});
      });
    });

    test('horizon moves an item between active and expiring', () async {
      await withTestDatabase((db) async {
        await seedStatuses(db);
        final repo = DriftItemRepository(db);
        final today = day(2026, 1, 1);

        // Return window ends 2026-01-15: 14 days out — outside a 7-day
        // horizon, inside a 30-day one.
        final far = await repo.list(
          ItemQuery(today: today, horizonDays: 7, status: ItemCoverageStatus.active),
        );
        expect(far.map((i) => i.id), contains('expiring'));

        final near = await repo.list(
          ItemQuery(today: today, horizonDays: 30, status: ItemCoverageStatus.active),
        );
        expect(near.map((i) => i.id), isNot(contains('expiring')));
      });
    });

    test('max-severity rollup: one expired line drags the item to expired',
        () async {
      await withTestDatabase((db) async {
        final repo = DriftItemRepository(db);
        await repo.save(PurchaseItem(
          id: 'mixed',
          name: 'Mixed lines',
          purchaseDate: day(2026, 1, 1),
          coverageLines: [
            CoverageLine(
              kind: CoverageLineKind.manufacturerWarranty,
              basis: DurationFromPurchase.years(5),
            ),
            CoverageLine(
              kind: CoverageLineKind.returnWindow,
              basis: ExplicitEndDate(endDateValue: DayDate(2025, 1, 31)),
            ),
          ],
        ));
        final expiredItems = await repo.list(
          ItemQuery(today: day(2026, 1, 1), status: ItemCoverageStatus.expired),
        );
        expect(expiredItems.map((i) => i.id), ['mixed']);
      });
    });
  });

  group('search and filters', () {
    Future<void> seedSearchable(WarrantBookDatabase db) async {
      final repo = DriftItemRepository(db);
      await repo.save(fullItem(id: 'a'));
      await repo.save(fullItem(
        id: 'b',
        name: 'KitchenAid Mixer',
        store: 'Target',
        category: 'kitchen',
        // Distinct note body — the shared fixture note happens to contain
        // the substring "registered", which would confuse note-search
        // assertions if reused verbatim.
      ).copyForTest(
        notes: [
          Note(text: 'Need an extension cord', recordedOn: DayDate(2026, 2, 2)),
        ],
      ));
      await repo.save(PurchaseItem(
        id: 'c',
        name: 'Blank notebook',
        purchaseDate: day(2026, 3, 1),
        notes: [
          Note(text: 'bought with the drill', recordedOn: DayDate(2026, 3, 1)),
        ],
      ));
      await repo.save(fullItem(
        id: 'archived-one',
        name: 'Old drill press',
        category: 'tools',
        archived: true,
      ));
    }

    test('search matches name (case-insensitive)', () async {
      await withTestDatabase((db) async {
        await seedSearchable(db);
        final repo = DriftItemRepository(db);
        final hits = await repo.list(
          ItemQuery(today: day(2026, 6, 1), search: 'DRILL'),
        );
        // 'a' (name drill), 'c' (note mentions drill) — not 'archived-one'.
        expect(hits.map((i) => i.id), containsAll(['a', 'c']));
        expect(hits.map((i) => i.id), isNot(contains('b')));
      });
    });

    test('search matches store', () async {
      await withTestDatabase((db) async {
        await seedSearchable(db);
        final repo = DriftItemRepository(db);
        final hits = await repo.list(
          ItemQuery(today: day(2026, 6, 1), search: 'target'),
        );
        expect(hits.map((i) => i.id), ['b']);
      });
    });

    test('search matches note text', () async {
      await withTestDatabase((db) async {
        await seedSearchable(db);
        final repo = DriftItemRepository(db);
        final hits = await repo.list(
          ItemQuery(today: day(2026, 6, 1), search: 'registered online'),
        );
        expect(hits.map((i) => i.id), ['a']);
      });
    });

    test('LIKE wildcards in search text are literal', () async {
      await withTestDatabase((db) async {
        await seedSearchable(db);
        final repo = DriftItemRepository(db);
        final hits = await repo.list(
          ItemQuery(today: day(2026, 6, 1), search: '100% cotton'),
        );
        expect(hits, isEmpty);
      });
    });

    test('category filter matches exactly', () async {
      await withTestDatabase((db) async {
        await seedSearchable(db);
        final repo = DriftItemRepository(db);
        final kitchen = await repo.list(
          ItemQuery(today: day(2026, 6, 1), category: 'kitchen'),
        );
        expect(kitchen.map((i) => i.id), ['b']);
      });
    });

    test('archived items hidden unless includeArchived', () async {
      await withTestDatabase((db) async {
        await seedSearchable(db);
        final repo = DriftItemRepository(db);
        final without = await repo.list(ItemQuery(today: day(2026, 6, 1)));
        expect(without.map((i) => i.id), isNot(contains('archived-one')));

        final with_ = await repo.list(
          ItemQuery(today: day(2026, 6, 1), includeArchived: true),
        );
        expect(with_.map((i) => i.id), contains('archived-one'));
      });
    });

    test('results ordered newest purchase first', () async {
      await withTestDatabase((db) async {
        await seedSearchable(db);
        final repo = DriftItemRepository(db);
        final all = await repo.list(
          ItemQuery(today: day(2026, 6, 1), includeArchived: true),
        );
        final dates = all.map((i) => i.purchaseDate).toList();
        for (var i = 1; i < dates.length; i++) {
          expect(dates[i - 1].isAtOrAfter(dates[i]), isTrue);
        }
      });
    });
  });
}

/// Test-only aggregate copy helper — the domain keeps aggregates immutable
/// and the UI edit flow will construct fresh aggregates; tests just need a
/// concise way to derive a variant.
extension on PurchaseItem {
  PurchaseItem copyForTest({
    String? name,
    List<CoverageLine>? coverageLines,
    List<Note>? notes,
    List<AttachmentRef>? attachments,
    bool? archived,
  }) {
    return PurchaseItem(
      id: id,
      name: name ?? this.name,
      purchaseDate: purchaseDate,
      category: category,
      store: store,
      price: price,
      coverageLines: coverageLines ?? this.coverageLines,
      notes: notes ?? this.notes,
      attachments: attachments ?? this.attachments,
      archived: archived ?? this.archived,
    );
  }
}
