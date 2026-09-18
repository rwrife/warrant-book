// CSV export golden-file test (issue #6 acceptance criteria).
//
// The exact bytes of the export are pinned here: ITEM/LINE record kinds,
// ISO dates, ISO-4217 codes, RFC 4180 quoting, and CRLF line endings.
// Any change to the CSV format must consciously update this golden file.
//
// Field layout (14 columns): record,item_id,name,purchase_date,category,
// store,price_amount,price_currency,archived,line_kind,line_basis,
// line_months,line_end_date,line_label

import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/domain/export/csv_export.dart';
import 'package:warrant_book/domain/models/coverage_line.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/domain/models/purchase_item.dart';

void main() {
  test('golden: two items with lines, quoting, and all optional fields', () {
    final items = [
      PurchaseItem(
        id: 'id-1',
        name: 'Espresso, "the good" machine',
        purchaseDate: DayDate(2026, 1, 10),
        category: 'kitchen',
        store: 'Bed Bath & Beyond',
        price: PurchaseRecordedPrice.money(449.99, 'USD'),
        coverageLines: [
          CoverageLine(
            kind: CoverageLineKind.returnWindow,
            basis: DurationFromPurchase(months: 1),
            label: '30-day return',
          ),
          CoverageLine(
            kind: CoverageLineKind.manufacturerWarranty,
            basis: DurationFromPurchase.years(2),
          ),
        ],
      ),
      PurchaseItem(
        id: 'id-2',
        name: 'Hiking boots',
        purchaseDate: DayDate(2025, 11, 2),
        // price missing, no category/store/lines, archived.
        archived: true,
      ),
    ];

    const expected = 'record,item_id,name,purchase_date,category,store,'
        'price_amount,price_currency,archived,line_kind,line_basis,'
        'line_months,line_end_date,line_label\r\n'
        'ITEM,id-1,"Espresso, ""the good"" machine",2026-01-10,kitchen,'
        'Bed Bath & Beyond,449.99,USD,false,,,,,\r\n'
        'LINE,id-1,,,,,,,,returnWindow,duration,1,,30-day return\r\n'
        'LINE,id-1,,,,,,,,manufacturerWarranty,duration,24,,\r\n'
        'ITEM,id-2,Hiking boots,2025-11-02,,,,,true,,,,,\r\n';

    expect(registryCsv(items), expected);
  });

  test('explicit end dates export as ISO dates', () {
    final item = PurchaseItem(
      id: 'x',
      name: 'x',
      purchaseDate: DayDate(2026, 1, 1),
      coverageLines: [
        CoverageLine(
          kind: CoverageLineKind.extendedWarranty,
          basis: ExplicitEndDate(endDateValue: DayDate(2030, 6, 30)),
        ),
      ],
    );
    final csv = registryCsv([item]);
    expect(
      csv,
      contains(
        'LINE,x,,,,,,,,extendedWarranty,explicit,,2030-06-30,\r\n',
      ),
    );
  });

  test('empty registry exports only the header row', () {
    final csv = registryCsv(const []);
    expect(csv, '${csvHeader.join(',')}\r\n');
  });
}
