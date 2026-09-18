// Warrant Book — data & privacy settings (issue #6).
//
// The ownership-boundary screen: CSV export via the OS share sheet, ZIP
// backup, restore from a chosen ZIP (with the manifest summary and an
// explicit destructive-overwrite confirmation), and erase-all with a
// typed-safe double confirm. Every action reports its real outcome (or
// the service's exact error text) inline — no silent success, no silent
// failure.

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_scope.dart';
import '../../data/backup/backup_service.dart';
import '../../data/lifecycle/data_lifecycle_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../attachments/attachment_picker.dart';

Future<void> showDataSettingsDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (_) => const DataSettingsDialog(),
    );

class DataSettingsDialog extends StatefulWidget {
  const DataSettingsDialog({this.shareFile, super.key});

  final FileShareCallback? shareFile;

  @override
  State<DataSettingsDialog> createState() => _DataSettingsDialogState();
}

class _DataSettingsDialogState extends State<DataSettingsDialog> {
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
      _statusIsError = false;
    });
    try {
      final message = await action();
      if (mounted) setState(() => _status = message);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _statusIsError = true;
          _status = error is BackupException
              ? error.message
              : error is RestoreCancelledException
                  // Cancellation is not an error state — say nothing scary.
                  ? AppLocalizations.of(context).restoreCancelled
                  : '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() => _run(() async {
        final l10n = AppLocalizations.of(context);
        final scope = AppScope.read(context);
        final lifecycle = scope.lifecycle!;
        final share = widget.shareFile ?? scope.fileSharer ?? _platformShare;
        final file =
            lifecycle.writeCsvExportFile(await lifecycle.buildCsv());
        await share(file.path);
        return l10n.exportShared;
      });

  Future<void> _backup() => _run(() async {
        final l10n = AppLocalizations.of(context);
        final scope = AppScope.read(context);
        final lifecycle = scope.lifecycle!;
        final share = widget.shareFile ?? scope.fileSharer ?? _platformShare;
        final result = await lifecycle.createBackup();
        await share(result.file.path);
        return l10n.backupCreated(result.file.path);
      });

  static Future<void> _platformShare(String path) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)]),
    );
  }

  Future<void> _restore() => _run(() async {
        final l10n = AppLocalizations.of(context);
        final lifecycle = AppScope.read(context).lifecycle!;
        final picked = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['zip'],
        );
        final path = picked.isEmpty ? null : picked.first.path;
        if (path == null) {
          return l10n.restoreCancelled;
        }
        await lifecycle.restoreFrom(
          zipPath: path,
          confirmOverwrite: (manifest) async {
            if (!mounted) return false;
            return await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(l10n.restoreConfirmTitle),
                    content: Text(
                      l10n.restoreConfirmMessage(
                        '${manifest.schemaVersion}',
                        manifest.createdUtcIso,
                        '${manifest.files.length - 1}',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(false),
                        child: Text(l10n.cancel),
                      ),
                      FilledButton(
                        key: const Key('confirmRestoreButton'),
                        style:
                            FilledButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(true),
                        child: Text(l10n.restoreAction),
                      ),
                    ],
                  ),
                ) ??
                false;
          },
        );
        return l10n.restoreApplied;
      });

  Future<void> _eraseAll() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final lifecycle = AppScope.read(context).lifecycle!;
    final navigator = Navigator.of(context);
    // The confirmation gate runs OUTSIDE the busy state — waiting on the
    // user is not work, and a busy spinner behind a modal dialog would
    // pin the UI (and never settle) for as long as the dialog is open.
    final confirmed = await showDialog<bool>(
          context: navigator.context,
          builder: (dialogContext) => _EraseConfirmDialog(
            onConfirmed: () => Navigator.of(dialogContext).pop(true),
          ),
        ) ??
        false;
    if (!mounted) return;
    if (!confirmed) {
      setState(() {
        _status = l10n.restoreCancelled;
        _statusIsError = false;
      });
      return;
    }
    await _run(() async {
      await lifecycle.eraseAll();
      return l10n.eraseDone;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasLifecycle = AppScope.of(context).lifecycle != null;
    return AlertDialog(
      title: Text(l10n.dataSettingsTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.dataSettingsIntro,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            for (final (key, icon, label, action) in [
              (
                const Key('exportCsvButton'),
                Icons.table_chart_outlined,
                l10n.exportCsvAction,
                _exportCsv
              ),
              (
                const Key('backupButton'),
                Icons.archive_outlined,
                l10n.backupAction,
                _backup
              ),
              (
                const Key('restoreButton'),
                Icons.unarchive_outlined,
                l10n.restoreAction,
                _restore
              ),
            ])
              ListTile(
                key: key,
                leading: Icon(icon),
                title: Text(label),
                enabled: hasLifecycle && !_busy,
                onTap: action,
              ),
            const Divider(),
            ListTile(
              key: const Key('eraseAllButton'),
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l10n.eraseAllAction,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              enabled: hasLifecycle && !_busy,
              onTap: _eraseAll,
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            if (_status != null)
              Padding(
                key: const Key('dataStatusMessage'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _status!,
                  style: TextStyle(
                    color: _statusIsError
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

/// Erase-all gets an explicit acknowledgement (issue #6: "with
/// confirmation") — a checkbox gate, not just an OK button.
class _EraseConfirmDialog extends StatefulWidget {
  const _EraseConfirmDialog({required this.onConfirmed});

  final VoidCallback onConfirmed;

  @override
  State<_EraseConfirmDialog> createState() => _EraseConfirmDialogState();
}

class _EraseConfirmDialogState extends State<_EraseConfirmDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.eraseAllConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.eraseAllConfirmMessage),
          CheckboxListTile(
            key: const Key('eraseAcknowledge'),
            value: _acknowledged,
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.eraseAcknowledgeLabel),
            onChanged: (value) =>
                setState(() => _acknowledged = value ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('confirmEraseButton'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _acknowledged ? widget.onConfirmed : null,
          child: Text(l10n.eraseAllAction),
        ),
      ],
    );
  }
}
