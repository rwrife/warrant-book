// Warrant Book — pure-Dart domain layer (issue #2).
//
// Coverage-status computation. Everything here is pure: given an item, a
// horizon, and "today" (as a DayDate), it reports per-line and item-level
// status. Unknown/missing input can never count as covered — the types make
// an un-anchored or zero-duration line impossible to construct, so a line
// that exists always has a real end date.

import 'models/coverage_line.dart';
import 'models/day_date.dart';
import 'models/purchase_item.dart';

/// Severity order for status rollup: expired > expiring > active.
/// [CoverageLineStatus] extends this so max-severity rollups work.
enum CoverageSeverity {
  /// Covered, not near its end.
  active,

  /// Covered, but its end date is within the horizon.
  expiring,

  /// No longer covered.
  expired,
}

/// Status of one coverage line on a given day.
enum CoverageLineStatus {
  /// Covered, end date is beyond `today + horizon`.
  active,

  /// Covered, and end date falls within the horizon window
  /// (`today <= end <= today + horizon`).
  expiring,

  /// `today > end` — the window closed at the end of its last covered day.
  expired;

  /// Severity used for item-level rollup.
  CoverageSeverity get severity => switch (this) {
        CoverageLineStatus.active => CoverageSeverity.active,
        CoverageLineStatus.expiring => CoverageSeverity.expiring,
        CoverageLineStatus.expired => CoverageSeverity.expired,
      };
}

/// Item-level rollup over all of an item's coverage lines.
enum ItemCoverageStatus {
  /// The item has no coverage lines at all (plain registry entry).
  /// Deliberately NOT the same as "active" — an empty item must never read
  /// as covered.
  none,

  /// Worst-case line is active.
  active,

  /// Worst-case line is expiring.
  expiring,

  /// Worst-case line is expired.
  expired;

  CoverageSeverity? get severity => switch (this) {
        ItemCoverageStatus.none => null,
        ItemCoverageStatus.active => CoverageSeverity.active,
        ItemCoverageStatus.expiring => CoverageSeverity.expiring,
        ItemCoverageStatus.expired => CoverageSeverity.expired,
      };
}

/// Computed status for one line, including the resolved end date and
/// remaining days — everything the UI (issue #4) needs to render a row.
final class LineStatus {
  const LineStatus({
    required this.line,
    required this.endDate,
    required this.status,
    required this.daysRemaining,
  });

  /// The line this status was computed for.
  final CoverageLine line;

  /// End of the last covered day (inclusive), derived from the basis.
  final DayDate endDate;

  /// active / expiring / expired as of `today`.
  final CoverageLineStatus status;

  /// Whole days from `today` until [endDate] (0 on the final covered day,
  /// negative after expiry).
  final int daysRemaining;
}

/// Computes the status of a single [line] on [today].
///
/// [purchaseDate] anchors duration bases ([DurationFromPurchase]); explicit
/// end-date bases ignore it.
///
/// Boundary semantics:
/// - A line whose end date equals [today] is still covered for that day and
///   is `expiring` (daysRemaining == 0) provided horizon >= 0.
/// - A line whose end date is before [today] is `expired`; it can never be
///   reported active again by recomputation — for a fixed end date the
///   status is monotonic in time (active → expiring → expired).
LineStatus lineStatus(
  CoverageLine line,
  DayDate purchaseDate,
  DayDate today, {
  int horizonDays = 30,
}) {
  if (horizonDays < 0) {
    throw ArgumentError.value(horizonDays, 'horizonDays', 'must be >= 0');
  }
  final end = line.basis.endDate(purchaseDate);
  final daysRemaining = today.daysUntil(end);
  final CoverageLineStatus status;
  if (daysRemaining < 0) {
    status = CoverageLineStatus.expired;
  } else if (daysRemaining <= horizonDays) {
    status = CoverageLineStatus.expiring;
  } else {
    status = CoverageLineStatus.active;
  }
  return LineStatus(
    line: line,
    endDate: end,
    status: status,
    daysRemaining: daysRemaining,
  );
}

/// Per-line statuses for every line on [item], in list order.
List<LineStatus> allLineStatuses(PurchaseItem item, DayDate today,
    {int horizonDays = 30}) {
  return [
    for (final line in item.coverageLines)
      lineStatus(line, item.purchaseDate, today, horizonDays: horizonDays),
  ];
}

/// Item-level rollup = max severity across lines (expired > expiring >
/// active). An item with no lines is [ItemCoverageStatus.none], never
/// "covered".
ItemCoverageStatus itemCoverageStatus(PurchaseItem item, DayDate today,
    {int horizonDays = 30}) {
  if (item.coverageLines.isEmpty) return ItemCoverageStatus.none;
  var worst = CoverageSeverity.active;
  for (final status
      in allLineStatuses(item, today, horizonDays: horizonDays)) {
    if (status.status.severity.index > worst.index) {
      worst = status.status.severity;
    }
  }
  return switch (worst) {
    CoverageSeverity.active => ItemCoverageStatus.active,
    CoverageSeverity.expiring => ItemCoverageStatus.expiring,
    CoverageSeverity.expired => ItemCoverageStatus.expired,
  };
}
