import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/domain/models/coverage_line.dart';
import 'package:warrant_book/features/settings/app_settings.dart';

void main() {
  test('global reminder settings round-trip', () async {
    final store = InMemorySettingsStore();
    final settings = AppSettings(store);
    await settings.setRemindersEnabled(true);
    await settings.setReminderPermissionState(ReminderPermissionState.granted);
    await settings.setDefaultReminderDays(const [45, 10, 3]);
    await settings.setDefaultReminderHorizonDays(180);

    final restored = await AppSettings.load(store);

    expect(restored.remindersEnabled, isTrue);
    expect(restored.reminderPermissionState, ReminderPermissionState.granted);
    expect(restored.defaultReminderDays, [45, 10, 3]);
    expect(restored.defaultReminderHorizonDays, 180);
  });

  test('per-item override round-trips and can be removed', () async {
    final store = InMemorySettingsStore();
    final settings = AppSettings(store);
    const override = ItemReminderOverride(
      enabled: false,
      daysBefore: [14, 2],
      horizonDays: 90,
      watchedKinds: {
        CoverageLineKind.returnWindow,
        CoverageLineKind.extendedWarranty,
      },
    );
    await settings.setItemReminderOverride('item-1', override);

    var restored = await AppSettings.load(store);
    expect(restored.itemReminderOverride('item-1'), override);

    await restored.setItemReminderOverride('item-1', null);
    restored = await AppSettings.load(store);
    expect(restored.itemReminderOverride('item-1'), isNull);
  });
}
