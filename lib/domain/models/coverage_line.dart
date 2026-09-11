// Warrant Book — pure-Dart domain layer (issue #2).
//
// A coverage line is one tracked window on a purchase (return period,
// manufacturer warranty, extended warranty) with a rule for deriving its
// end: a duration measured from the purchase date, or an explicit end date.
//
// Hard invariants (positive durations, valid calendar dates) are enforced by
// the constructors themselves; cross-field rules live in
// `lib/domain/validation.dart`.

import 'day_date.dart';

/// The product role a coverage line plays. Drives list grouping and, later,
/// per-line reminder defaults (issue #5).
enum CoverageLineKind {
  /// Period in which the item can be returned to the store.
  returnWindow,

  /// Warranty supplied by the manufacturer as part of the purchase.
  manufacturerWarranty,

  /// Warranty bought separately (typically by the retailer).
  extendedWarranty,
}

/// How a coverage line's end date is derived. Exhaustive by construction:
/// every line is either a duration-from-purchase or an explicit end date —
/// there is no "unknown basis" state, so missing input fails at
/// construction/validation time and can never silently count as covered.
sealed class CoverageBasis {
  const CoverageBasis();

  /// The end date this basis yields for an item purchased on [purchaseDate].
  ///
  /// Duration bases clamp the day-of-month to the target month's length
  /// (see [DayDate.addMonths]); explicit bases ignore [purchaseDate].
  DayDate endDate(DayDate purchaseDate);
}

/// Coverage measured as a whole-number count of calendar months from the
/// purchase date (e.g. 24 months, 3 years == 36 months).
final class DurationFromPurchase extends CoverageBasis {
  /// A duration of [months] calendar months. Must be at least one month;
  /// zero/negative durations are rejected so a mistyped "0" can never be
  /// read as "covered for nothing" versus a missing line.
  DurationFromPurchase({required this.months}) {
    if (months < 1) {
      throw ArgumentError.value(months, 'months', 'must be at least 1');
    }
  }

  /// Convenience for year-based terms (store extended warranties are often
  /// sold in whole years).
  DurationFromPurchase.years(int years) : months = years * 12 {
    if (years < 1) {
      throw ArgumentError.value(years, 'years', 'must be at least 1');
    }
  }

  /// The term length in calendar months (years are normalized to months).
  final int months;

  @override
  DayDate endDate(DayDate purchaseDate) => purchaseDate.addMonths(months);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DurationFromPurchase && other.months == months;

  @override
  int get hashCode => Object.hash(DurationFromPurchase, months);

  @override
  String toString() => 'DurationFromPurchase($months months)';
}

/// Coverage with a fixed calendar end date entered directly by the user
/// (e.g. "manufacturer warranty ends 2027-06-30").
final class ExplicitEndDate extends CoverageBasis {
  const ExplicitEndDate({required this.endDateValue});

  /// The fixed day the coverage ends (inclusive — the item is still covered
  /// during that whole day).
  final DayDate endDateValue;

  @override
  DayDate endDate(DayDate purchaseDate) => endDateValue;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExplicitEndDate && other.endDateValue == endDateValue;

  @override
  int get hashCode => Object.hash(ExplicitEndDate, endDateValue);

  @override
  String toString() => 'ExplicitEndDate($endDateValue)';
}

/// A single tracked coverage window attached to a purchase item.
final class CoverageLine {
  const CoverageLine({
    required this.kind,
    required this.basis,
    this.label,
  });

  /// Which kind of window this is (return, manufacturer, extended).
  final CoverageLineKind kind;

  /// How the end date is derived.
  final CoverageBasis basis;

  /// Optional free-text label ("Costco extended 3-year"), for display only.
  final String? label;
}
