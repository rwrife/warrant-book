import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/main.dart';

void main() {
  testWidgets('app boots and renders the placeholder home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const WarrantBookApp());

    expect(find.text('Warrant Book'), findsOneWidget);
    expect(
      find.text('Workspace skeleton — registry UI coming in M2.'),
      findsOneWidget,
    );
  });
}
