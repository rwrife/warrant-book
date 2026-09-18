// Warrant Book — data layer (issue #6).
//
// App-private attachment store: receipt bytes live under `<root>/receipts/`
// named by the SHA-256 of their content, so the same receipt attached to
// two items is stored exactly once, and a stored file can never be
// silently swapped (backup restore re-verifies the hash — issue #6).
//
// Reference bookkeeping deliberately stays in the `attachments` table as
// part of the item aggregate (DriftItemRepository rewrites those rows on
// save). This class only owns files. The GC is [sweepOrphans]: it deletes
// files no attachment row references anymore, running after item/
// attachment deletes. Deferring the sweep avoids racing a save of the same
// content to a second item, and is covered by tests.
//
// Filesystem calls here use the synchronous dart:io variants on purpose:
// `exists()`/`length()` are the slow async wrappers the repo's lints
// forbid, while these stat-sized operations are negligible next to the
// SHA-256 hashing.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../db/app_database.dart';

/// Thrown when an attachment operation cannot be completed safely.
class AttachmentStoreException implements Exception {
  const AttachmentStoreException(this.message);

  final String message;

  @override
  String toString() => 'AttachmentStoreException: $message';
}

/// Result of [AttachmentStore.attachFileSync].
class StoredAttachment {
  const StoredAttachment({
    required this.relativePath,
    required this.sha256Hex,
    required this.sizeBytes,
    required this.displayName,
  });

  /// Path relative to the store root, e.g. `receipts/<sha>.jpg`.
  final String relativePath;

  /// Lowercase hex SHA-256 of the stored bytes.
  final String sha256Hex;

  /// Byte length of the stored file.
  final int sizeBytes;

  /// User-facing original name.
  final String displayName;
}

/// Result of [AttachmentStore.sweepOrphans].
class OrphanSweepResult {
  const OrphanSweepResult({
    required this.deletedPaths,
    this.errors = const [],
  });

  /// Relative paths of files removed because no item referenced them.
  final List<String> deletedPaths;

  /// Non-fatal errors encountered while deleting (paths skipped).
  final List<String> errors;

  bool get isClean => deletedPaths.isEmpty && errors.isEmpty;
}

/// Content-addressed attachment files in app-private storage.
class AttachmentStore {
  /// The database is only consulted for reference bookkeeping (orphan
  /// sweep, erase-all); bytes are owned entirely here.
  AttachmentStore(this._db, String rootPath) : _root = Directory(rootPath);

  final WarrantBookDatabase _db;
  final Directory _root;

  static const String receiptsDir = 'receipts';

  /// Absolute path of [relativePath] under the store root.
  String absolutePath(String relativePath) => p.join(_root.path, relativePath);

  /// Copies the bytes at [sourcePath] into the store under a filename
  /// derived from their SHA-256 (deduplicated; attaching identical bytes
  /// adds no second copy). Callers then add the returned reference to the
  /// item aggregate and save it. [maxBytes] guards accidental huge imports.
  ///
  /// IO here is synchronous on purpose: widget tests run UI flows in a
  /// fake-async zone that never completes real IO futures, and receipt
  /// files are bounded by [maxBytes].
  StoredAttachment attachFileSync({
    required String sourcePath,
    String? displayName,
    int maxBytes = 32 * 1024 * 1024,
  }) {
    final source = File(sourcePath);
    final stat = source.statSync();
    if (stat.type != FileSystemEntityType.file) {
      throw const AttachmentStoreException('Source file does not exist');
    }
    if (stat.size > maxBytes) {
      throw AttachmentStoreException(
        'Attachment is ${stat.size} bytes, over the $maxBytes byte limit',
      );
    }
    final bytes = source.readAsBytesSync();
    final hex = sha256.convert(bytes).toString();
    final extension = p.extension(sourcePath).toLowerCase();
    final safeExtension =
        RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension) ? extension : '';
    final relativePath = '$receiptsDir/$hex$safeExtension';

    final target = File(absolutePath(relativePath));
    if (!target.existsSync()) {
      target.createSync(recursive: true);
      target.writeAsBytesSync(bytes);
    }
    return StoredAttachment(
      relativePath: relativePath,
      sha256Hex: hex,
      sizeBytes: bytes.length,
      displayName: displayName ?? p.basename(sourcePath),
    );
  }

  /// Deletes every file under the store root and clears all attachment
  /// rows (part of erase-all). The row clear awaits drift (synchronous
  /// FFI under the test executor); the file IO is sync for the same reason
  /// as [attachFileSync].
  Future<void> clearAll() async {
    await _db.delete(_db.attachments).go();
    if (_root.existsSync()) {
      _root.deleteSync(recursive: true);
    }
  }

  /// Wholesale replacement of the store's file tree with everything under
  /// [stagedRoot] (backup restore: the restored database already carries
  /// the matching attachment rows). A restore replaces — per-file merge is
  /// deliberately not attempted, matching the database swap semantics.
  void replaceStoreFrom(String stagedRoot) {
    if (_root.existsSync()) {
      _root.deleteSync(recursive: true);
    }
    final source = Directory(stagedRoot);
    if (!source.existsSync()) return; // backup had no attachments
    _root.createSync(recursive: true);
    for (final entity in source.listSync(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: stagedRoot);
      final target = File(p.join(_root.path, relative))
        ..createSync(recursive: true);
      entity.copySync(target.path);
    }
  }

  /// Relative paths of ALL files currently on disk under the store root.
  List<String> storedRelativePaths() {
    if (!_root.existsSync()) return const [];
    final paths = <String>[];
    for (final entity in _root.listSync(recursive: true)) {
      if (entity is File) {
        paths.add(p.relative(entity.path, from: _root.path));
      }
    }
    return paths..sort();
  }

  /// Deletes every file under the store root that no attachment row
  /// references. Files referenced by ANY item (including archived ones)
  /// are kept. An error deleting one file does not stop the sweep.
  Future<OrphanSweepResult> sweepOrphans() async {
    final referenced = (await _db.select(_db.attachments).get())
        .map((row) => row.relativePath)
        .toSet();
    final deleted = <String>[];
    final errors = <String>[];
    for (final path in storedRelativePaths()) {
      if (referenced.contains(path)) continue;
      try {
        File(absolutePath(path)).deleteSync();
        deleted.add(path);
      } on Object catch (error) {
        errors.add('$path: $error');
      }
    }
    // Remove directories emptied by the sweep; non-empty ones are kept.
    if (_root.existsSync()) {
      for (final entity in _root.listSync(recursive: true)) {
        if (entity is! Directory) continue;
        try {
          entity.deleteSync(); // only succeeds when empty
        } on Object {
          // Non-empty — expected while live files remain.
        }
      }
    }
    return OrphanSweepResult(deletedPaths: deleted, errors: errors);
  }

  /// SHA-256 hex of a stored file (for backup manifests).
  String sha256Of(String relativePath) {
    final file = File(absolutePath(relativePath));
    if (!file.existsSync()) {
      throw AttachmentStoreException('Missing attachment file $relativePath');
    }
    return sha256.convert(file.readAsBytesSync()).toString();
  }
}
