// Widget tests for the core registry UI (issue #4).
//
// Acceptance criteria covered here:
// 1. add → appears in Coverage now
// 2. item with a 24-month warranty shows the correct computed status
//    (active, end date computed from the purchase date)
// 3. editing a coverage line recomputes the status
// 4. search returns matches and excludes non-matches
//
// All tests run the real widget tree over the real Drift repository on
// `NativeDatabase.memory()` with a frozen "today" (2026-06-15) injected
// through AppScope — no mocks between UI and database.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/data/db/app_database.dart';
import 'package:warrant_book/data/repositories/drift_item_repository.dart';
import 'package:warrant_book/domain/models/coverage_line.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/domain/models/purchase_item.dart';
import 'package:warrant_book/features/settings/app_settings.dart';
import 'package:warrant_book/main.dart';

import '../data/support/db_test_support.dart';

final DayDate today = DayDate(2026, 6, 15);

void main() {
  Future<void> pumpApp(
    WidgetTester tester,
    WarrantBookDatabase db, {
    List<PurchaseItem> seed = const [],
    int horizonDays = 30,
  }) async {
    final repo = DriftItemRepository(db);
    for (final item in seed) {
      await repo.save(item);
    }
    await tester.pumpWidget(
      WarrantBookApp(
        repository: repo,
        settings: AppSettings(InMemorySettingsStore(),
            horizonDays: horizonDays),
        today: today,
      ),
    );
    await tester.pumpAndSettle();
  }

  PurchaseItem item({
    String id = 'seed-1',
    required String name,
    DayDate? purchaseDate,
    String? category,
    List<CoverageLine> lines = const [],
    List<Note> notes = const [],
    bool archived = false,
  }) {
    return PurchaseItem(
      id: id,
      name: name,
      purchaseDate: purchaseDate ?? DayDate(2026, 1, 10),
      category: category,
      notes: notes,
      coverageLines: lines,
      archived: archived,
    );
  }

  testWidgets('add purchase → item appears in Coverage now',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      await pumpApp(tester, db);

      await tester.tap(find.byKey(const Key('addPurchaseButton')));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('nameField')), 'Espresso machine');
      await tester.enterText(
          find.byKey(const Key('categoryField')), 'kitchen');
      // Default coverage line: manufacturer warranty, 24 months.
      await tester.enterText(find.byKey(const Key('monthsField-0')), '24');
      await tester.pump();
      // Live computed end-date preview (issue #4: "duration inputs show
      // the computed end date live") — purchase date defaults to today
      // (2026-06-15) + 24 months = 2028-06-15.
      expect(find.text('Ends 2028-06-15'), findsOneWidget);

      await tester.tap(find.byKey(const Key('saveButton')));
      await tester.pumpAndSettle();

      expect(find.text('Espresso machine'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });
  });

  testWidgets('24-month warranty computes status and end date correctly',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      // Purchased 2024-07-01, 24-month warranty → ends 2026-07-01,
      // i.e. 16 days after frozen today (2026-06-15): inside the default
      // 30-day horizon, so it must read "Expiring", not "Active".
      await pumpApp(tester, db, seed: [
        item(
          name: 'Drill press',
          purchaseDate: DayDate(2024, 7, 1),
          lines: [
            CoverageLine(
              kind: CoverageLineKind.manufacturerWarranty,
              basis: DurationFromPurchase(months: 24),
            ),
          ],
        ),
      ]);

      expect(find.text('Drill press'), findsOneWidget);
      expect(find.text('Expiring'), findsOneWidget);
      expect(find.textContaining('Ends 2026-07-01'), findsNothing);
      // Row subtitle shows remaining days.
      expect(find.textContaining('16 days left'), findsOneWidget);

      // Open detail: coverage line shows chip + computed end date.
      await tester.tap(find.text('Drill press'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ends 2026-07-01'), findsOneWidget);
      expect(find.text('Expiring'), findsWidgets);
    });
  });

  testWidgets('editing a coverage line recomputes the status',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      // 24 months from 2024-07-01 = expiring (as above).
      await pumpApp(tester, db, seed: [
        item(
          id: 'edit-me',
          name: 'Standing desk',
          purchaseDate: DayDate(2024, 7, 1),
          lines: [
            CoverageLine(
              kind: CoverageLineKind.manufacturerWarranty,
              basis: DurationFromPurchase(months: 24),
            ),
          ],
        ),
      ]);
      expect(find.text('Expiring'), findsOneWidget);

      // Edit: extend the warranty to 48 months → end 2028-07-01, far
      // outside the horizon → status must recompute to Active.
      await tester.tap(find.text('Standing desk'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detailMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detailMenuEdit')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('monthsField-0')), '48');
      await tester.pump();
      expect(find.text('Ends 2028-07-01'), findsOneWidget);
      await tester.tap(find.byKey(const Key('saveButton')));
      await tester.pumpAndSettle(); // pop back to the list

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Expiring'), findsNothing);
    });
  });

  testWidgets('search returns matches and excludes non-matches',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      await pumpApp(tester, db, seed: [
        item(
          id: 'a',
          name: 'Dewalt drill',
          category: 'tools',
          lines: [
            CoverageLine(
              kind: CoverageLineKind.manufacturerWarranty,
              basis: DurationFromPurchase.years(3),
            ),
          ],
        ),
        item(
          id: 'b',
          name: 'KitchenAid mixer',
          category: 'kitchen',
          notes: [Note(text: 'extension cord needed', recordedOn: today)],
        ),
      ]);

      // Both visible with no search.
      expect(find.text('Dewalt drill'), findsOneWidget);
      expect(find.text('KitchenAid mixer'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('searchField')), 'drill');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Dewalt drill'), findsOneWidget);
      expect(find.text('KitchenAid mixer'), findsNothing);

      // Clearing restores everything.
      await tester.enterText(find.byKey(const Key('searchField')), '');
      await tester.pumpAndSettle();
      expect(find.text('Dewalt drill'), findsOneWidget);
      expect(find.text('KitchenAid mixer'), findsOneWidget);

      // Note-text search hits the item whose NAME does not match.
      await tester.enterText(
          find.byKey(const Key('searchField')), 'extension cord');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('KitchenAid mixer'), findsOneWidget);
      expect(find.text('Dewalt drill'), findsNothing);
    });
  });

  testWidgets('category filter narrows the list', (WidgetTester tester) async {
    await withTestDatabase((db) async {
      await pumpApp(tester, db, seed: [
        item(id: 'a', name: 'Dewalt drill', category: 'tools'),
        item(id: 'b', name: 'KitchenAid mixer', category: 'kitchen'),
      ]);

      await tester.tap(find.byKey(const Key('categoryChip-tools')));
      await tester.pumpAndSettle();

      expect(find.text('Dewalt drill'), findsOneWidget);
      expect(find.text('KitchenAid mixer'), findsNothing);
    });
  });

  testWidgets('expiring-soon tab honors the horizon setting',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      // Line ends 16 days out: inside 30-day horizon, outside 7-day.
      await pumpApp(tester, db, seed: [
        item(
          name: 'Drill press',
          purchaseDate: DayDate(2024, 7, 1),
          lines: [
            CoverageLine(
              kind: CoverageLineKind.manufacturerWarranty,
              basis: DurationFromPurchase(months: 24),
            ),
          ],
        ),
      ]);

      // Switch to the Expiring soon tab (index 1).
      await tester.tap(find.widgetWithText(Tab, 'Expiring soon'));
      await tester.pumpAndSettle();
      expect(find.text('Drill press'), findsOneWidget);

      // Shrink the horizon to 7 via the settings dialog → empty state.
      await tester.tap(find.byKey(const Key('settingsButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('horizonField')), '7');
      await tester.tap(find.byKey(const Key('saveHorizonButton')));
      await tester.pumpAndSettle();

      expect(find.text('Drill press'), findsNothing);
      expect(
        find.text('Nothing is expiring within the next 7 days.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('archive tab lists archived items; unarchive returns them',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      await pumpApp(tester, db, seed: [
        item(id: 'arch', name: 'Old router', archived: true),
      ]);

      await tester.tap(find.widgetWithText(Tab, 'Archive'));
      await tester.pumpAndSettle();
      expect(find.text('Old router'), findsOneWidget);

      await tester.tap(find.text('Old router'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detailMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detailMenuArchive')));
      await tester.pumpAndSettle();

      // Back to the list, where the unarchived item must be gone from
      // the archive tab (the detail page still shows its title).
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Old router'), findsNothing);
      expect(
        find.text('No archived or fully expired items yet.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('add-only note appears on the timeline',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      await pumpApp(tester, db, seed: [item(id: 'n', name: 'Grill')]);

      await tester.tap(find.text('Grill'));
      await tester.pumpAndSettle();
      expect(find.text('No notes yet. Record repairs, RMAs, or receipts here.'),
          findsOneWidget);

      await tester.enterText(find.byKey(const Key('noteField')), 'RMA 4711');
      await tester.tap(find.byKey(const Key('addNoteButton')));
      await tester.pumpAndSettle();

      expect(find.text('RMA 4711'), findsOneWidget);
      expect(find.textContaining('2026-06-15'), findsOneWidget);
    });
  });

  testWidgets('validation blocks save and shows inline problems',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      await pumpApp(tester, db);

      await tester.tap(find.byKey(const Key('addPurchaseButton')));
      await tester.pumpAndSettle();

      // Blank name + invalid months → save must not pop, errors inline.
      await tester.tap(find.byKey(const Key('saveButton')));
      await tester.pumpAndSettle();

      expect(find.text('Item name is required.'), findsOneWidget);
      // Still on the form (list screen's add button is not in the tree).
      expect(find.byKey(const Key('addPurchaseButton')), findsNothing);
    });
  });
}
