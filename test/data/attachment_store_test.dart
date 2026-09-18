// Attachment lifecycle tests (issue #6 acceptance criteria).
//
// Exercises the REAL filesystem (temp dirs), the real Drift database, and
// the real DriftItemRepository end to end: attach → the content-addressed
// file exists and the saved aggregate references it; detach → the orphan
// sweep removes the file once nothing references it; item delete → sweep
// again; content shared between two items survives until BOTH references
// are gone; the sweep never touches referenced files.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:warrant_book/data/attachments/attachment_store.dart';
import 'package:warrant_book/data/repositories/drift_item_repository.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/domain/models/purchase_item.dart';

import '../data/support/db_test_support.dart';

void main() {
  late Directory root;
  late Directory attachmentsRoot;

  setUp(() {
    root = Directory.systemTemp.createTempSync('attach-test');
    attachmentsRoot = Directory(p.join(root.path, 'attachments'));
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String sourceFile(String name, List<int> bytes) {
    final file = File(p.join(root.path, name));
    file.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return file.path;
  }

  PurchaseItem itemWith(String id, List<AttachmentRef> attachments) =>
      PurchaseItem(
        id: id,
        name: 'Item $id',
        purchaseDate: DayDate(2026, 1, 1),
        attachments: attachments,
      );

  test('attach stores content-addressed file and returns its hash', () async {
    await withTestDatabase((db) async {
      final store = AttachmentStore(db, attachmentsRoot.path);
      final bytes = utf8.encode('receipt total 42.00');
      final source = sourceFile('receipt.txt', bytes);

      final stored = store.attachFileSync(sourcePath: source);

      final expectedHash = sha256.convert(bytes).toString();
      expect(stored.sha256Hex, expectedHash);
      expect(stored.relativePath, 'receipts/$expectedHash.txt');
      expect(stored.sizeBytes, bytes.length);
      expect(stored.displayName, 'receipt.txt');
      expect(File(store.absolutePath(stored.relativePath)).existsSync(),
          isTrue);
      // Source is copied, never moved.
      expect(File(source).existsSync(), isTrue);
    });
  });

  test('identical bytes deduplicate to one stored file', () async {
    await withTestDatabase((db) async {
      final store = AttachmentStore(db, attachmentsRoot.path);
      final bytes = utf8.encode('same receipt');
      final first =
          store.attachFileSync(sourcePath: sourceFile('a.txt', bytes));
      final second =
          store.attachFileSync(sourcePath: sourceFile('sub/b.txt', bytes));

      expect(second.relativePath, first.relativePath);
      expect(store.storedRelativePaths(), [first.relativePath]);
    });
  });

  test('attach rejects oversized input and missing sources', () async {
    await withTestDatabase((db) async {
      final store = AttachmentStore(db, attachmentsRoot.path);
      final source = sourceFile('big.bin', List.filled(10, 7));

      expect(
        () => store.attachFileSync(sourcePath: source, maxBytes: 4),
        throwsA(isA<AttachmentStoreException>()),
      );
      expect(
        () => store.attachFileSync(
            sourcePath: p.join(root.path, 'nope.txt')),
        throwsA(isA<AttachmentStoreException>()),
      );
    });
  });

  test('attach → detach → sweep leaves no orphan file', () async {
    await withTestDatabase((db) async {
      final store = AttachmentStore(db, attachmentsRoot.path);
      final repo = DriftItemRepository(db);
      final stored = store.attachFileSync(
        sourcePath: sourceFile('r.txt', utf8.encode('receipt')),
      );

      // Attach: save the aggregate with the reference.
      await repo.save(itemWith('item-1', [
        AttachmentRef(
          relativePath: stored.relativePath,
          displayName: stored.displayName,
        ),
      ]));
      final rows = await db.select(db.attachments).get();
      expect(rows.single.relativePath, stored.relativePath);

      // A sweep with the reference alive keeps the file.
      var sweep = await store.sweepOrphans();
      expect(sweep.deletedPaths, isEmpty);
      expect(File(store.absolutePath(stored.relativePath)).existsSync(),
          isTrue);

      // Detach: save without the reference, then sweep.
      await repo.save(itemWith('item-1', const []));
      sweep = await store.sweepOrphans();
      expect(sweep.deletedPaths, [stored.relativePath]);
      expect(File(store.absolutePath(stored.relativePath)).existsSync(),
          isFalse);

      // Sweep is idempotent.
      final second = await store.sweepOrphans();
      expect(second.deletedPaths, isEmpty);
      expect(second.errors, isEmpty);
    });
  });

  test('item delete + sweep removes files; shared content survives until '
      'every reference is gone', () async {
    await withTestDatabase((db) async {
      final store = AttachmentStore(db, attachmentsRoot.path);
      final repo = DriftItemRepository(db);
      final solo = store.attachFileSync(
        sourcePath: sourceFile('solo.txt', utf8.encode('solo')),
      );
      final shared = store.attachFileSync(
        sourcePath: sourceFile('shared.txt', utf8.encode('shared')),
      );
      AttachmentRef ref(StoredAttachment s) =>
          AttachmentRef(relativePath: s.relativePath);

      await repo.save(itemWith('item-a', [ref(solo), ref(shared)]));
      await repo.save(itemWith('item-b', [ref(shared)]));

      // Delete item-a: `solo` is now unreferenced, `shared` still lives
      // through item-b.
      await repo.delete('item-a');
      var sweep = await store.sweepOrphans();
      expect(sweep.deletedPaths, [solo.relativePath]);
      expect(File(store.absolutePath(shared.relativePath)).existsSync(),
          isTrue);

      await repo.delete('item-b');
      sweep = await store.sweepOrphans();
      expect(sweep.deletedPaths, [shared.relativePath]);
      expect(store.storedRelativePaths(), isEmpty);
    });
  });

  test('clearAll wipes files and rows (erase-all building block)', () async {
    await withTestDatabase((db) async {
      final store = AttachmentStore(db, attachmentsRoot.path);
      final repo = DriftItemRepository(db);
      final stored = store.attachFileSync(
        sourcePath: sourceFile('r.txt', utf8.encode('x')),
      );
      await repo.save(itemWith('item-1', [
        AttachmentRef(relativePath: stored.relativePath),
      ]));

      await store.clearAll();

      expect(store.storedRelativePaths(), isEmpty);
      expect(await db.select(db.attachments).get(), isEmpty);
    });
  });

  test('sha256Of matches the digest recorded at attach time', () async {
    await withTestDatabase((db) async {
      final store = AttachmentStore(db, attachmentsRoot.path);
      final stored = store.attachFileSync(
        sourcePath: sourceFile('r.txt', utf8.encode('verify me')),
      );
      expect(store.sha256Of(stored.relativePath), stored.sha256Hex);
      expect(
        () => store.sha256Of('receipts/missing.txt'),
        throwsA(isA<AttachmentStoreException>()),
      );
    });
  });
}
