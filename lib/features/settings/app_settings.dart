// Warrant Book — app-level settings (issue #4).
//
// The only user-tunable app setting in this slice is the "expiring soon"
// horizon (default 30 days per issue #4). It is persisted through a tiny
// storage interface so widget tests never touch platform channels
// (`shared_preferences` would need `SharedPreferences.setMockInitialValues`
// at every test boundary; an in-memory store is explicit and honest).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Key-value persistence for integer settings.
abstract interface class SettingsStore {
  /// Stored value for [key], or null when never written.
  Future<int?> readInt(String key);

  /// Persists [value] under [key].
  Future<void> writeInt(String key, int value);
}

/// Backed by `shared_preferences` (production wiring).
class SharedPreferencesSettingsStore implements SettingsStore {
  @override
  Future<int?> readInt(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key);
  }

  @override
  Future<void> writeInt(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }
}

/// Plain map-backed store for widget/unit tests.
class InMemorySettingsStore implements SettingsStore {
  final Map<String, int> _values = {};

  @override
  Future<int?> readInt(String key) async => _values[key];

  @override
  Future<void> writeInt(String key, int value) async => _values[key] = value;
}

/// App-wide observable settings.
///
/// Listenable so list screens recompute statuses when the horizon changes,
/// keeping "expiring soon" consistent with what the domain math sees.
class AppSettings extends ChangeNotifier {
  AppSettings(this._store, {int horizonDays = defaultHorizonDays})
      : _horizonDays = _clampHorizon(horizonDays);

  /// Issue #4: default expiring-soon horizon is 30 days.
  static const int defaultHorizonDays = 30;

  /// Bounds accepted for user-entered horizons.
  static const int minHorizonDays = 1;
  static const int maxHorizonDays = 365;

  static const String _horizonKey = 'expiring_soon_horizon_days';

  final SettingsStore _store;
  int _horizonDays;

  /// Days ahead within which a coverage line counts as "expiring".
  int get horizonDays => _horizonDays;

  set horizonDays(int value) {
    final clamped = _clampHorizon(value);
    if (clamped == _horizonDays) return;
    _horizonDays = clamped;
    unawaited(_store.writeInt(_horizonKey, clamped));
    notifyListeners();
  }

  /// Loads persisted settings, falling back to defaults.
  static Future<AppSettings> load(SettingsStore store) async {
    final stored = await store.readInt(_horizonKey);
    return AppSettings(store, horizonDays: stored ?? defaultHorizonDays);
  }

  static int _clampHorizon(int value) =>
      value.clamp(minHorizonDays, maxHorizonDays);
}
