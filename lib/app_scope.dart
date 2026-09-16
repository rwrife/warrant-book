// Warrant Book — dependency scope (issue #4).
//
// A single InheritedWidget carrying the three things every screen needs:
// the repository, the observable app settings, and a fixed "today" for
// status computation. Tests construct `WarrantBookApp` with an in-memory
// repository and a synthetic day; production injects the real database via
// `main()`. Screens never reach for globals — `AppScope.of(context)` is the
// only access path.

import 'package:flutter/widgets.dart';

import 'domain/models/day_date.dart';
import 'domain/repositories/item_repository.dart';
import 'features/reminders/reminder_scheduler.dart';
import 'features/settings/app_settings.dart';

/// Read-only app services shared down the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({
    required this.repository,
    required this.settings,
    required this.today,
    this.reminderScheduler,
    required super.child,
    super.key,
  });

  final ItemRepository repository;
  final AppSettings settings;
  final ReminderScheduler? reminderScheduler;

  /// The calendar day all statuses are evaluated against. Injectable so
  /// widget tests can freeze time deterministically.
  final DayDate today;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found above this widget');
    return scope!;
  }

  /// Non-subscribing read for `initState`, where `of` is not allowed yet.
  static AppScope read(BuildContext context) {
    final scope =
        context.getElementForInheritedWidgetOfExactType<AppScope>()?.widget
            as AppScope?;
    assert(scope != null, 'No AppScope found above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      repository != oldWidget.repository ||
      settings != oldWidget.settings ||
      reminderScheduler != oldWidget.reminderScheduler ||
      today != oldWidget.today;
}
