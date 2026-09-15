import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/domain/models/coverage_line.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/domain/models/purchase_item.dart';
import 'package:warrant_book/domain/repositories/item_repository.dart';
import 'package:warrant_book/features/reminders/reminder_scheduler.dart';
import 'package:warrant_book/features/reminders/rescheduling_item_repository.dart';
import 'package:warrant_book/features/settings/app_settings.dart';

import 'fake_reminder_platform.dart';

void main() {
  late _MemoryRepository repository;
  late InMemorySettingsStore store;
  late AppSettings settings;
  late FakeReminderPlatform platform;
  late ReminderScheduler scheduler;

  setUp(() async {
    repository = _MemoryRepository();
    store = InMemorySettingsStore();
    settings = AppSettings(store);
    platform = FakeReminderPlatform(permissionGranted: true);
    scheduler = ReminderScheduler(
      repository: repository,
      settings: settings,
      platform: platform,
      now: () => DateTime(2026, 1, 1, 8),
    );
    await scheduler.initialize();
  });

  test('default 30 and 7 day reminders use local calendar 9am', () async {
    repository.items.add(_item('a', DayDate(2026, 3, 2)));

    expect(await scheduler.setEnabled(true), isTrue);

    expect(platform.permissionRequests, 1);
    expect(platform.scheduled.map((r) => r.localDateTime), [
      DateTime(2026, 1, 31, 9),
      DateTime(2026, 2, 23, 9),
    ]);
    expect(platform.scheduled.every((r) => r.itemId == 'a'), isTrue);
  });

  test('edit replaces the full upcoming set', () async {
    repository.items.add(_item('a', DayDate(2026, 3, 2)));
    await scheduler.setEnabled(true);
    repository.items[0] = _item('a', DayDate(2026, 4, 2));

    await scheduler.recompute();

    expect(platform.cancelAllCalls, 2);
    expect(platform.scheduled.first.localDateTime, DateTime(2026, 3, 3, 9));
  });

  test('delete cancels reminders by rebuilding from database', () async {
    repository.items.add(_item('a', DayDate(2026, 3, 2)));
    await scheduler.setEnabled(true);
    repository.items.clear();

    await scheduler.recompute();

    expect(platform.scheduled, isEmpty);
    expect(platform.cancelAllCalls, 2);
  });

  test('afterRestore exposes and performs a full reschedule', () async {
    await scheduler.setEnabled(true);
    repository.items.add(_item('restored', DayDate(2026, 5, 1)));

    await scheduler.afterRestore();

    expect(platform.scheduled, hasLength(2));
    expect(platform.scheduled.every((r) => r.itemId == 'restored'), isTrue);
  });

  test('per-item days horizon and watched kinds override defaults', () async {
    repository.items.add(
      PurchaseItem(
        id: 'a',
        name: 'Laptop',
        purchaseDate: DayDate(2025, 1, 1),
        coverageLines: [
          CoverageLine(
            kind: CoverageLineKind.returnWindow,
            basis: ExplicitEndDate(endDateValue: DayDate(2026, 1, 20)),
          ),
          CoverageLine(
            kind: CoverageLineKind.manufacturerWarranty,
            basis: ExplicitEndDate(endDateValue: DayDate(2026, 2, 15)),
          ),
        ],
      ),
    );
    await settings.setItemReminderOverride(
      'a',
      const ItemReminderOverride(
        daysBefore: [5],
        horizonDays: 30,
        watchedKinds: {CoverageLineKind.returnWindow},
      ),
    );

    await scheduler.setEnabled(true);

    expect(platform.scheduled, hasLength(1));
    expect(platform.scheduled.single.localDateTime, DateTime(2026, 1, 15, 9));
    expect(platform.scheduled.single.lineKind, CoverageLineKind.returnWindow);
  });

  test('OS cap keeps the earliest reminders deterministically', () async {
    for (var i = 0; i < ReminderScheduler.maxPendingReminders + 5; i++) {
      repository.items.add(_item('item-$i', DayDate(2026, 2, 1).addDays(i)));
    }

    await scheduler.setEnabled(true);

    expect(
      platform.scheduled,
      hasLength(ReminderScheduler.maxPendingReminders),
    );
    final dates = platform.scheduled.map((r) => r.localDateTime).toList();
    expect([...dates]..sort(), dates);
  });

  test('concurrent recomputations are serialized', () async {
    repository.items.add(_item('a', DayDate(2026, 3, 2)));
    platform.blockScheduling = true;
    final enable = scheduler.setEnabled(true);
    await platform.started.future;
    final second = scheduler.recompute();
    platform.release.complete();
    await Future.wait([enable, second]);

    expect(platform.maxConcurrentOperations, 1);
  });

  test(
    'notification plugin failure never rolls back successful CRUD',
    () async {
      final failingPlatform = _ThrowingReminderPlatform();
      final failingScheduler = ReminderScheduler(
        repository: repository,
        settings: settings,
        platform: failingPlatform,
        now: () => DateTime(2026, 1, 1, 8),
      );
      await failingScheduler.initialize();
      await settings.setRemindersEnabled(true);
      final wrapped = ReschedulingItemRepository(
        repository,
        failingScheduler,
        settings,
      );

      await wrapped.save(_item('saved', DayDate(2026, 3, 2)));
      expect(await repository.findById('saved'), isNotNull);
      expect(failingScheduler.lastError, isA<StateError>());

      expect(await wrapped.delete('saved'), isTrue);
      expect(await repository.findById('saved'), isNull);
    },
  );

  test('startup recomputes without requesting permission again', () async {
    repository.items.add(_item('a', DayDate(2026, 3, 2)));
    await settings.setRemindersEnabled(true);
    await settings.setReminderPermissionState(ReminderPermissionState.granted);
    final startupPlatform = FakeReminderPlatform(permissionGranted: true);
    final startupScheduler = ReminderScheduler(
      repository: repository,
      settings: settings,
      platform: startupPlatform,
      now: () => DateTime(2026, 1, 1, 8),
    );

    await startupScheduler.initialize();

    expect(startupPlatform.permissionRequests, 0);
    expect(startupPlatform.permissionChecks, 1);
    expect(startupPlatform.scheduled, hasLength(2));
  });

  test('revocation stops scheduling without prompting', () async {
    repository.items.add(_item('a', DayDate(2026, 3, 2)));
    await scheduler.setEnabled(true);
    platform.permissionGranted = false;

    await scheduler.recompute();

    expect(platform.permissionRequests, 1);
    expect(platform.scheduled, isEmpty);
    expect(settings.remindersEnabled, isTrue, reason: 'preserves user intent');
    expect(settings.reminderPermissionState, ReminderPermissionState.denied);
    expect(scheduler.isEnabled, isFalse);
  });

  test('external permission regrant restores persisted intent', () async {
    repository.items.add(_item('a', DayDate(2026, 3, 2)));
    await scheduler.setEnabled(true);
    platform.permissionGranted = false;
    await scheduler.recompute();
    platform.permissionGranted = true;

    await scheduler.recompute();

    expect(platform.permissionRequests, 1);
    expect(platform.scheduled, hasLength(2));
    expect(scheduler.isEnabled, isTrue);
  });

  test('every recompute refreshes the platform timezone', () async {
    final before = platform.timezoneRefreshes;

    await scheduler.recompute();

    expect(platform.timezoneRefreshes, before + 1);
  });

  test(
    'failure and recovery both notify listeners and clear lastError',
    () async {
      final recoveringPlatform = _RecoveringReminderPlatform();
      final recoveringScheduler = ReminderScheduler(
        repository: repository,
        settings: settings,
        platform: recoveringPlatform,
        now: () => DateTime(2026, 1, 1, 8),
      );
      var notifications = 0;
      recoveringScheduler.addListener(() => notifications++);
      await recoveringScheduler.initialize();
      await settings.setRemindersEnabled(true);
      repository.items.add(_item('recovering', DayDate(2026, 3, 2)));

      await recoveringScheduler.recompute();
      expect(recoveringScheduler.lastError, isA<StateError>());
      expect(notifications, 1);

      recoveringPlatform.fail = false;
      await recoveringScheduler.recompute();
      expect(recoveringScheduler.lastError, isNull);
      expect(notifications, 2);
    },
  );

  test('initialization failure remains visible across recompute', () async {
    final failedScheduler = ReminderScheduler(
      repository: repository,
      settings: settings,
      platform: _InitializationFailurePlatform(),
    );
    var notifications = 0;
    failedScheduler.addListener(() => notifications++);

    await failedScheduler.initialize();
    final setupError = failedScheduler.lastError;
    await failedScheduler.recompute();

    expect(setupError, isA<StateError>());
    expect(failedScheduler.lastError, same(setupError));
    expect(notifications, 1);
  });
}

PurchaseItem _item(String id, DayDate end) => PurchaseItem(
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

class _MemoryRepository implements ItemRepository {
  final List<PurchaseItem> items = [];

  @override
  Future<List<PurchaseItem>> list(ItemQuery query) async => [...items];

  @override
  Future<PurchaseItem?> findById(String id) async =>
      items.where((item) => item.id == id).firstOrNull;

  @override
  Future<void> save(PurchaseItem item) async {
    items.removeWhere((existing) => existing.id == item.id);
    items.add(item);
  }

  @override
  Future<bool> delete(String id) async {
    final before = items.length;
    items.removeWhere((item) => item.id == id);
    return before != items.length;
  }

  @override
  String newItemId() => 'new';

  @override
  Future<List<String>> categories() async => const [];
}

class _ThrowingReminderPlatform implements ReminderPlatform {
  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<void> cancelAll() async {
    throw StateError('plugin unavailable');
  }

  @override
  Future<String?> initialize(ReminderTapCallback onTap) async => null;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> refreshTimezone() async {}

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    throw StateError('plugin unavailable');
  }
}

class _RecoveringReminderPlatform implements ReminderPlatform {
  bool fail = true;

  @override
  Future<void> cancelAll() async {}

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<String?> initialize(ReminderTapCallback onTap) async => null;

  @override
  Future<void> refreshTimezone() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    if (fail) throw StateError('notification scheduling failed');
  }
}

class _InitializationFailurePlatform extends _RecoveringReminderPlatform {
  @override
  Future<String?> initialize(ReminderTapCallback onTap) async {
    throw StateError('notification initialization failed');
  }
}
