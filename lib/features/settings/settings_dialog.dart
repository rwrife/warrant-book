import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../l10n/generated/app_localizations.dart';
import '../reminders/reminder_scheduler.dart';
import 'app_settings.dart';

Future<void> showSettingsDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SettingsDialog());

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _horizon;
  late final TextEditingController _reminderDays;
  late final TextEditingController _reminderHorizon;
  bool _changingPermission = false;
  ReminderScheduler? _scheduler;
  late final AppSettings _settings;

  @override
  void initState() {
    super.initState();
    final settings = AppScope.read(context).settings;
    _settings = settings..addListener(_onSettingsChanged);
    _scheduler = AppScope.read(context).reminderScheduler
      ?..addListener(_onSchedulerChanged);
    _horizon = TextEditingController(text: '${settings.horizonDays}');
    _reminderDays = TextEditingController(
      text: settings.defaultReminderDays.join(', '),
    );
    _reminderHorizon = TextEditingController(
      text: '${settings.defaultReminderHorizonDays}',
    );
  }

  @override
  void dispose() {
    _scheduler?.removeListener(_onSchedulerChanged);
    _settings.removeListener(_onSettingsChanged);
    _horizon.dispose();
    _reminderDays.dispose();
    _reminderHorizon.dispose();
    super.dispose();
  }

  void _onSchedulerChanged() {
    if (mounted) setState(() {});
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleReminders(bool enabled) async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    setState(() => _changingPermission = true);
    await scheduler.setEnabled(enabled);
    if (mounted) setState(() => _changingPermission = false);
  }

  Future<void> _save() async {
    final scope = AppScope.read(context);
    final horizon = int.tryParse(_horizon.text);
    if (horizon != null) scope.settings.horizonDays = horizon;
    final days = _reminderDays.text
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>();
    if (days.isNotEmpty) await scope.settings.setDefaultReminderDays(days);
    final reminderHorizon = int.tryParse(_reminderHorizon.text);
    if (reminderHorizon != null) {
      await scope.settings.setDefaultReminderHorizonDays(reminderHorizon);
    }
    final scheduler = scope.reminderScheduler;
    if (scheduler != null) await scheduler.recompute();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = AppScope.of(context).settings;
    final permissionDenied =
        settings.reminderPermissionState == ReminderPermissionState.denied;
    final schedulingError = _scheduler?.lastError;
    return AlertDialog(
      title: Text(l10n.settingsAction),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('horizonField'),
              controller: _horizon,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l10n.settingsHorizonLabel),
            ),
            const Divider(height: 32),
            SwitchListTile(
              key: const Key('remindersSwitch'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.remindersEnable),
              subtitle: Text(l10n.remindersPermissionTiming),
              value: _scheduler?.isEnabled ?? false,
              onChanged: _changingPermission ? null : _toggleReminders,
            ),
            if (permissionDenied)
              Text(
                l10n.remindersPermissionDenied,
                key: const Key('permissionDeniedMessage'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (schedulingError != null)
              Text(
                l10n.remindersSchedulingError('$schedulingError'),
                key: const Key('reminderSchedulingError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('defaultReminderDaysField'),
              controller: _reminderDays,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(labelText: l10n.reminderDaysLabel),
            ),
            TextField(
              key: const Key('defaultReminderHorizonField'),
              controller: _reminderHorizon,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: l10n.reminderHorizonLabel),
            ),
            const SizedBox(height: 12),
            Text(l10n.remindersSourceOfTruth),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('saveHorizonButton'),
          onPressed: () => unawaited(_save()),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
