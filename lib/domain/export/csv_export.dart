// Warrant Book — domain layer (issue #6).
//
// Deterministic CSV serialization of the registry: one row per item, plus
// one row per coverage line. Pure Dart over domain types (no Flutter, no
// I/O) so the golden-file test can pin the exact bytes. Dates use the
// canonical ISO `yyyy-MM-dd` form and prices carry their ISO-4217 code —
// never a locale-formatted string (issue #6 acceptance criteria).
//
// Quoting follows RFC 4180: fields are quoted only when they contain a
// comma, double quote, CR or LF; embedded quotes double up. Rows end with
// CRLF so the file opens predictably in spreadsheet apps.

import '../models/coverage_line.dart';
import '../models/purchase_item.dart';

/// One CSV row kind — first column of every record.
enum CsvRecordKind {
  /// Aggregate purchase row.
  item('ITEM'),

  /// Coverage-window row attached to an item.
  coverageLine('LINE');

  const CsvRecordKind(this.label);

  /// Stable text written to the `record` column — parsed by the golden
  /// test, never an ordinal.
  final String label;
}

/// Header row emitted by [registryCsv].
const List<String> csvHeader = <String>[
  'record',
  'item_id',
  'name',
  'purchase_date',
  'category',
  'store',
  'price_amount',
  'price_currency',
  'archived',
  'line_kind',
  'line_basis',
  'line_months',
  'line_end_date',
  'line_label',
];

/// RFC 4180 field quoting: quote only when needed, double embedded quotes.
String csvField(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _csvRow(List<String> fields) =>
    '${fields.map(csvField).join(',')}\r\n';

/// Renders [items] as CSV text: header, then per item an ITEM row followed
/// by one LINE row per coverage line (in domain order). Item order is left
/// to the caller (the repository's newest-first list order).
String registryCsv(Iterable<PurchaseItem> items) {
  final buffer = StringBuffer()..write(_csvRow(csvHeader));
  for (final item in items) {
    buffer.write(
      _csvRow([
        CsvRecordKind.item.label,
        item.id,
        item.name,
        item.purchaseDate.toString(),
        item.category ?? '',
        item.store ?? '',
        item.price.isMissing ? '' : item.price.amount!.toString(),
        item.price.currencyCode ?? '',
        item.archived ? 'true' : 'false',
        '',
        '',
        '',
        '',
        '',
      ]),
    );
    for (final line in item.coverageLines) {
      final (basisKind, months, endDate) = switch (line.basis) {
        final DurationFromPurchase d => ('duration', '${d.months}', ''),
        final ExplicitEndDate e => ('explicit', '', e.endDateValue.toString()),
      };
      buffer.write(
        _csvRow([
          CsvRecordKind.coverageLine.label,
          item.id,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          line.kind.name,
          basisKind,
          months,
          endDate,
          line.label ?? '',
        ]),
      );
    }
  }
  return buffer.toString();
}
