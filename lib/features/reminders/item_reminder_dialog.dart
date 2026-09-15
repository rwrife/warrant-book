import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/models/coverage_line.dart';
import '../../domain/models/purchase_item.dart';
import '../../l10n/generated/app_localizations.dart';
import '../settings/app_settings.dart';

Future<void> showItemReminderDialog(BuildContext context, PurchaseItem item) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ItemReminderDialog(item: item),
    );

class _ItemReminderDialog extends StatefulWidget {
  const _ItemReminderDialog({required this.item});

  final PurchaseItem item;

  @override
  State<_ItemReminderDialog> createState() => _ItemReminderDialogState();
}

class _ItemReminderDialogState extends State<_ItemReminderDialog> {
  late bool _enabled;
  late Set<CoverageLineKind> _watchedKinds;
  late final TextEditingController _days;
  late final TextEditingController _horizon;

  @override
  void initState() {
    super.initState();
    final settings = AppScope.read(context).settings;
    final override = settings.itemReminderOverride(widget.item.id);
    _enabled = override?.enabled ?? true;
    _watchedKinds = Set.of(override?.watchedKinds ?? CoverageLineKind.values);
    _days = TextEditingController(
      text: (override?.daysBefore ?? settings.defaultReminderDays).join(', '),
    );
    _horizon = TextEditingController(
      text: '${override?.horizonDays ?? settings.defaultReminderHorizonDays}',
    );
  }

  @override
  void dispose() {
    _days.dispose();
    _horizon.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final scope = AppScope.read(context);
    final parsedDays = _days.text
        .split(',')
        .map((part) => int.tryParse(part.trim()))
        .whereType<int>()
        .toList();
    final horizon = int.tryParse(_horizon.text);
    if (parsedDays.isEmpty || horizon == null) return;
    await scope.settings.setItemReminderOverride(
      widget.item.id,
      ItemReminderOverride(
        enabled: _enabled,
        daysBefore: parsedDays,
        horizonDays: horizon,
        watchedKinds: _watchedKinds,
      ),
    );
    final scheduler = scope.reminderScheduler;
    if (scheduler != null) await scheduler.recompute();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.itemReminderSettings),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              key: const Key('itemRemindersEnabled'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.itemRemindersEnabled),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            TextField(
              key: const Key('itemReminderDaysField'),
              controller: _days,
              decoration: InputDecoration(labelText: l10n.reminderDaysLabel),
            ),
            TextField(
              key: const Key('itemReminderHorizonField'),
              controller: _horizon,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l10n.reminderHorizonLabel),
            ),
            for (final kind in CoverageLineKind.values)
              CheckboxListTile(
                key: Key('watch-${kind.name}'),
                contentPadding: EdgeInsets.zero,
                title: Text(_kindLabel(l10n, kind)),
                value: _watchedKinds.contains(kind),
                onChanged: (value) => setState(() {
                  if (value ?? false) {
                    _watchedKinds.add(kind);
                  } else {
                    _watchedKinds.remove(kind);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('saveItemReminderButton'),
          onPressed: () => unawaited(_save()),
          child: Text(l10n.save),
        ),
      ],
    );
  }

  static String _kindLabel(AppLocalizations l10n, CoverageLineKind kind) =>
      switch (kind) {
        CoverageLineKind.returnWindow => l10n.kindReturnWindow,
        CoverageLineKind.manufacturerWarranty => l10n.kindManufacturerWarranty,
        CoverageLineKind.extendedWarranty => l10n.kindExtendedWarranty,
      };
}
