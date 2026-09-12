// Shared fixtures for data-layer tests (issue #3).
//
// NOTE: `DayDate` and the duration-basis constructors validate their inputs
// in their constructor bodies, so aggregates here cannot be `const` — that
// is intentional (issue #2 made invalid dates impossible to construct).

import 'package:warrant_book/domain/models/coverage_line.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/domain/models/purchase_item.dart';

DayDate day(int y, int m, int d) => DayDate(y, m, d);

/// A fully-populated aggregate: two duration lines + one explicit line,
/// two notes, one attachment.
PurchaseItem fullItem({
  String id = 'item-full',
  String name = 'Dewalt 12in drill',
  DayDate? purchaseDate,
  String? category = 'tools',
  String? store = 'Home Depot',
  PurchaseRecordedPrice price = const PurchaseRecordedPrice.missing(),
  bool archived = false,
}) {
  return PurchaseItem(
    id: id,
    name: name,
    purchaseDate: purchaseDate ?? day(2026, 1, 15),
    category: category,
    store: store,
    price: price,
    coverageLines: [
      CoverageLine(
        kind: CoverageLineKind.returnWindow,
        basis: DurationFromPurchase(months: 1),
        label: '30-day return',
      ),
      CoverageLine(
        kind: CoverageLineKind.manufacturerWarranty,
        basis: DurationFromPurchase.years(3),
      ),
      CoverageLine(
        kind: CoverageLineKind.extendedWarranty,
        basis: ExplicitEndDate(endDateValue: DayDate(2030, 6, 30)),
        label: 'Costco extended',
      ),
    ],
    notes: [
      Note(text: 'Registered online', recordedOn: DayDate(2026, 1, 16)),
      Note(text: 'Bit set included', recordedOn: DayDate(2026, 1, 15)),
    ],
    attachments: const [
      AttachmentRef(
        relativePath: 'receipts/drill.jpg',
        displayName: 'drill.jpg',
      ),
    ],
    archived: archived,
  );
}
