// Issue #6 widget flows over the REAL stack: detail-page attachments
// (attach via injected picker → inline preview over real bytes → delete
// confirms → file swept), plus the Data & privacy dialog (CSV export
// writes a real file and hands it to the share seam; erase-all needs an
// explicit acknowledgement and wipes the registry).
//
// Real Drift database on NativeDatabase.memory(), real temp-dir attachment
// store, injected picker/share seams — no mocks between UI and DB.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:warrant_book/data/attachments/attachment_store.dart';
import 'package:warrant_book/data/db/app_database.dart';
import 'package:warrant_book/data/lifecycle/data_lifecycle_service.dart';
import 'package:warrant_book/data/repositories/drift_item_repository.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/domain/models/purchase_item.dart';
import 'package:warrant_book/domain/repositories/item_repository.dart';
import 'package:warrant_book/features/attachments/attachment_picker.dart';
import 'package:warrant_book/features/settings/app_settings.dart';
import 'package:warrant_book/main.dart';

import '../data/support/db_test_support.dart';

/// Valid 1x1 PNG so Image.file can decode the inline preview.
List<int> pngBytes() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class StubPicker implements AttachmentPicker {
  StubPicker(this.path, this.name);

  final String path;
  final String name;
  int imageCalls = 0;

  @override
  Future<PickedAttachment?> pickImage() async {
    imageCalls++;
    return PickedAttachment(path: path, displayName: name);
  }

  @override
  Future<PickedAttachment?> pickDocument() async => null;
}

void main() {
  late Directory root;
  late Directory attachmentsRoot;
  late Directory documentsDir;

  setUp(() {
    root = Directory.systemTemp.createTempSync('issue6-ui');
    attachmentsRoot = Directory(p.join(root.path, 'attachments'));
    documentsDir = Directory(p.join(root.path, 'documents'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  PurchaseItem seedItem({String id = 'seed-1', String name = 'Drill'}) =>
      PurchaseItem(
        id: id,
        name: name,
        purchaseDate: DayDate(2026, 1, 10),
      );

  Future<void> seed(WarrantBookDatabase db, PurchaseItem item) =>
      DriftItemRepository(db).save(item);

  DataLifecycleService lifecycle(WarrantBookDatabase db) =>
      DataLifecycleService(
        db: db,
        repository: DriftItemRepository(db),
        attachments: AttachmentStore(db, attachmentsRoot.path),
        settings: AppSettings(InMemorySettingsStore()),
        documentsDir: documentsDir.path,
      );

  Future<void> pump(
    WidgetTester tester,
    WarrantBookDatabase db,
    DataLifecycleService service, {
    AttachmentPicker? picker,
    FileShareCallback? share,
  }) async {
    await tester.pumpWidget(
      WarrantBookApp(
        repository: DriftItemRepository(db),
        settings: AppSettings(InMemorySettingsStore()),
        today: DayDate(2026, 6, 15),
        lifecycle: service,
        attachmentPicker: picker,
        fileSharer: share,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(Key('itemRow-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('attach → inline preview → delete confirm → file swept',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      final service = lifecycle(db);
      await seed(db, seedItem());

      final png = File(p.join(root.path, 'receipt.png'))
        ..writeAsBytesSync(pngBytes());
      final picker = StubPicker(png.path, 'receipt.png');
      await pump(tester, db, service, picker: picker);
      await openDetail(tester, 'seed-1');

      expect(find.text('Attachments'), findsOneWidget);
      expect(
        find.text('No receipts attached. Tap the link icon to add a '
            'photo or PDF.'),
        findsOneWidget,
      );

      // Drive the real attach flow through the injected picker.
      await tester.tap(find.byKey(const Key('addAttachmentButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attachPhotoOption')), findsOneWidget);
      await tester.tap(find.byKey(const Key('attachPhotoOption')));
      await tester.pumpAndSettle();
      expect(picker.imageCalls, 1);

      // The saved aggregate now references the content-addressed file.
      final reloaded = await DriftItemRepository(db).findById('seed-1');
      expect(reloaded!.attachments, hasLength(1));
      final storedPath = service.attachmentAbsolutePath(
        reloaded.attachments.single.relativePath,
      );
      expect(File(storedPath).existsSync(), isTrue);

      // UI updated: tile with inline preview present.
      final relative = reloaded.attachments.single.relativePath;
      expect(
        find.byKey(Key('attachmentTile-$relative')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('deleteAttachment-$relative')),
        findsOneWidget,
      );
      expect(find.byType(Image), findsWidgets,
          reason: 'inline preview renders the stored bytes');

      // Delete with confirmation removes the row and sweeps the file.
      await tester.tap(find.byKey(Key('deleteAttachment-$relative')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDeleteAttachmentButton')));
      await tester.pumpAndSettle();

      expect(
        (await DriftItemRepository(db).findById('seed-1'))!.attachments,
        isEmpty,
      );
      expect(File(storedPath).existsSync(), isFalse,
          reason: 'sweep after detach removes the orphan file');
    });
  });

  testWidgets('CSV export writes the real file and shares it',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      final service = lifecycle(db);
      await seed(db, seedItem(name: 'Espresso machine'));
      final shared = <String>[];
      await pump(tester, db, service, share: (path) async => shared.add(path));

      await tester.tap(find.byKey(const Key('dataSettingsButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('exportCsvButton')));
      await tester.pumpAndSettle();

      expect(shared, hasLength(1));
      final csv = File(shared.single).readAsStringSync();
      expect(csv, startsWith('record,item_id,name,purchase_date'));
      expect(csv, contains('ITEM,seed-1,Espresso machine,2026-01-10'));
      expect(find.text('CSV written and handed to the share sheet.'),
          findsOneWidget);
    });
  });

  testWidgets('erase-all requires acknowledgement and wipes the registry',
      (WidgetTester tester) async {
    await withTestDatabase((db) async {
      final service = lifecycle(db);
      await seed(db, seedItem());
      await pump(tester, db, service);

      await tester.tap(find.byKey(const Key('dataSettingsButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('eraseAllButton')));
      await tester.pumpAndSettle();

      expect(find.text('Erase ALL app data?'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('confirmEraseButton')))
            .onPressed,
        isNull,
        reason: 'erase stays disabled until acknowledged',
      );

      // Cancel keeps the data.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await DriftItemRepository(db).findById('seed-1'), isNotNull);

      // Acknowledge + erase wipes rows and the preferences store.
      await tester.tap(find.byKey(const Key('eraseAllButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('eraseAcknowledge')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('confirmEraseButton')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('confirmEraseButton')));
      await tester.pumpAndSettle();

      expect(find.text('All data erased.'), findsOneWidget);
      expect(await DriftItemRepository(db).findById('seed-1'), isNull);
      final remaining = await DriftItemRepository(db)
          .list(ItemQuery(today: DayDate(2026, 6, 15), includeArchived: true));
      expect(remaining, isEmpty);
    });
  });
}
