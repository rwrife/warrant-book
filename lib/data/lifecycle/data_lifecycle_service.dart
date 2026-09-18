// Warrant Book — data layer (issue #6).
//
// One service behind every user-owned-data lifecycle action the UI offers:
// CSV export, ZIP backup, verified restore, and erase-all. It orchestrates
// the DB, attachment store, settings, and the (optional) reminder
// scheduler, and knows nothing about Flutter — the UI wires the buttons.
//
// Invariants:
// - Restore refuses BEFORE touching live data (manifest, hashes, and
//   version checks all happen while staging).
// - Erase-all removes rows, files, preferences, and cancels notification
//   schedules — every owned byte on the device.
// - Reminders are re-derived from committed state: after a restore,
//   [restoreFrom] re-runs the scheduler (#5's afterRestore hook), never
//   replaying stale schedules from the backup.

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/export/csv_export.dart';
import '../../domain/models/day_date.dart';
import '../../domain/models/purchase_item.dart';
import '../../domain/repositories/item_repository.dart';
import '../../features/reminders/reminder_scheduler.dart';
import '../../features/settings/app_settings.dart';
import '../attachments/attachment_store.dart';
import '../backup/backup_service.dart';
import '../db/app_database.dart';

/// Everything needed to run the lifecycle service against one installation.
class DataLifecycleService {
  DataLifecycleService({
    required WarrantBookDatabase db,
    required ItemRepository repository,
    required AttachmentStore attachments,
    required AppSettings settings,
    required String documentsDir,
    this.reminderScheduler,
    Future<void> Function()? onChanged,
  }) : // These are named public-facing arguments; storage fields are
       // private (matching the existing scheduler/settings convention).
       // ignore: prefer_initializing_formals
       _db = db,
       // ignore: prefer_initializing_formals
       _repository = repository,
       _attachments = attachments,
       // ignore: prefer_initializing_formals
       _settings = settings,
       // ignore: prefer_initializing_formals
       _documentsDir = documentsDir,
       // ignore: prefer_initializing_formals
       _onChanged = onChanged,
       _backup = BackupService(
         attachments,
         WarrantBookDatabase.currentSchemaVersion,
       );

  final WarrantBookDatabase _db;
  final ItemRepository _repository;
  final AttachmentStore _attachments;
  final AppSettings _settings;
  final BackupService _backup;
  final String _documentsDir;
  final ReminderScheduler? reminderScheduler;
  final Future<void> Function()? _onChanged;

  Future<void> _notifyChanged() => _onChanged?.call() ?? Future.value();

  // ---- CSV export ------------------------------------------------------

  /// Renders the full registry (all items incl. archived, all coverage
  /// lines) as CSV text. ISO dates and ISO-4217 codes only.
  Future<String> buildCsv() async {
    final items = await _repository.list(
      ItemQuery(
        today: DayDate.fromDateTime(DateTime.now()),
        horizonDays: 3650,
        includeArchived: true,
      ),
    );
    return registryCsv(items);
  }

  /// Writes [csv] to a shareable file under the documents dir and returns
  /// its path (the UI hands it to the OS share sheet). The file is named
  /// with a UTC stamp so repeated exports never clobber each other.
  /// Sync IO: runs inside the dialog's fake-async zone in widget tests.
  File writeCsvExportFile(String csv) {
    final stamp =
        DateTime.now().toUtc().toIso8601String().split(':').join('-');
    final file = File(p.join(_documentsDir, 'exports',
        'warrant-book-$stamp.csv'))
      ..createSync(recursive: true)
      ..writeAsStringSync(csv);
    return file;
  }

  // ---- Attachments -----------------------------------------------------

  /// Absolute path of a stored attachment (for previews and sharing).
  String attachmentAbsolutePath(String relativePath) =>
      _attachments.absolutePath(relativePath);

  /// Copies bytes from [sourcePath] into the content-addressed store and
  /// adds the reference to item [itemId] (deduplicated by content hash).
  /// Returns the updated item, or null when the item no longer exists.
  Future<PurchaseItem?> attachToFile({
    required String itemId,
    required String sourcePath,
    String? displayName,
  }) async {
    final item = await _repository.findById(itemId);
    if (item == null) return null;
    final stored = _attachments.attachFileSync(
      sourcePath: sourcePath,
      displayName: displayName,
    );
    final updated = _withAttachments(item, [
      ...item.attachments,
      AttachmentRef(
        relativePath: stored.relativePath,
        displayName: stored.displayName,
      ),
    ]);
    await _repository.save(updated);
    await _notifyChanged();
    return updated;
  }

  /// Removes one attachment reference from an item and sweeps files that
  /// lost their last reference. Returns the updated item.
  Future<PurchaseItem?> detachAttachment({
    required String itemId,
    required String relativePath,
  }) async {
    final item = await _repository.findById(itemId);
    if (item == null) return null;
    final updated = _withAttachments(
      item,
      [
        for (final ref in item.attachments)
          if (ref.relativePath != relativePath) ref,
      ],
    );
    await _repository.save(updated);
    await _attachments.sweepOrphans();
    await _notifyChanged();
    return updated;
  }

  /// Deleting an item through the repository then sweeping files is the
  /// item-delete path; exposed so the UI delete stays one call.
  Future<void> deleteItem(String itemId) async {
    await _repository.delete(itemId);
    await _attachments.sweepOrphans();
    await _notifyChanged();
  }

  // ---- Backup / restore -------------------------------------------------

  /// Creates a ZIP backup and returns (path, manifest). The UI exports the
  /// file via the share sheet or leaves it in `backups/`.
  Future<({File file, BackupManifest manifest})> createBackup() async {
    final stamp = DateTime.now().toUtc().toIso8601String().split(':').join('-');
    final file = File(
      p.join(_documentsDir, 'backups', 'warrant-book-$stamp.zip'),
    );
    final manifest = await _backup.createBackup(_db, file.path);
    return (file: file, manifest: manifest);
  }

  /// Full restore pipeline: stage+validate (throws [BackupException]
  /// BEFORE any live data changes), [confirmOverwrite] gates the
  /// destructive apply, then reminders are re-scheduled from the restored
  /// state. The UI shows [BackupException.message] verbatim on refusal.
  Future<void> restoreFrom({
    required String zipPath,
    required Future<bool> Function(BackupManifest manifest) confirmOverwrite,
  }) async {
    final staged = await _backup.validateAndStage(zipPath);
    try {
      final confirmed = await confirmOverwrite(staged.manifest);
      if (!confirmed) {
        staged.discard();
        throw const RestoreCancelledException();
      }
      await _backup.applyToLiveDatabase(staged, _db);
    } on Object {
      staged.discard();
      rethrow;
    }
    // #5 acceptance: restores re-schedule reminders from committed state.
    await reminderScheduler?.afterRestore();
    await _notifyChanged();
  }

  // ---- Erase all ---------------------------------------------------------

  /// Removes every byte the app owns: DB rows, attachment files, all
  /// stored preferences, and every scheduled notification. The UI must
  /// have collected explicit confirmation BEFORE calling.
  Future<void> eraseAll() async {
    await _db.transaction(() async {
      await _db.delete(_db.coverageLines).go();
      await _db.delete(_db.notes).go();
      await _db.delete(_db.items).go();
      await _db.delete(_db.attachments).go();
    });
    await _attachments.clearAll();
    // Preferences: every key this app writes, plus defaults restored.
    await _settings.eraseAllStored();
    // Notification schedules first-hand from the platform.
    await reminderScheduler?.cancelAllPending();
    await _notifyChanged();
  }

  PurchaseItem _withAttachments(
    PurchaseItem item,
    List<AttachmentRef> attachments,
  ) =>
      PurchaseItem(
        id: item.id,
        name: item.name,
        purchaseDate: item.purchaseDate,
        category: item.category,
        store: item.store,
        price: item.price,
        coverageLines: item.coverageLines,
        notes: item.notes,
        attachments: attachments,
        archived: item.archived,
      );
}

/// Thrown by [DataLifecycleService.restoreFrom] when the user backs out of
/// the overwrite confirmation (distinct from a validation refusal).
class RestoreCancelledException implements Exception {
  const RestoreCancelledException();
}
