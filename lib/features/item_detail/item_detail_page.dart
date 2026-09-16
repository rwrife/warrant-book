// Warrant Book — item detail (issue #4).
//
// Shows purchase facts, every coverage line with its computed status chip
// and end date, and the add-only notes timeline. Edit reuses the add form
// (the repository replaces the whole aggregate); archive toggles the
// `archived` flag; delete confirms first — a local-first app with no
// backups yet (issue #6) must not offer a silent destructive action.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/coverage.dart';
import '../../domain/models/coverage_line.dart';
import '../../domain/models/purchase_item.dart';
import '../../l10n/generated/app_localizations.dart';
import '../add_edit/item_form_page.dart';
import '../items/widgets.dart';
import '../reminders/item_reminder_dialog.dart';

/// Detail screen for one purchase item, resolved from [itemId] on every
/// rebuild so edits/archives/deletes from any path are reflected.
class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({required this.itemId, super.key});

  final String itemId;

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  late Future<PurchaseItem?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = AppScope.read(context).repository.findById(widget.itemId);
  }

  Future<void> _reloadAsync() async {
    setState(_reload);
    await _future;
  }

  Future<void> _openEdit(PurchaseItem item) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ItemFormPage(existing: item)),
    );
    if (changed == true) await _reloadAsync();
  }

  Future<void> _toggleArchive(PurchaseItem item) async {
    final scope = AppScope.of(context);
    await scope.repository.save(_copyOf(
      item,
      archived: !item.archived,
    ));
    await _reloadAsync();
  }

  Future<void> _delete(PurchaseItem item) async {
    final l10n = AppLocalizations.of(context);
    final scope = AppScope.read(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteConfirmTitle),
        content: Text(l10n.deleteConfirmMessage(item.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirmDeleteButton'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await scope.repository.delete(item.id);
    // Pop back to the list, telling it to refresh.
    navigator.pop(true);
  }

  static PurchaseItem _copyOf(PurchaseItem item, {required bool archived}) =>
      PurchaseItem(
        id: item.id,
        name: item.name,
        purchaseDate: item.purchaseDate,
        category: item.category,
        store: item.store,
        price: item.price,
        coverageLines: item.coverageLines,
        notes: item.notes,
        attachments: item.attachments,
        archived: archived,
      );

  Future<void> _addNote(PurchaseItem item, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final scope = AppScope.of(context);
    await scope.repository.save(PurchaseItem(
      id: item.id,
      name: item.name,
      purchaseDate: item.purchaseDate,
      category: item.category,
      store: item.store,
      price: item.price,
      coverageLines: item.coverageLines,
      notes: [
        ...item.notes,
        Note(text: trimmed, recordedOn: scope.today),
      ],
      attachments: item.attachments,
      archived: item.archived,
    ));
    await _reloadAsync();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PurchaseItem?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final item = snapshot.data;
        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: SizedBox.shrink()),
          );
        }
        return _DetailScaffold(
          item: item,
          onEdit: () => _openEdit(item),
          onToggleArchive: () => _toggleArchive(item),
          onDelete: () => _delete(item),
          onAddNote: (text) => _addNote(item, text),
        );
      },
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.item,
    required this.onEdit,
    required this.onToggleArchive,
    required this.onDelete,
    required this.onAddNote,
  });

  final PurchaseItem item;
  final Future<void> Function() onEdit;
  final Future<void> Function() onToggleArchive;
  final Future<void> Function() onDelete;
  final Future<void> Function(String text) onAddNote;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = AppScope.of(context);
    final statuses = allLineStatuses(item, scope.today,
        horizonDays: scope.settings.horizonDays);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<String>(
            key: const Key('detailMenu'),
            tooltip: l10n.moreActions,
            onSelected: (value) {
              unawaited(switch (value) {
                'edit' => onEdit(),
                'reminders' => showItemReminderDialog(context, item),
                'archive' => onToggleArchive(),
                'delete' => onDelete(),
                _ => Future<void>.value(),
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('detailMenuReminders'),
                value: 'reminders',
                child: Text(l10n.itemReminderSettings),
              ),
              PopupMenuItem(
                key: const Key('detailMenuEdit'),
                value: 'edit',
                child: Text(l10n.editItem),
              ),
              PopupMenuItem(
                key: const Key('detailMenuArchive'),
                value: 'archive',
                child: Text(item.archived
                    ? l10n.unarchiveAction
                    : l10n.archiveAction),
              ),
              PopupMenuItem(
                key: const Key('detailMenuDelete'),
                value: 'delete',
                child: Text(l10n.delete),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (item.archived)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.archivedBadge,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          Text(l10n.purchaseInfoSection,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          _InfoRow(label: l10n.fieldPurchaseDate, value: '${item.purchaseDate}'),
          if (item.category != null)
            _InfoRow(label: l10n.fieldCategory, value: item.category!),
          if (item.store != null)
            _InfoRow(label: l10n.fieldStore, value: item.store!),
          _InfoRow(
            label: l10n.fieldPrice,
            value: item.price.isMissing
                ? l10n.priceNotRecorded
                : l10n.priceDisplay(
                    item.price.amount!.toStringAsFixed(2),
                    item.price.currencyCode!),
          ),
          const Divider(height: 32),
          Text(l10n.coverageLinesSection,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (statuses.isEmpty)
            Text(l10n.statusNone,
                style: Theme.of(context).textTheme.bodyMedium)
          else
            for (final status in statuses)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_kindLabel(l10n, status.line.kind)}'
                        '${status.line.label == null ? '' : ' — ${status.line.label}'}'
                        '\n${l10n.endsOn('${status.endDate}')}'
                        ' · ${remainingLabel(l10n, status)}',
                      ),
                    ),
                    StatusChip(status.status),
                  ],
                ),
              ),
          const Divider(height: 32),
          Text(l10n.notesSection,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          if (item.notes.isEmpty)
            Text(l10n.emptyNotes)
          else
            for (final note in item.notes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${note.recordedOn}  ',
                        style: Theme.of(context).textTheme.bodySmall),
                    Expanded(child: Text(note.text)),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          _AddNoteRow(onAdd: onAddNote),
        ],
      ),
    );
  }

  static String _kindLabel(AppLocalizations l10n, CoverageLineKind kind) =>
      switch (kind) {
        CoverageLineKind.returnWindow => l10n.kindReturnWindow,
        CoverageLineKind.manufacturerWarranty =>
          l10n.kindManufacturerWarranty,
        CoverageLineKind.extendedWarranty => l10n.kindExtendedWarranty,
      };
}

class _AddNoteRow extends StatefulWidget {
  const _AddNoteRow({required this.onAdd});

  final Future<void> Function(String text) onAdd;

  @override
  State<_AddNoteRow> createState() => _AddNoteRowState();
}

class _AddNoteRowState extends State<_AddNoteRow> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const Key('noteField'),
            controller: _controller,
            decoration: InputDecoration(
              hintText: l10n.noteHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const Key('addNoteButton'),
          icon: const Icon(Icons.send),
          tooltip: l10n.addNote,
          onPressed: () {
            final text = _controller.text;
            _controller.clear();
            unawaited(widget.onAdd(text));
          },
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
