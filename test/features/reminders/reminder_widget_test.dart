import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/data/repositories/drift_item_repository.dart';
import 'package:warrant_book/domain/models/coverage_line.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/domain/models/purchase_item.dart';
import 'package:warrant_book/features/reminders/reminder_scheduler.dart';
import 'package:warrant_book/features/settings/app_settings.dart';
import 'package:warrant_book/main.dart';

import '../../data/support/db_test_support.dart';
import 'fake_reminder_platform.dart';

void main() {
  testWidgets('permission denial leaves reminders off and explains fallback', (
    tester,
  ) async {
    await withTestDatabase((db) async {
      final repository = DriftItemRepository(db);
      final settings = AppSettings(InMemorySettingsStore());
      final platform = FakeReminderPlatform(permissionGranted: false);
      final scheduler = ReminderScheduler(
        repository: repository,
        settings: settings,
        platform: platform,
        now: () => DateTime(2026, 1, 1, 8),
      );
      await scheduler.initialize();
      await tester.pumpWidget(
        WarrantBookApp(
          repository: repository,
          settings: settings,
          today: DayDate(2026, 1, 1),
          reminderScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();

      expect(platform.permissionRequests, 0);
      await tester.tap(find.byKey(const Key('settingsButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remindersSwitch')));
      await tester.pumpAndSettle();

      expect(platform.permissionRequests, 1);
      expect(settings.remindersEnabled, isFalse);
      expect(find.byKey(const Key('permissionDeniedMessage')), findsOneWidget);
      expect(find.textContaining('source of truth'), findsOneWidget);
    });
  });

  testWidgets('settings reports and clears scheduler failures', (tester) async {
    await withTestDatabase((db) async {
      final repository = DriftItemRepository(db);
      final settings = AppSettings(InMemorySettingsStore());
      final platform = FakeReminderPlatform();
      final scheduler = ReminderScheduler(
        repository: repository,
        settings: settings,
        platform: platform,
      );
      await scheduler.initialize();
      platform.cancelError = StateError('channel unavailable');
      await scheduler.recompute();
      await tester.pumpWidget(
        WarrantBookApp(
          repository: repository,
          settings: settings,
          today: DayDate(2026, 1, 1),
          reminderScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settingsButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reminderSchedulingError')), findsOneWidget);
      expect(find.textContaining('channel unavailable'), findsOneWidget);

      platform.cancelError = null;
      await scheduler.recompute();
      await tester.pump();
      expect(find.byKey(const Key('reminderSchedulingError')), findsNothing);
    });
  });

  testWidgets('warm notification tap opens existing item detail', (
    tester,
  ) async {
    await withTestDatabase((db) async {
      final repository = DriftItemRepository(db);
      await repository.save(_item('warm'));
      final settings = AppSettings(InMemorySettingsStore());
      final platform = FakeReminderPlatform();
      final scheduler = ReminderScheduler(
        repository: repository,
        settings: settings,
        platform: platform,
      );
      await scheduler.initialize();
      await tester.pumpWidget(
        WarrantBookApp(
          repository: repository,
          settings: settings,
          today: DayDate(2026, 1, 1),
          reminderScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();

      platform.tap('warm');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('detailMenu')), findsOneWidget);
      expect(find.text('Item warm'), findsWidgets);
    });
  });

  testWidgets('cold notification payload opens detail after first frame', (
    tester,
  ) async {
    await withTestDatabase((db) async {
      final repository = DriftItemRepository(db);
      await repository.save(_item('cold'));
      final settings = AppSettings(InMemorySettingsStore());
      final platform = FakeReminderPlatform(coldStartPayload: 'item:cold');
      final scheduler = ReminderScheduler(
        repository: repository,
        settings: settings,
        platform: platform,
      );
      await scheduler.initialize();

      await tester.pumpWidget(
        WarrantBookApp(
          repository: repository,
          settings: settings,
          today: DayDate(2026, 1, 1),
          reminderScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('detailMenu')), findsOneWidget);
      expect(find.text('Item cold'), findsWidgets);
    });
  });

  testWidgets('tap for removed item is ignored safely', (tester) async {
    await withTestDatabase((db) async {
      final repository = DriftItemRepository(db);
      final settings = AppSettings(InMemorySettingsStore());
      final platform = FakeReminderPlatform(coldStartPayload: 'item:removed');
      final scheduler = ReminderScheduler(
        repository: repository,
        settings: settings,
        platform: platform,
      );
      await scheduler.initialize();
      await tester.pumpWidget(
        WarrantBookApp(
          repository: repository,
          settings: settings,
          today: DayDate(2026, 1, 1),
          reminderScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('detailMenu')), findsNothing);
      expect(find.text('Warrant Book'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('per-item reminder controls persist days horizon and kinds', (
    tester,
  ) async {
    await withTestDatabase((db) async {
      final repository = DriftItemRepository(db);
      await repository.save(_item('custom'));
      final settings = AppSettings(InMemorySettingsStore());
      final platform = FakeReminderPlatform();
      final scheduler = ReminderScheduler(
        repository: repository,
        settings: settings,
        platform: platform,
      );
      await scheduler.initialize();
      await tester.pumpWidget(
        WarrantBookApp(
          repository: repository,
          settings: settings,
          today: DayDate(2026, 1, 1),
          reminderScheduler: scheduler,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Item custom'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detailMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('detailMenuReminders')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('itemReminderDaysField')),
        '14, 2',
      );
      await tester.enterText(
        find.byKey(const Key('itemReminderHorizonField')),
        '90',
      );
      await tester.tap(find.byKey(const Key('watch-manufacturerWarranty')));
      await tester.tap(find.byKey(const Key('saveItemReminderButton')));
      await tester.pumpAndSettle();

      final override = settings.itemReminderOverride('custom');
      expect(override?.daysBefore, [14, 2]);
      expect(override?.horizonDays, 90);
      expect(
        override?.watchedKinds.contains(CoverageLineKind.manufacturerWarranty),
        isFalse,
      );
    });
  });

  testWidgets('resume refreshes the production day from the injected clock', (
    tester,
  ) async {
    await withTestDatabase((db) async {
      final repository = DriftItemRepository(db);
      await repository.save(_coveredItem('resume-clock', DayDate(2026, 1, 1)));
      final settings = AppSettings(InMemorySettingsStore());
      var now = DateTime(2026, 1, 1, 12);
      await tester.pumpWidget(
        WarrantBookApp(
          repository: repository,
          settings: settings,
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Item resume-clock'), findsOneWidget);

      now = DateTime(2026, 1, 2, 12);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Item resume-clock'), findsNothing);
    });
  });

  testWidgets('foreground midnight timer advances the production day', (
    tester,
  ) async {
    await withTestDatabase((db) async {
      final repository = DriftItemRepository(db);
      await repository.save(_coveredItem('midnight', DayDate(2026, 1, 1)));
      final settings = AppSettings(InMemorySettingsStore());
      var now = DateTime(2026, 1, 1, 23, 59, 59);
      await tester.pumpWidget(
        WarrantBookApp(
          repository: repository,
          settings: settings,
          clock: () => now,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Item midnight'), findsOneWidget);

      now = DateTime(2026, 1, 2);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Item midnight'), findsNothing);
    });
  });
}

PurchaseItem _item(String id) =>
    PurchaseItem(id: id, name: 'Item $id', purchaseDate: DayDate(2025, 1, 1));

PurchaseItem _coveredItem(String id, DayDate end) => PurchaseItem(
  id: id,
  name: 'Item $id',
  purchaseDate: DayDate(2025, 1, 1),
  coverageLines: [
    CoverageLine(
      kind: CoverageLineKind.manufacturerWarranty,
      basis: ExplicitEndDate(endDateValue: end),
    ),
  ],
);
