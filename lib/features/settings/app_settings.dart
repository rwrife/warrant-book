import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/coverage_line.dart';

abstract interface class SettingsStore {
  Future<int?> readInt(String key);
  Future<void> writeInt(String key, int value);
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
}

class SharedPreferencesSettingsStore implements SettingsStore {
  @override
  Future<int?> readInt(String key) async =>
      (await SharedPreferences.getInstance()).getInt(key);

  @override
  Future<void> writeInt(String key, int value) async {
    await (await SharedPreferences.getInstance()).setInt(key, value);
  }

  @override
  Future<String?> readString(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> writeString(String key, String value) async {
    await (await SharedPreferences.getInstance()).setString(key, value);
  }
}

class InMemorySettingsStore implements SettingsStore {
  final Map<String, Object> _values = {};

  @override
  Future<int?> readInt(String key) async => _values[key] as int?;

  @override
  Future<void> writeInt(String key, int value) async => _values[key] = value;

  @override
  Future<String?> readString(String key) async => _values[key] as String?;

  @override
  Future<void> writeString(String key, String value) async =>
      _values[key] = value;
}

enum ReminderPermissionState { unknown, granted, denied }

@immutable
class ItemReminderOverride {
  const ItemReminderOverride({
    this.enabled = true,
    required this.daysBefore,
    required this.horizonDays,
    required this.watchedKinds,
  });

  final bool enabled;
  final List<int> daysBefore;
  final int horizonDays;
  final Set<CoverageLineKind> watchedKinds;

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'daysBefore': daysBefore,
    'horizonDays': horizonDays,
    'watchedKinds': watchedKinds.map((kind) => kind.name).toList()..sort(),
  };

  factory ItemReminderOverride.fromJson(Map<String, Object?> json) =>
      ItemReminderOverride(
        enabled: json['enabled'] as bool? ?? true,
        daysBefore: _normalizeDays(
          (json['daysBefore'] as List<Object?>? ?? const [])
              .whereType<num>()
              .map((value) => value.toInt()),
        ),
        horizonDays: _clampReminderHorizon(
          (json['horizonDays'] as num?)?.toInt() ??
              AppSettings.defaultReminderHorizonDaysValue,
        ),
        watchedKinds: (json['watchedKinds'] as List<Object?>? ?? const [])
            .whereType<String>()
            .map(CoverageLineKind.values.byName)
            .toSet(),
      );

  @override
  bool operator ==(Object other) =>
      other is ItemReminderOverride &&
      other.enabled == enabled &&
      listEquals(other.daysBefore, daysBefore) &&
      setEquals(other.watchedKinds, watchedKinds) &&
      other.horizonDays == horizonDays;

  @override
  int get hashCode => Object.hash(
    enabled,
    Object.hashAll(daysBefore),
    Object.hashAll(watchedKinds.toList()..sort((a, b) => a.index - b.index)),
    horizonDays,
  );
}

class AppSettings extends ChangeNotifier {
  AppSettings(
    this._store, {
    int horizonDays = defaultHorizonDays,
    bool remindersEnabled = false,
    ReminderPermissionState reminderPermissionState =
        ReminderPermissionState.unknown,
    List<int> defaultReminderDays = const [30, 7],
    int defaultReminderHorizonDays = defaultReminderHorizonDaysValue,
    Map<String, ItemReminderOverride> itemReminderOverrides = const {},
  }) : _horizonDays = _clampHorizon(horizonDays),
       // Public constructor names intentionally omit implementation prefixes.
       // ignore: prefer_initializing_formals
       _remindersEnabled = remindersEnabled,
       // ignore: prefer_initializing_formals
       _reminderPermissionState = reminderPermissionState,
       _defaultReminderDays = _normalizeDays(defaultReminderDays),
       _defaultReminderHorizonDays = _clampReminderHorizon(
         defaultReminderHorizonDays,
       ),
       _itemReminderOverrides = Map.of(itemReminderOverrides);

  static const int defaultHorizonDays = 30;
  static const int minHorizonDays = 1;
  static const int maxHorizonDays = 365;
  static const int defaultReminderHorizonDaysValue = 365;
  static const String _horizonKey = 'expiring_soon_horizon_days';
  static const String _remindersKey = 'reminder_preferences_v1';

  final SettingsStore _store;
  int _horizonDays;
  bool _remindersEnabled;
  ReminderPermissionState _reminderPermissionState;
  List<int> _defaultReminderDays;
  int _defaultReminderHorizonDays;
  final Map<String, ItemReminderOverride> _itemReminderOverrides;

  int get horizonDays => _horizonDays;
  bool get remindersEnabled => _remindersEnabled;
  ReminderPermissionState get reminderPermissionState =>
      _reminderPermissionState;
  List<int> get defaultReminderDays => List.unmodifiable(_defaultReminderDays);
  int get defaultReminderHorizonDays => _defaultReminderHorizonDays;

  set horizonDays(int value) {
    final clamped = _clampHorizon(value);
    if (clamped == _horizonDays) return;
    _horizonDays = clamped;
    unawaited(_store.writeInt(_horizonKey, clamped));
    notifyListeners();
  }

  ItemReminderOverride? itemReminderOverride(String itemId) =>
      _itemReminderOverrides[itemId];

  Future<void> setRemindersEnabled(bool value) async {
    if (_remindersEnabled == value) return;
    _remindersEnabled = value;
    await _persistReminders();
    notifyListeners();
  }

  Future<void> setReminderPermissionState(ReminderPermissionState value) async {
    if (_reminderPermissionState == value) return;
    _reminderPermissionState = value;
    await _persistReminders();
    notifyListeners();
  }

  Future<void> setDefaultReminderDays(Iterable<int> values) async {
    final normalized = _normalizeDays(values);
    if (listEquals(normalized, _defaultReminderDays)) return;
    _defaultReminderDays = normalized;
    await _persistReminders();
    notifyListeners();
  }

  Future<void> setDefaultReminderHorizonDays(int value) async {
    final normalized = _clampReminderHorizon(value);
    if (normalized == _defaultReminderHorizonDays) return;
    _defaultReminderHorizonDays = normalized;
    await _persistReminders();
    notifyListeners();
  }

  Future<void> setItemReminderOverride(
    String itemId,
    ItemReminderOverride? value,
  ) async {
    if (value == null) {
      _itemReminderOverrides.remove(itemId);
    } else {
      _itemReminderOverrides[itemId] = ItemReminderOverride(
        enabled: value.enabled,
        daysBefore: _normalizeDays(value.daysBefore),
        horizonDays: _clampReminderHorizon(value.horizonDays),
        watchedKinds: Set.of(value.watchedKinds),
      );
    }
    await _persistReminders();
    notifyListeners();
  }

  Future<void> removeItemReminderOverride(String itemId) =>
      setItemReminderOverride(itemId, null);

  Future<void> _persistReminders() async {
    await _store.writeString(
      _remindersKey,
      jsonEncode({
        'enabled': _remindersEnabled,
        'permission': _reminderPermissionState.name,
        'defaultDays': _defaultReminderDays,
        'defaultHorizonDays': _defaultReminderHorizonDays,
        'items': _itemReminderOverrides.map(
          (id, override) => MapEntry(id, override.toJson()),
        ),
      }),
    );
  }

  static Future<AppSettings> load(SettingsStore store) async {
    final horizon = await store.readInt(_horizonKey);
    final raw = await store.readString(_remindersKey);
    if (raw == null) {
      return AppSettings(store, horizonDays: horizon ?? defaultHorizonDays);
    }
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final itemJson = json['items'] as Map<String, Object?>? ?? const {};
      return AppSettings(
        store,
        horizonDays: horizon ?? defaultHorizonDays,
        remindersEnabled: json['enabled'] as bool? ?? false,
        reminderPermissionState: ReminderPermissionState.values.byName(
          json['permission'] as String? ?? ReminderPermissionState.unknown.name,
        ),
        defaultReminderDays:
            (json['defaultDays'] as List<Object?>? ?? const [30, 7])
                .whereType<num>()
                .map((value) => value.toInt())
                .toList(),
        defaultReminderHorizonDays:
            (json['defaultHorizonDays'] as num?)?.toInt() ??
            defaultReminderHorizonDaysValue,
        itemReminderOverrides: itemJson.map(
          (id, value) => MapEntry(
            id,
            ItemReminderOverride.fromJson(value as Map<String, Object?>),
          ),
        ),
      );
    } on Object {
      return AppSettings(store, horizonDays: horizon ?? defaultHorizonDays);
    }
  }

  static int _clampHorizon(int value) =>
      value.clamp(minHorizonDays, maxHorizonDays);
}

List<int> _normalizeDays(Iterable<int> values) {
  final normalized = values
      .where((value) => value >= 0 && value <= 3650)
      .toSet();
  return normalized.toList()..sort((a, b) => b.compareTo(a));
}

int _clampReminderHorizon(int value) => value.clamp(1, 3650);
