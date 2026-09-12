// Warrant Book — pure-Dart domain layer (issue #2).
//
// PurchaseItem is the aggregate root: what was bought, when, what it cost
// (possibly unknown), and its coverage lines. It depends on nothing outside
// `lib/domain/` — no Flutter, no Drift — so coverage math can be unit-tested
// as pure Dart (issue #2 acceptance criteria).

import 'coverage_line.dart';
import 'day_date.dart';

/// A recorded price: either an amount + currency, or an explicit "missing"
/// state ("I don't remember / no receipt"). Modeled as its own type so the
/// missing state can never be confused with the number zero
/// (issue #2: missing ≠ zero semantics).
final class PurchaseRecordedPrice {
  /// Prefer [PurchaseRecordedPrice.money] / [PurchaseRecordedPrice.missing].
  const PurchaseRecordedPrice._({this.amount, this.currencyCode});

  /// A known price of [amount] in ISO-4217 uppercase [currencyCode].
  PurchaseRecordedPrice.money(double amount, String currencyCode)
      : amount = amount,
        currencyCode = currencyCode {
    if (amount.isNaN || amount.isInfinite) {
      throw ArgumentError.value(amount, 'amount', 'must be finite');
    }
    if (amount < 0) {
      throw ArgumentError.value(amount, 'amount', 'must not be negative');
    }
    if (!_isCurrencyCode(currencyCode)) {
      throw ArgumentError.value(
        currencyCode,
        'currencyCode',
        'must be a 3-letter ISO-4217 code, uppercase',
      );
    }
  }

  /// The price was deliberately not recorded — distinct from 0.00.
  const PurchaseRecordedPrice.missing() : this._();

  /// The amount, or null when the price is missing.
  final double? amount;

  /// ISO-4217 code, or null when the price is missing.
  final String? currencyCode;

  /// True when the user recorded no price at all.
  bool get isMissing => amount == null;

  static bool _isCurrencyCode(String code) {
    if (code.length != 3) return false;
    for (final unit in code.codeUnits) {
      if (unit < 0x41 || unit > 0x5A) return false; // A-Z only
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurchaseRecordedPrice &&
          other.amount == amount &&
          other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(amount, currencyCode);

  @override
  String toString() =>
      isMissing ? 'PurchaseRecordedPrice.missing' : 'PurchaseRecordedPrice($amount $currencyCode)';
}

/// A timeline note on an item ("repair submitted, RMA 12345").
final class Note {
  const Note({required this.text, required this.recordedOn});

  /// Free-text note body.
  final String text;

  /// Calendar day the note was written.
  final DayDate recordedOn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note &&
          other.text == text &&
          other.recordedOn == recordedOn;

  @override
  int get hashCode => Object.hash(text, recordedOn);

  @override
  String toString() => 'Note($recordedOn: $text)';
}

/// A reference (not the bytes) to a receipt photo/PDF in the app-private
/// document store. File I/O and hashing are the data layer's job (issue #6);
/// the domain only tracks the reference.
final class AttachmentRef {
  const AttachmentRef({required this.relativePath, this.displayName});

  /// Path relative to the app-private documents root.
  final String relativePath;

  /// Original/user-facing file name for display.
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttachmentRef &&
          other.relativePath == relativePath &&
          other.displayName == displayName;

  @override
  int get hashCode => Object.hash(relativePath, displayName);

  @override
  String toString() => 'AttachmentRef($relativePath, $displayName)';
}

/// One registered purchase — the aggregate root of the domain.
final class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.name,
    required this.purchaseDate,
    this.category,
    this.store,
    this.price = const PurchaseRecordedPrice.missing(),
    this.coverageLines = const <CoverageLine>[],
    this.notes = const <Note>[],
    this.attachments = const <AttachmentRef>[],
    this.archived = false,
  });

  /// Stable identifier (minted by the repository in issue #3).
  final String id;

  /// Display name of the purchased thing ("Dewalt 12in drill").
  final String name;

  /// Required day of purchase — the anchor for every duration-based line and
  /// for return-window math. Required per issue #2.
  final DayDate purchaseDate;

  /// Optional grouping category.
  final String? category;

  /// Optional store / seller name.
  final String? store;

  /// Price with explicit missing≠zero semantics.
  final PurchaseRecordedPrice price;

  /// Coverage windows; the empty list is legal (plain registry item).
  final List<CoverageLine> coverageLines;

  /// Notes timeline.
  final List<Note> notes;

  /// Attached receipt references.
  final List<AttachmentRef> attachments;

  /// True when moved to the archive (issue #4 lists); archived items stop
  /// appearing in active coverage lists but keep their computed status.
  final bool archived;
}
