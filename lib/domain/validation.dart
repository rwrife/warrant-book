// Warrant Book — pure-Dart domain layer (issue #2).
//
// Field-level validation rules for forms and repository write paths.
// `validateItem` returns a complete list of human-readable problems; the
// UI (issue #4) renders them and the repository (issue #3) can refuse
// writes that fail. Constructors already enforce hard invariants — this
// layer catches cross-field rules (e.g. an explicit end date before the
// purchase date) that no single constructor can see.

import 'models/coverage_line.dart';
import 'models/day_date.dart';
import 'models/purchase_item.dart';

/// Validates a whole [item], returning problem messages (empty == valid).
List<String> validateItem(PurchaseItem item) {
  final problems = <String>[];
  problems.addAll(validateName(item.name));
  problems.addAll(validatePurchaseDate(item.purchaseDate));
  if (item.price.isMissing != (item.price.currencyCode == null)) {
    problems.add('Price missing/unknown must not carry a currency code.');
  }
  for (var i = 0; i < item.coverageLines.length; i++) {
    problems.addAll(
      validateCoverageLine(item.coverageLines[i], item.purchaseDate,
          at: i),
    );
  }
  for (var i = 0; i < item.notes.length; i++) {
    if (item.notes[i].text.trim().isEmpty) {
      problems.add('Note #${i + 1} is empty.');
    }
  }
  return problems;
}

/// Name is required and must not be blank whitespace.
List<String> validateName(String name) {
  if (name.trim().isEmpty) {
    return const ['Item name is required.'];
  }
  return const [];
}

/// Purchase date anchor sanity: reject dates so far in the future they are
/// certainly typos (10 years), and reject obviously broken years.
List<String> validatePurchaseDate(
  DayDate purchaseDate, {
  DayDate? today,
}) {
  final problems = <String>[];
  if (purchaseDate.year < 1800) {
    problems.add('Purchase year looks invalid (before 1800).');
  }
  if (today != null &&
      purchaseDate.isAfter(today.addDays(3652))) {
    problems.add('Purchase date is more than 10 years in the future.');
  }
  return problems;
}

/// Cross-field rules for one coverage line against its item's
/// [purchaseDate]. [at] is the 0-based index used in messages.
List<String> validateCoverageLine(
  CoverageLine line,
  DayDate purchaseDate, {
  int at = 0,
}) {
  final problems = <String>[];
  final label = 'Coverage line #${at + 1}';
  final basis = line.basis;
  if (basis is ExplicitEndDate) {
    if (basis.endDateValue.isBefore(purchaseDate)) {
      problems.add(
        '$label ends (${basis.endDateValue}) before the purchase date '
        '($purchaseDate).',
      );
    }
    if (basis.endDateValue.isAfter(purchaseDate.addYears(50))) {
      problems.add('$label ends more than 50 years after purchase.');
    }
  }
  if (basis is DurationFromPurchase && basis.months > 600) {
    problems.add('$label duration exceeds 50 years.');
  }
  return problems;
}
