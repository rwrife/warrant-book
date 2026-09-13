// Warrant Book — settings dialog (issue #4).
//
// Exposes the single MVP app setting: the expiring-soon horizon in days.
// Writes flow through AppSettings (which clamps and persists), so the
// lists and the domain math always agree on the horizon.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../l10n/generated/app_localizations.dart';

/// Shows the settings dialog.
Future<void> showSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: '${AppScope.read(context).settings.horizonDays}',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsAction),
      content: TextField(
        key: const Key('horizonField'),
        controller: _controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: l10n.settingsHorizonLabel),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('saveHorizonButton'),
          onPressed: () {
            final value = int.tryParse(_controller.text);
            if (value != null) {
              AppScope.of(context).settings.horizonDays = value;
            }
            Navigator.of(context).pop();
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
