// Warrant Book — pure-Dart domain layer (issue #2).
//
// `DayDate` is a calendar date with no time-of-day and no time zone. All
// coverage date math in the domain is performed on `DayDate` values so that
// status computation is identical regardless of the device's clock settings
// (no DST or UTC-offset drift can shift a coverage boundary by a day).

/// True when [year] is a Gregorian leap year.
bool isGregorianLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

/// Number of days in [month] (1-12) of [year].
int daysInGregorianMonth(int year, int month) {
  if (month < 1 || month > 12) {
    throw ArgumentError.value(month, 'month', 'must be 1-12');
  }
  switch (month) {
    case 1 || 3 || 5 || 7 || 8 || 10 || 12:
      return 31;
    case 4 || 6 || 9 || 11:
      return 30;
    default:
      return isGregorianLeapYear(year) ? 29 : 28;
  }
}

/// An immutable proleptic-Gregorian calendar date (year, month, day).
final class DayDate implements Comparable<DayDate> {
  /// Constructs a date from explicit calendar fields.
  DayDate(int year, int month, int day)
      : year = year,
        month = month,
        day = day {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be 1-12');
    }
    final maxDay = daysInGregorianMonth(year, month);
    if (day < 1 || day > maxDay) {
      throw ArgumentError.value(day, 'day', 'must be 1-$maxDay for $month');
    }
  }

  /// Extracts the wall-calendar date of [moment] as seen in its own zone.
  ///
  /// Only the calendar fields are read; the time-of-day and the zone offset
  /// are discarded, so a `DateTime` in any zone maps to the same `DayDate`
  /// as the calendar date the user would recognize on a wall calendar.
  factory DayDate.fromDateTime(DateTime moment) =>
      DayDate(moment.year, moment.month, moment.day);

  /// Parses the canonical ISO-8601 form `yyyy-MM-dd` — exactly what
  /// [toString] emits — as used by the persistence layer (issue #3).
  ///
  /// Throws [FormatException] for anything else (no lenient parsing: a
  /// corrupt stored date must fail loudly, not silently shift a coverage
  /// window).
  factory DayDate.parseIso(String iso) {
    final match = _isoPattern.firstMatch(iso);
    if (match == null) {
      throw FormatException('Expected yyyy-MM-dd, got "$iso"');
    }
    // The constructor re-validates the calendar fields, so a stored
    // "2026-02-30" throws rather than rolling over.
    return DayDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static final RegExp _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');


  /// The proleptic-Gregorian year (negative allowed for BCE if ever needed).
  final int year;

  /// Month of the year, 1-12.
  final int month;

  /// Day of the month, 1-[daysInMonth].
  final int day;

  /// Number of days in this date's month (28-31).
  int get daysInMonth => daysInGregorianMonth(year, month);

  DateTime _midnightUtc() => DateTime.utc(year, month, day);

  /// Whole days from this date up to [later]; negative when [later] is
  /// earlier than this date. Same-day pairs always return exactly 0.
  int daysUntil(DayDate later) =>
      later._midnightUtc().difference(_midnightUtc()).inDays;

  /// Returns this date shifted by [months] calendar months.
  ///
  /// Day-of-month is clamped to the length of the target month (end-of-month
  /// truncation): 2026-01-31 + 1 month is 2026-02-28, and 2024-02-29 + 1 year
  /// is 2025-02-28 while 2024-02-29 + 4 years is 2028-02-29.
  DayDate addMonths(int months) {
    final zeroBasedMonth = (month - 1) + months;
    final monthRemainder = zeroBasedMonth % 12; // Dart % is non-negative.
    final targetYear = year + (zeroBasedMonth - monthRemainder) ~/ 12;
    final targetMonth = monthRemainder + 1;
    final maxDay = daysInGregorianMonth(targetYear, targetMonth);
    final targetDay = day <= maxDay ? day : maxDay;
    return DayDate(targetYear, targetMonth, targetDay);
  }

  /// Returns this date shifted by whole calendar years.
  DayDate addYears(int years) => addMonths(years * 12);

  DayDate addDays(int days) {
    final shifted = _midnightUtc().add(Duration(days: days));
    return DayDate(shifted.year, shifted.month, shifted.day);
  }

  bool isBefore(DayDate other) => compareTo(other) < 0;

  bool isAfter(DayDate other) => compareTo(other) > 0;

  bool isAtOrBefore(DayDate other) => compareTo(other) <= 0;

  bool isAtOrAfter(DayDate other) => compareTo(other) >= 0;

  @override
  int compareTo(DayDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayDate &&
          other.year == year &&
          other.month == month &&
          other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
