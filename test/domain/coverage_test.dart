// Issue #2: exhaustive unit tests for the pure-Dart domain layer.
//
// Covers the acceptance criteria list:
// - month/year-boundary arithmetic
// - leap day (Feb 29 purchase + 1/4 years)
// - end-of-month truncation (Jan 31 + 1 month)
// - timezone-independent day boundaries
// - status monotonicity (fixed end dates never regress expired -> active)
// - empty-coverage-line items
// - validation rules + missing != zero price semantics
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:warrant_book/domain/coverage.dart';
import 'package:warrant_book/domain/models/coverage_line.dart';
import 'package:warrant_book/domain/models/day_date.dart';
import 'package:warrant_book/domain/models/purchase_item.dart';
import 'package:warrant_book/domain/validation.dart';

PurchaseItem itemWith(
  List<CoverageLine> lines, {
  DayDate? purchaseDate,
}) {
  return PurchaseItem(
    id: 'test',
    name: 'Drill',
    purchaseDate: purchaseDate ?? DayDate(2026, 1, 10),
    coverageLines: lines,
  );
}

void main() {
  group('DayDate basics', () {
    test('rejects impossible calendar days', () {
      expect(() => DayDate(2026, 2, 30), throwsA(isA<ArgumentError>()));
      expect(() => DayDate(2025, 2, 29), throwsA(isA<ArgumentError>()));
      expect(() => DayDate(2024, 2, 29), isNot(throwsA(isA<Exception>())));
      expect(() => DayDate(2026, 13, 1), throwsA(isA<ArgumentError>()));
      expect(() => DayDate(2026, 4, 31), throwsA(isA<ArgumentError>()));
    });

    test('daysUntil boundary pairs', () {
      expect(DayDate(2026, 1, 10).daysUntil(DayDate(2026, 1, 10)), 0);
      expect(DayDate(2026, 1, 10).daysUntil(DayDate(2026, 1, 11)), 1);
      expect(DayDate(2026, 1, 10).daysUntil(DayDate(2026, 1, 9)), -1);
      expect(DayDate(2026, 2, 28).daysUntil(DayDate(2026, 3, 1)), 1);
      expect(DayDate(2024, 2, 28).daysUntil(DayDate(2024, 3, 1)), 2);
    });

    test('equality and ordering', () {
      expect(DayDate(2026, 3, 5), DayDate(2026, 3, 5));
      expect(DayDate(2026, 3, 5).hashCode, DayDate(2026, 3, 5).hashCode);
      expect(DayDate(2025, 12, 31).isBefore(DayDate(2026, 1, 1)), isTrue);
      expect(DayDate(2026, 1, 1).isAtOrAfter(DayDate(2026, 1, 1)), isTrue);
    });
  });

  group('month/year boundary arithmetic', () {
    test('Jan 31 + 1 month truncates to Feb 28 (common year)', () {
      expect(DayDate(2026, 1, 31).addMonths(1), DayDate(2026, 2, 28));
    });

    test('Jan 31 + 1 month truncates to Feb 29 (leap year)', () {
      expect(DayDate(2024, 1, 31).addMonths(1), DayDate(2024, 2, 29));
    });

    test('Jan 31 + 1 month truncates to Apr 30 style targets', () {
      expect(DayDate(2026, 3, 31).addMonths(1), DayDate(2026, 4, 30));
      expect(DayDate(2026, 1, 30).addMonths(1), DayDate(2026, 2, 28));
    });

    test('month math crosses year boundaries both directions', () {
      expect(DayDate(2026, 11, 15).addMonths(2), DayDate(2027, 1, 15));
      expect(DayDate(2026, 1, 15).addMonths(23), DayDate(2027, 12, 15));
      expect(DayDate(2026, 12, 31).addMonths(1), DayDate(2027, 1, 31));
    });

    test('year math keeps day-of-month when valid', () {
      expect(DayDate(2026, 6, 15).addYears(1), DayDate(2027, 6, 15));
      expect(DayDate(2026, 6, 15).addYears(3), DayDate(2029, 6, 15));
    });
  });

  group('leap day handling', () {
    test('Feb 29 + 1 year clamps to Feb 28', () {
      expect(DayDate(2024, 2, 29).addMonths(12), DayDate(2025, 2, 28));
      expect(DayDate(2024, 2, 29).addYears(1), DayDate(2025, 2, 28));
    });

    test('Feb 29 + 4 years lands on Feb 29 again', () {
      expect(DayDate(2024, 2, 29).addYears(4), DayDate(2028, 2, 29));
    });

    test('century rules: 2100 not leap, 2000 leap', () {
      expect(DayDate(2096, 2, 29).addYears(4), DayDate(2100, 2, 28));
      expect(DayDate(1996, 2, 29).addYears(4), DayDate(2000, 2, 29));
    });

    test('duration line bought on leap day gets clamped end date', () {
      final line = CoverageLine(
        kind: CoverageLineKind.manufacturerWarranty,
        basis: DurationFromPurchase.years(1),
      );
      expect(
        lineStatus(line, DayDate(2024, 2, 29), DayDate(2026, 1, 1))
            .endDate,
        DayDate(2025, 2, 28),
      );
    });
  });

  group('timezone-independent day boundaries', () {
    test('fromDateTime uses wall-calendar fields, not the UTC instant', () {
      // Local midnight vs 23:59 same calendar day must map to the same date
      // regardless of the runner's zone.
      final morning = DateTime(2026, 7, 4, 0, 30);
      final evening = DateTime(2026, 7, 4, 23, 59);
      expect(DayDate.fromDateTime(morning), DayDate(2026, 7, 4));
      expect(DayDate.fromDateTime(evening), DayDate(2026, 7, 4));
    });

    test('a DayDate is stable under toUtc round-trip via daysUntil', () {
      final d = DayDate(2026, 11, 1);
      // DST-switch month (US): day math must not drift by an hour anywhere.
      expect(d.addDays(1), DayDate(2026, 11, 2));
      expect(d.daysUntil(d.addDays(400)), 400);
    });

    test('status on the final covered day is expiring, not expired', () {
      final line = CoverageLine(
        kind: CoverageLineKind.returnWindow,
        basis: ExplicitEndDate(
          endDateValue: DayDate(2026, 2, 9),
        ),
      );
      final onLastDay = lineStatus(
        line,
        DayDate(2026, 1, 10),
        DayDate(2026, 2, 9),
      );
      expect(onLastDay.status, CoverageLineStatus.expiring);
      expect(onLastDay.daysRemaining, 0);

      final dayAfter = lineStatus(
        line,
        DayDate(2026, 1, 10),
        DayDate(2026, 2, 10),
      );
      expect(dayAfter.status, CoverageLineStatus.expired);
      expect(dayAfter.daysRemaining, -1);
    });
  });

  group('line status math', () {
    test('active vs expiring respects the horizon window', () {
      final purchase = DayDate(2026, 1, 10);
      final line = CoverageLine(
        kind: CoverageLineKind.manufacturerWarranty,
        basis: DurationFromPurchase(months: 24),
      );
      // Ends 2028-01-10. On 2027-12-11 exactly 30 days remain -> expiring.
      final at30 = lineStatus(line, purchase, DayDate(2027, 12, 11));
      expect(at30.endDate, DayDate(2028, 1, 10));
      expect(at30.status, CoverageLineStatus.expiring);
      expect(at30.daysRemaining, 30);

      final at31 = lineStatus(line, purchase, DayDate(2027, 12, 10));
      expect(at31.daysRemaining, 31);
      expect(at31.status, CoverageLineStatus.active);
    });

    test('zero horizon: still expiring on the final day only', () {
      final line = CoverageLine(
        kind: CoverageLineKind.returnWindow,
        basis: DurationFromPurchase(months: 1),
      );
      final last = lineStatus(
        line,
        DayDate(2026, 1, 31),
        DayDate(2026, 2, 28),
        horizonDays: 0,
      );
      expect(last.status, CoverageLineStatus.expiring);
      final earlier = lineStatus(
        line,
        DayDate(2026, 1, 31),
        DayDate(2026, 2, 27),
        horizonDays: 0,
      );
      expect(earlier.status, CoverageLineStatus.active);
    });

    test('negative horizon is rejected', () {
      expect(
        () => lineStatus(
          CoverageLine(
            kind: CoverageLineKind.returnWindow,
            basis: ExplicitEndDate(
              endDateValue: DayDate(2026, 5, 1),
            ),
          ),
          DayDate(2026, 1, 1),
          DayDate(2026, 1, 1),
          horizonDays: -1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('explicit basis ignores purchase date anchor', () {
      final line = CoverageLine(
        kind: CoverageLineKind.extendedWarranty,
        basis: ExplicitEndDate(
          endDateValue: DayDate(2030, 12, 31),
        ),
      );
      expect(
        lineStatus(line, DayDate(1999, 5, 5), DayDate(2026, 1, 1)).endDate,
        DayDate(2030, 12, 31),
      );
    });

    test('duration basis anchors on purchase date, not today', () {
      final line = CoverageLine(
        kind: CoverageLineKind.returnWindow,
        basis: DurationFromPurchase(months: 1),
      );
      // Purchased 2026-01-05; one month later == 2026-02-05 regardless of
      // which "today" we ask about.
      expect(
        lineStatus(line, DayDate(2026, 1, 5), DayDate(2026, 1, 6)).endDate,
        DayDate(2026, 2, 5),
      );
      expect(
        lineStatus(line, DayDate(2026, 1, 5), DayDate(2031, 9, 9)).endDate,
        DayDate(2026, 2, 5),
      );
    });
  });

  group('status monotonicity (property-style)', () {
    test('fixed and duration lines never regress as today advances', () {
      final rng = Random(1234);
      for (var trial = 0; trial < 500; trial++) {
        final purchase = DayDate(
          2020 + rng.nextInt(10),
          1 + rng.nextInt(12),
          1 + rng.nextInt(28),
        );
        final end = purchase.addMonths(1 + rng.nextInt(40));
        final bases = <CoverageBasis>[
          ExplicitEndDate(endDateValue: end),
          DurationFromPurchase(months: 1 + rng.nextInt(40)),
        ];
        for (final basis in bases) {
          final line = CoverageLine(
            kind: CoverageLineKind.manufacturerWarranty,
            basis: basis,
          );
          var previousRank = -1;
          var today = purchase.addDays(-(1 + rng.nextInt(400)));
          final stop = purchase.addDays(1600);
          while (today.isAtOrBefore(stop)) {
            final status = lineStatus(line, purchase, today);
            final rank = status.status.severity.index;
            expect(
              rank >= previousRank,
              isTrue,
              reason: 'regression $previousRank -> $rank at $today',
            );
            previousRank = rank;
            today = today.addDays(1 + rng.nextInt(7));
          }
          // And the terminal state must eventually be expired.
          expect(
            lineStatus(line, purchase, purchase.addDays(1700)).status,
            CoverageLineStatus.expired,
          );
        }
      }
    });

    test('explicit end-date line: expired stays expired forever', () {
      final line = CoverageLine(
        kind: CoverageLineKind.returnWindow,
        basis: ExplicitEndDate(
          endDateValue: DayDate(2026, 3, 1),
        ),
      );
      for (final later in [
        DayDate(2026, 3, 2),
        DayDate(2027, 1, 1),
        DayDate(2126, 1, 1),
      ]) {
        expect(
          lineStatus(line, DayDate(2026, 1, 1), later).status,
          CoverageLineStatus.expired,
        );
      }
    });
  });

  group('item-level rollup', () {
    test('empty-coverage item reports none, never covered', () {
      final bare = itemWith(const []);
      expect(
        itemCoverageStatus(bare, DayDate(2026, 5, 1)),
        ItemCoverageStatus.none,
      );
      expect(allLineStatuses(bare, DayDate(2026, 5, 1)), isEmpty);
    });

    test('worst severity wins (active + expired == expired)', () {
      final purchase = DayDate(2026, 1, 1);
      final active = CoverageLine(
        kind: CoverageLineKind.manufacturerWarranty,
        basis: DurationFromPurchase(months: 24),
      );
      final expired = CoverageLine(
        kind: CoverageLineKind.returnWindow,
        basis: DurationFromPurchase(months: 1),
      );
      expect(
        itemCoverageStatus(
          itemWith([active, expired], purchaseDate: purchase),
          DayDate(2026, 6, 1),
        ),
        ItemCoverageStatus.expired,
      );
    });

    test('expiring beats active but loses to expired', () {
      final purchase = DayDate(2026, 1, 1);
      final soonish = CoverageLine(
        kind: CoverageLineKind.manufacturerWarranty,
        basis: ExplicitEndDate(
          endDateValue: DayDate(2026, 6, 15),
        ),
      );
      final active = CoverageLine(
        kind: CoverageLineKind.extendedWarranty,
        basis: ExplicitEndDate(
          endDateValue: DayDate(2028, 6, 15),
        ),
      );
      final gone = CoverageLine(
        kind: CoverageLineKind.returnWindow,
        basis: ExplicitEndDate(
          endDateValue: DayDate(2026, 1, 31),
        ),
      );
      final today = DayDate(2026, 6, 1);
      expect(
        itemCoverageStatus(
          itemWith([active, soonish], purchaseDate: purchase),
          today,
        ),
        ItemCoverageStatus.expiring,
      );
      expect(
        itemCoverageStatus(
          itemWith([active, soonish, gone], purchaseDate: purchase),
          today,
        ),
        ItemCoverageStatus.expired,
      );
    });

    test('all-active item is active', () {
      final purchase = DayDate(2026, 1, 1);
      final a = CoverageLine(
        kind: CoverageLineKind.returnWindow,
        basis: DurationFromPurchase(months: 2),
      );
      final b = CoverageLine(
        kind: CoverageLineKind.manufacturerWarranty,
        basis: DurationFromPurchase(months: 36),
      );
      expect(
        itemCoverageStatus(
          itemWith([a, b], purchaseDate: purchase),
          DayDate(2026, 1, 15),
        ),
        ItemCoverageStatus.active,
      );
    });
  });

  group('missing != zero price semantics', () {
    test('missing price is not equal to zero price', () {
      const missing = PurchaseRecordedPrice.missing();
      final zero = PurchaseRecordedPrice.money(0.0, 'USD');
      expect(missing, isNot(zero));
      expect(missing.isMissing, isTrue);
      expect(zero.isMissing, isFalse);
      expect(zero.amount, 0.0);
      expect(missing.amount, isNull);
      expect(missing.currencyCode, isNull);
    });

    test('money rejects negative, NaN, infinity, bad currency codes', () {
      expect(
        () => PurchaseRecordedPrice.money(-0.01, 'USD'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PurchaseRecordedPrice.money(double.nan, 'USD'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => PurchaseRecordedPrice.money(double.infinity, 'USD'),
        throwsA(isA<ArgumentError>()),
      );
      for (final bad in ['US', 'USDD', 'usd', 'U\$D']) {
        expect(
          () => PurchaseRecordedPrice.money(10, bad),
          throwsA(isA<ArgumentError>()),
          reason: 'currency code "$bad" must be rejected',
        );
      }
      expect(PurchaseRecordedPrice.money(0, 'USD').amount, 0);
    });
  });

  group('basis construction guards', () {
    test('zero/negative durations cannot be constructed', () {
      expect(
        () => DurationFromPurchase(months: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => DurationFromPurchase(months: -3),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => DurationFromPurchase.years(0),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('years normalize to months and compare by value', () {
      expect(DurationFromPurchase.years(2), DurationFromPurchase(months: 24));
      expect(
        ExplicitEndDate(
          endDateValue: DayDate(2027, 1, 1),
        ),
        ExplicitEndDate(
          endDateValue: DayDate(2027, 1, 1),
        ),
      );
    });
  });

  group('validation rules', () {
    test('valid item produces no problems', () {
      final item = PurchaseItem(
        id: 'x',
        name: 'Monitor',
        purchaseDate: DayDate(2026, 1, 2),
        price: PurchaseRecordedPrice.money(349.99, 'USD'),
        category: 'electronics',
        store: 'Best Buy',
        coverageLines: [
          CoverageLine(
            kind: CoverageLineKind.returnWindow,
            basis: DurationFromPurchase(months: 1),
          ),
        ],
        notes: [Note(text: 'bought on sale', recordedOn: DayDate(2026, 1, 2))],
      );
      expect(validateItem(item), isEmpty);
    });

    test('blank name flagged', () {
      expect(
        validateItem(
          PurchaseItem(id: 'x', name: '   ', purchaseDate: DayDate(2026, 1, 2)),
        ),
        contains('Item name is required.'),
      );
    });

    test('explicit end date before purchase date flagged', () {
      final item = PurchaseItem(
        id: 'x',
        name: 'Toaster',
        purchaseDate: DayDate(2026, 5, 1),
        coverageLines: [
          CoverageLine(
            kind: CoverageLineKind.manufacturerWarranty,
            basis: ExplicitEndDate(
              endDateValue: DayDate(2026, 4, 30),
            ),
          ),
        ],
      );
      expect(validateItem(item), hasLength(1));
      expect(validateItem(item).single, contains('before the purchase date'));
    });

    test('absurdly long durations flagged', () {
      final item = PurchaseItem(
        id: 'x',
        name: 'Toaster',
        purchaseDate: DayDate(2026, 5, 1),
        coverageLines: [
          CoverageLine(
            kind: CoverageLineKind.extendedWarranty,
            basis: DurationFromPurchase(months: 700),
          ),
        ],
      );
      expect(validateItem(item), contains('Coverage line #1 duration exceeds 50 years.'));
    });

    test('far-future purchase date flagged when today provided', () {
      expect(
        validatePurchaseDate(
          DayDate(2040, 1, 1),
          today: DayDate(2026, 1, 1),
        ),
        contains('Purchase date is more than 10 years in the future.'),
      );
      expect(
        validatePurchaseDate(
          DayDate(2027, 1, 1),
          today: DayDate(2026, 1, 1),
        ),
        isEmpty,
      );
    });

    test('empty note text flagged', () {
      final item = PurchaseItem(
        id: 'x',
        name: 'Kettle',
        purchaseDate: DayDate(2026, 1, 2),
        notes: [Note(text: '  ', recordedOn: DayDate(2026, 1, 2))],
      );
      expect(validateItem(item), contains('Note #1 is empty.'));
    });
  });

  group('domain purity', () {
    test('domain sources never import Flutter or Drift', () {
      // Structural guarantee for issue #2: everything under lib/domain must
      // stay dependency-free (pure Dart), so coverage math is testable and
      // reusable outside Flutter.
      final domainRoot = Directory('lib/domain');
      expect(domainRoot.existsSync(), isTrue,
          reason: 'tests must run from the package root');
      final offenders = <String>[];
      for (final entity in domainRoot.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('package:flutter') ||
            source.contains('package:drift') ||
            source.contains('dart:io') ||
            source.contains('package:warrant_book/data')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'domain must be pure Dart with no Flutter/Drift/IO deps');
    });
  });
}
