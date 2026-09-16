import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/coverage_line.dart';
import '../../domain/models/day_date.dart';
import '../../domain/repositories/item_repository.dart';
import '../settings/app_settings.dart';

typedef ReminderTapCallback = void Function(String? payload);

@immutable
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.itemId,
    required this.lineKind,
    required this.localDateTime,
    required this.title,
    required this.body,
  });

  final int id;
  final String itemId;
  final CoverageLineKind lineKind;
  final DateTime localDateTime;
  final String title;
  final String body;

  String get payload => 'item:$itemId';
}

abstract interface class ReminderPlatform {
  Future<String?> initialize(ReminderTapCallback onTap);
  Future<bool> checkPermission();
  Future<bool> requestPermission();
  Future<void> refreshTimezone();
  Future<void> cancelAll();
  Future<void> schedule(ScheduledReminder reminder);
}

class ReminderScheduler extends ChangeNotifier {
  ReminderScheduler({
    required ItemRepository repository,
    required this.settings,
    required ReminderPlatform platform,
    DateTime Function()? now,
  }) : // These remain public-facing named arguments while storage is private.
       // ignore: prefer_initializing_formals
       _repository = repository,
       // ignore: prefer_initializing_formals
       _platform = platform,
       _now = now ?? DateTime.now;

  /// Kept below iOS's 64-pending-notification ceiling so app-maintained
  /// notifications have a deterministic rolling window on every platform.
  static const int maxPendingReminders = 60;

  final ItemRepository _repository;
  final AppSettings settings;
  final ReminderPlatform _platform;
  final DateTime Function() _now;
  final ValueNotifier<String?> pendingItemTap = ValueNotifier(null);
  Future<void> _serial = Future.value();
  Object? _lastError;
  bool _platformReady = false;

  Object? get lastError => _lastError;

  bool get isEnabled =>
      settings.remindersEnabled &&
      settings.reminderPermissionState == ReminderPermissionState.granted;

  Future<void> initialize() async {
    try {
      final coldPayload = await _platform.initialize(_handlePayload);
      _platformReady = true;
      _handlePayload(coldPayload);
    } on Object catch (error) {
      _recordError(error);
    }
    if (settings.remindersEnabled) await recompute();
  }

  Future<bool> setEnabled(bool enabled) async {
    if (!enabled) {
      await settings.setRemindersEnabled(false);
      await recompute();
      return true;
    }
    if (isEnabled) return true;

    bool granted;
    try {
      granted = await _platform.requestPermission();
    } on Object catch (error) {
      _recordError(error);
      granted = false;
    }
    await settings.setReminderPermissionState(
      granted
          ? ReminderPermissionState.granted
          : ReminderPermissionState.denied,
    );
    if (granted) await settings.setRemindersEnabled(true);
    await recompute();
    return granted;
  }

  Future<void> recompute() {
    final completion = Completer<void>();
    _serial = _serial.then((_) async {
      try {
        await _recomputeNow();
        if (_platformReady) _setLastError(null);
      } on Object catch (error) {
        _recordError(error);
      } finally {
        completion.complete();
      }
    });
    return completion.future;
  }

  /// Stable restore integration point for issue #6.
  Future<void> afterRestore() => recompute();

  Future<void> _recomputeNow() async {
    if (!_platformReady) return;
    await _platform.cancelAll();
    await _platform.refreshTimezone();
    if (!settings.remindersEnabled) return;

    late final bool granted;
    try {
      granted = await _platform.checkPermission();
    } on Object {
      await settings.setReminderPermissionState(
        ReminderPermissionState.unknown,
      );
      rethrow;
    }
    await settings.setReminderPermissionState(
      granted
          ? ReminderPermissionState.granted
          : ReminderPermissionState.denied,
    );
    if (!granted) return;

    final current = _now();
    final today = DayDate.fromDateTime(current);
    final items = await _repository.list(
      ItemQuery(today: today, horizonDays: 3650, includeArchived: true),
    );
    final reminders = <ScheduledReminder>[];
    final identities = <String>{};
    for (final item in items) {
      if (item.archived) continue;
      final override = settings.itemReminderOverride(item.id);
      if (override?.enabled == false) continue;
      final days = override?.daysBefore ?? settings.defaultReminderDays;
      final horizon =
          override?.horizonDays ?? settings.defaultReminderHorizonDays;
      final watched = override?.watchedKinds ?? CoverageLineKind.values.toSet();
      for (final line in item.coverageLines) {
        if (!watched.contains(line.kind)) continue;
        final end = line.basis.endDate(item.purchaseDate);
        final daysToEnd = today.daysUntil(end);
        if (daysToEnd < 0 || daysToEnd > horizon) continue;
        for (final daysBefore in days) {
          final fireDay = end.addDays(-daysBefore);
          final localDateTime = DateTime(
            fireDay.year,
            fireDay.month,
            fireDay.day,
            9,
          );
          if (!localDateTime.isAfter(current)) continue;
          final identity = '${item.id}|${line.kind.name}|$end|$daysBefore';
          if (!identities.add(identity)) continue;
          reminders.add(
            ScheduledReminder(
              id: 0,
              itemId: item.id,
              lineKind: line.kind,
              localDateTime: localDateTime,
              title: '${item.name} coverage reminder',
              body:
                  '$daysBefore days until ${_kindName(line.kind)} ends on $end.',
            ),
          );
        }
      }
    }
    reminders.sort((a, b) {
      final byTime = a.localDateTime.compareTo(b.localDateTime);
      if (byTime != 0) return byTime;
      final byItem = a.itemId.compareTo(b.itemId);
      if (byItem != 0) return byItem;
      final byKind = a.lineKind.index.compareTo(b.lineKind.index);
      if (byKind != 0) return byKind;
      return a.body.compareTo(b.body);
    });
    final selected = reminders.take(maxPendingReminders).toList();
    for (var index = 0; index < selected.length; index++) {
      final reminder = selected[index];
      await _platform.schedule(
        ScheduledReminder(
          id: 1000 + index,
          itemId: reminder.itemId,
          lineKind: reminder.lineKind,
          localDateTime: reminder.localDateTime,
          title: reminder.title,
          body: reminder.body,
        ),
      );
    }
  }

  static String _kindName(CoverageLineKind kind) => switch (kind) {
    CoverageLineKind.returnWindow => 'return window',
    CoverageLineKind.manufacturerWarranty => 'manufacturer warranty',
    CoverageLineKind.extendedWarranty => 'extended warranty',
  };

  void _handlePayload(String? payload) {
    if (payload == null || !payload.startsWith('item:')) return;
    final itemId = payload.substring(5);
    if (itemId.isNotEmpty) pendingItemTap.value = itemId;
  }

  void consumePendingTap() => pendingItemTap.value = null;

  void _recordError(Object error) {
    _setLastError(error);
  }

  void _setLastError(Object? error) {
    if (identical(_lastError, error)) return;
    _lastError = error;
    notifyListeners();
  }

  @override
  void dispose() {
    pendingItemTap.dispose();
    super.dispose();
  }
}
