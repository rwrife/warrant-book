// Warrant Book — data layer (issue #6).
//
// Versioned ZIP backup/restore for the whole user-owned dataset:
//
//   manifest.json          format + schema version + per-file hashes
//   db.sqlite              the app database (VACUUM INTO snapshot)
//   attachments/...        every receipt file, store-relative paths
//
// Restore never trusts the archive: every member is re-hashed against the
// manifest before anything on disk is touched, and a backup whose
// `backup_format` or `schema_version` is newer than this app understands
// is REFUSED with a clear error (a future-schema database must never be
// opened and half-migrated by an older build — same rule as the DB
// migration scaffold in app_database.dart).
//
// Creating a backup uses `VACUUM INTO`, which SQLite documents as a
// transactionally consistent snapshot that works while the database is in
// use — no close-and-reopen dance, no torn copies.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import '../attachments/attachment_store.dart';
import '../db/app_database.dart';

/// Stable identifiers of backup archive members.
class BackupPaths {
  static const String manifest = 'manifest.json';
  static const String database = 'db.sqlite';
  static const String attachmentsPrefix = 'attachments/';
}

/// Every failure in [BackupService] — always with a user-explainable
/// message; restore fails closed.
class BackupException implements Exception {
  const BackupException(this.reason, this.message);

  final BackupRefusalReason reason;
  final String message;

  @override
  String toString() => 'BackupException(${reason.name}): $message';
}

enum BackupRefusalReason {
  /// The archive has no parseable manifest.
  notABackup,

  /// A member file is missing, unreadable, or hashes differently than the
  /// manifest promised.
  checksumMismatch,

  /// `backup_format` is newer than this app can read.
  futureFormat,

  /// The backup's database schema version is newer than this app's.
  futureSchema,

  /// The backup database cannot be opened as a warrant-book database.
  unusableDatabase,
}

/// Parsed `manifest.json`.
class BackupManifest {
  const BackupManifest({
    required this.backupFormat,
    required this.schemaVersion,
    required this.createdUtcIso,
    required this.files,
  });

  /// Bump when the backup layout changes incompatibly. Readers refuse
  /// anything above [currentBackupFormat].
  static const int currentBackupFormat = 1;

  static const int currentSchemaVersion =
      WarrantBookDatabase.currentSchemaVersion;

  final int backupFormat;
  final int schemaVersion;
  final String createdUtcIso;

  /// Archive member path -> lowercase-hex SHA-256 (files are hashed at
  /// backup time; restore re-verifies).
  final Map<String, String> files;

  factory BackupManifest.parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on Object {
      throw const BackupException(
        BackupRefusalReason.notABackup,
        'manifest.json is not valid JSON — this is not a Warrant Book backup',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const BackupException(
        BackupRefusalReason.notABackup,
        'manifest.json is not an object — this is not a Warrant Book backup',
      );
    }
    final format = decoded['backup_format'];
    final schema = decoded['schema_version'];
    final created = decoded['created_utc'];
    final filesJson = decoded['files'];
    if (format is! int || schema is! int || created is! String ||
        filesJson is! Map<String, Object?>) {
      throw const BackupException(
        BackupRefusalReason.notABackup,
        'manifest.json is missing required fields (backup_format, '
        'schema_version, created_utc, files)',
      );
    }
    final files = <String, String>{};
    for (final entry in filesJson.entries) {
      final hash = entry.value;
      if (hash is! String) {
        throw const BackupException(
          BackupRefusalReason.notABackup,
          'manifest files map must be path -> sha256 hex string',
        );
      }
      files[entry.key] = hash.toLowerCase();
    }
    return BackupManifest(
      backupFormat: format,
      schemaVersion: schema,
      createdUtcIso: created,
      files: files,
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert({
    'backup_format': backupFormat,
    'schema_version': schemaVersion,
    'created_utc': createdUtcIso,
    'files': files,
  });
}

/// Files extracted and verified in a temp staging directory, ready to be
/// applied. [discard] must run whether or not the apply happens.
class StagedBackup {
  StagedBackup._({
    required this.directory,
    required this.manifest,
    required this.databasePath,
    required this.attachmentPaths,
  });

  final Directory directory;
  final BackupManifest manifest;
  final String databasePath;

  /// Store-relative attachment paths present in the archive.
  final List<String> attachmentPaths;

  void discard() {
    try {
      directory.deleteSync(recursive: true);
    } on Object {
      // Best-effort cleanup of a temp dir; the OS reclaims /tmp anyway.
    }
  }
}

/// Creates and applies versioned ZIP backups.
class BackupService {
  BackupService(this._attachments, this._appSchemaVersion);

  final AttachmentStore _attachments;
  final int _appSchemaVersion;

  /// Writes a backup of [db] + every attachment file to [zipPath].
  ///
  /// [db] may stay open: the snapshot is taken with `VACUUM INTO`, which is
  /// consistent under concurrent use. The returned manifest is embedded in
  /// the archive as `manifest.json`.
  Future<BackupManifest> createBackup(
    WarrantBookDatabase db,
    String zipPath,
  ) async {
    final tempDir = await Directory.systemTemp.createTemp('warrantbook-bkp');
    try {
      final snapshotPath = p.join(tempDir.path, BackupPaths.database);
      await db.customStatement('VACUUM INTO ?', [snapshotPath]);

      final files = <String, String>{
        BackupPaths.database: _sha256OfFile(snapshotPath),
      };
      for (final relativePath in _attachments.storedRelativePaths()) {
        final digest = _attachments.sha256Of(relativePath);
        files['${BackupPaths.attachmentsPrefix}$relativePath'] = digest;
      }
      final manifest = BackupManifest(
        backupFormat: BackupManifest.currentBackupFormat,
        schemaVersion: _appSchemaVersion,
        createdUtcIso: DateTime.now().toUtc().toIso8601String(),
        files: files,
      );

      final archive = Archive();
      void addBytes(String name, List<int> bytes) =>
          archive.addFile(ArchiveFile(name, bytes.length, bytes));

      addBytes(BackupPaths.manifest, utf8.encode(manifest.toJsonString()));
      addBytes(BackupPaths.database, File(snapshotPath).readAsBytesSync());
      for (final relativePath in _attachments.storedRelativePaths()) {
        addBytes(
          '${BackupPaths.attachmentsPrefix}$relativePath',
          File(_attachments.absolutePath(relativePath)).readAsBytesSync(),
        );
      }

      final encoded = ZipEncoder().encode(archive);
      File(zipPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(encoded);
      return manifest;
    } finally {
      try {
        tempDir.deleteSync(recursive: true);
      } on Object {
        // best-effort
      }
    }
  }

  /// Extracts [zipPath] to a temp directory, verifying against the
  /// manifest BEFORE touching live data. Throws [BackupException] (leaving
  /// the live dataset untouched) for: non-backup archives, tampered or
  /// truncated files, unknown future backup formats, and databases from a
  /// future schema version.
  ///
  /// The caller MUST either [StagedBackup.discard] the result or pass it to
  /// [applyToLiveDatabase].
  Future<StagedBackup> validateAndStage(String zipPath) async {
    final List<int> bytes;
    try {
      bytes = await File(zipPath).readAsBytes();
    } on Object {
      throw BackupException(
        BackupRefusalReason.notABackup,
        'Cannot read backup file $zipPath',
      );
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const BackupException(
        BackupRefusalReason.notABackup,
        'The selected file is not a readable ZIP archive',
      );
    }

    final manifestEntry = archive.findFile(BackupPaths.manifest);
    if (manifestEntry == null) {
      throw const BackupException(
        BackupRefusalReason.notABackup,
        'Archive has no manifest.json — this is not a Warrant Book backup',
      );
    }
    final BackupManifest manifest;
    try {
      manifest = BackupManifest.parse(
        utf8.decode(manifestEntry.readBytes()!),
      );
    } on BackupException {
      rethrow;
    } on Object catch (error) {
      throw BackupException(
        BackupRefusalReason.notABackup,
        'manifest.json unreadable: $error',
      );
    }

    // Refuse future versions BEFORE extraction — a newer format or schema
    // may contain data shapes this build would corrupt, so nothing is
    // staged or applied.
    if (manifest.backupFormat > BackupManifest.currentBackupFormat) {
      throw BackupException(
        BackupRefusalReason.futureFormat,
        'This backup was written by a newer Warrant Book '
        '(backup format ${manifest.backupFormat} > supported '
        '${BackupManifest.currentBackupFormat}). Update the app first.',
      );
    }
    if (manifest.schemaVersion > _appSchemaVersion) {
      throw BackupException(
        BackupRefusalReason.futureSchema,
        'This backup uses database schema v${manifest.schemaVersion}, '
        'which this Warrant Book (schema v$_appSchemaVersion) cannot read '
        'safely. Update the app first.',
      );
    }

    final staged = await Directory.systemTemp.createTemp('warrantbook-str');
    try {
      final attachmentPaths = <String>[];
      for (final entry in archive) {
        // The manifest hashes the payload files, not itself, so it is
        // exempt from the per-file integrity loop (it was already parsed
        // above — a corrupt one would have thrown notABackup).
        if (entry.name == BackupPaths.manifest) continue;
        if (entry.isFile) {
          final data = entry.readBytes();
          if (data == null) {
            throw BackupException(
              BackupRefusalReason.checksumMismatch,
              'Member ${entry.name} could not be decompressed',
            );
          }
          final expectedHash = manifest.files[entry.name];
          final actualHash = sha256.convert(data).toString();
          if (expectedHash == null || actualHash != expectedHash) {
            throw BackupException(
              BackupRefusalReason.checksumMismatch,
              expectedHash == null
                  ? 'Archive contains unexpected file ${entry.name} '
                      '(not listed in the manifest)'
                  : 'File ${entry.name} failed integrity check '
                      '(manifest $expectedHash, actual $actualHash)',
            );
          }
          final target = File(p.join(staged.path, entry.name));
          await target.create(recursive: true);
          await target.writeAsBytes(data);
          if (entry.name.startsWith(BackupPaths.attachmentsPrefix)) {
            attachmentPaths.add(
              entry.name.substring(BackupPaths.attachmentsPrefix.length),
            );
          }
        }
      }
      for (final required in manifest.files.keys) {
        if (required == BackupPaths.manifest) continue;
        if (!File(p.join(staged.path, required)).existsSync()) {
          throw BackupException(
            BackupRefusalReason.checksumMismatch,
            'Manifest lists $required but the archive does not contain it',
          );
        }
      }

      // Prove the staged database opens as a v<=current schema warrant-book
      // database before it can replace anything.
      final probeDb = WarrantBookDatabase(
        NativeDatabase(
          File(p.join(staged.path, BackupPaths.database)),
        ),
      );
      try {
        await probeDb.customSelect('SELECT 1').getSingle();
      } on Object catch (error) {
        throw BackupException(
          BackupRefusalReason.unusableDatabase,
          'The backup database cannot be opened: $error',
        );
      } finally {
        await probeDb.close();
      }

      return StagedBackup._(
        directory: staged,
        manifest: manifest,
        databasePath: p.join(staged.path, BackupPaths.database),
        attachmentPaths: attachmentPaths..sort(),
      );
    } on Object {
      staged.deleteSync(recursive: true);
      rethrow;
    }
  }

  /// Applies the staged backup to the LIVE [db] without closing it:
  /// staged attachment files replace the store, then the staged database is
  /// ATTACHed to the live connection and every table is replaced inside one
  /// transaction (delete-all → insert-all; item rows cascade-clear child
  /// rows first). Same-schema-only: [validateAndStage] already refused
  /// anything else, and the DB migration scaffold guarantees the live
  /// database is at the app's schema version.
  ///
  /// The destructive-overwrite confirmation is a UI decision and must have
  /// happened before this call. Callers should run
  /// `ReminderScheduler.afterRestore()` afterwards so restored items get
  /// their reminders re-scheduled (issue #5 hook).
  Future<void> applyToLiveDatabase(
    StagedBackup staged,
    WarrantBookDatabase db,
  ) async {
    // 1. Attachment files first: the rows about to be inserted reference
    // exactly these paths.
    _attachments.replaceStoreFrom(
      p.join(staged.directory.path, 'attachments'),
    );

    try {
      // ATTACH cannot run inside a transaction; the replacement below can.
      await db.customStatement('ATTACH DATABASE ? AS staged', [
        staged.databasePath,
      ]);
      try {
        await db.transaction(() async {
          // Parents first — ON DELETE CASCADE (PRAGMA foreign_keys is set
          // per connection in beforeOpen) empties the children too; the
          // explicit child deletes are belt-and-braces against a schema
          // where a cascade were ever relaxed.
          await db.customStatement('DELETE FROM main.items');
          await db.customStatement('DELETE FROM main.coverage_lines');
          await db.customStatement('DELETE FROM main.notes');
          await db.customStatement('DELETE FROM main.attachments');
          // Same-schema guarantee makes `SELECT *` column-exact.
          await db.customStatement('INSERT INTO main.items '
              'SELECT * FROM staged.items');
          await db.customStatement('INSERT INTO main.coverage_lines '
              'SELECT * FROM staged.coverage_lines');
          await db.customStatement('INSERT INTO main.notes '
              'SELECT * FROM staged.notes');
          await db.customStatement('INSERT INTO main.attachments '
              'SELECT * FROM staged.attachments');
        });
      } on Object {
        // Roll the file replacement back is impossible (live rows were
        // replaced or threw before inserting); surface loudly — the staged
        // backup on disk is untouched and restore can be retried.
        rethrow;
      } finally {
        await db.customStatement('DETACH DATABASE staged');
      }
    } finally {
      staged.discard();
    }
  }

  static String _sha256OfFile(String path) =>
      sha256.convert(File(path).readAsBytesSync()).toString();
}
