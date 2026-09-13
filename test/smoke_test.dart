// App boot smoke test (issue #1 skeleton, rewired for issue #4).
//
// Verifies the app boots into the registry home screen against an
// in-memory database with a frozen "today".

import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/data/repositories/drift_item_repository.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/features/settings/app_settings.dart';
import 'package:warrant_book/main.dart';

import 'data/support/db_test_support.dart';

void main() {
  testWidgets('app boots into the empty registry', (WidgetTester tester) async {
    await withTestDatabase((db) async {
      await tester.pumpWidget(
        WarrantBookApp(
          repository: DriftItemRepository(db),
          settings: AppSettings(InMemorySettingsStore()),
          today: DayDate(2026, 6, 15),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Warrant Book'), findsOneWidget);
      expect(find.text('Coverage now'), findsWidgets);
      expect(
        find.text(
          'Nothing under coverage yet. Tap Add purchase to register '
          'your first item.',
        ),
        findsOneWidget,
      );
    });
  });
}
