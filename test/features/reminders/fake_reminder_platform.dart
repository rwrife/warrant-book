import 'dart:async';

import 'package:warrant_book/features/reminders/reminder_scheduler.dart';

class FakeReminderPlatform implements ReminderPlatform {
  FakeReminderPlatform({this.permissionGranted = true, this.coldStartPayload});

  bool permissionGranted;
  String? coldStartPayload;
  int permissionRequests = 0;
  int permissionChecks = 0;
  int timezoneRefreshes = 0;
  int cancelAllCalls = 0;
  final List<ScheduledReminder> scheduled = [];
  ReminderTapCallback? _onTap;
  bool blockScheduling = false;
  Object? cancelError;
  final Completer<void> started = Completer();
  final Completer<void> release = Completer();
  int _concurrentOperations = 0;
  int maxConcurrentOperations = 0;

  @override
  Future<String?> initialize(ReminderTapCallback onTap) async {
    _onTap = onTap;
    return coldStartPayload;
  }

  void tap(String itemId) => _onTap?.call('item:$itemId');

  @override
  Future<bool> checkPermission() async {
    permissionChecks++;
    return permissionGranted;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<void> refreshTimezone() async => timezoneRefreshes++;

  @override
  Future<void> cancelAll() async {
    if (cancelError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    _enter();
    scheduled.clear();
    cancelAllCalls++;
    _leave();
  }

  @override
  Future<void> schedule(ScheduledReminder reminder) async {
    _enter();
    if (blockScheduling && !release.isCompleted) {
      if (!started.isCompleted) started.complete();
      await release.future;
    }
    scheduled.add(reminder);
    _leave();
  }

  void _enter() {
    _concurrentOperations++;
    maxConcurrentOperations = _concurrentOperations > maxConcurrentOperations
        ? _concurrentOperations
        : maxConcurrentOperations;
  }

  void _leave() => _concurrentOperations--;
}
