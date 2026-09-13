// Warrant Book — domain layer (issue #3).
//
// The repository contract the UI (issue #4) and the backup/export features
// (issue #6) will program against. It lives in `domain/` because it speaks
// only in domain types; the Drift implementation lives in
// `lib/data/repositories/` (see PLAN.md architecture).

import '../coverage.dart';
import '../models/day_date.dart';
import '../models/purchase_item.dart';

/// Filter criteria for registry listings, evaluated against a synthetic
/// "today" and an expiring-soon horizon (issue #3 acceptance criteria:
/// list-by-status, search by name/notes/store, category filter).
///
/// Immutable value object: UI code can build one per keystroke/re-render
/// without locking in any storage details.
final class ItemQuery {
  const ItemQuery({
    required this.today,
    this.horizonDays = 30,
    this.status,
    this.category,
    this.search,
    this.includeArchived = false,
    this.coverageNow = false,
    this.expiringSoon = false,
    this.archiveView = false,
  });

  /// The day statuses are evaluated against (the app passes "today";
  /// tests pass synthetic days).
  final DayDate today;

  /// Horizon in days for the [ItemCoverageStatus.expiring] classification.
  /// Matches [lineStatus]'s `horizonDays` semantics.
  final int horizonDays;

  /// When non-null, only items whose rolled-up coverage status equals this.
  final ItemCoverageStatus? status;

  /// When non-null, only items whose category matches exactly.
  final String? category;

  /// When non-null (and non-blank after trimming), only items whose name,
  /// store, or any note text contains this substring, case-insensitively.
  final String? search;

  /// Archived items are hidden by default in active/search views (issue #4);
  /// the archive view ([archiveView]) overrides this.
  final bool includeArchived;

  /// Issue #4 "Coverage now" tab: items with at least one line still
  /// covering today (status active or expiring — an expiring line covers
  /// until its end day), plus plain registry entries with no coverage
  /// lines at all (they can never expire, so no other list would ever
  /// show them).
  final bool coverageNow;

  /// Issue #4 "Expiring soon" tab: items with at least one line whose end
  /// date falls inside the horizon window on [today].
  final bool expiringSoon;

  /// Issue #4 "Archive" tab: archived items, plus non-archived items whose
  /// every coverage line is expired.
  final bool archiveView;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemQuery &&
          other.today == today &&
          other.horizonDays == horizonDays &&
          other.status == status &&
          other.category == category &&
          other.search == search &&
          other.includeArchived == includeArchived &&
          other.coverageNow == coverageNow &&
          other.expiringSoon == expiringSoon &&
          other.archiveView == archiveView;

  @override
  int get hashCode => Object.hash(today, horizonDays, status, category,
      search, includeArchived, coverageNow, expiringSoon, archiveView);
}

/// Durable storage for the purchase registry.
///
/// Implementations must be safe for sequential use from the UI isolate.
/// [save] persists the whole aggregate: coverage lines, notes and attachment
/// references are replaced by the ones present on [PurchaseItem] (the
/// aggregate boundary; individual child-row edits are not part of the API).
abstract interface class ItemRepository {
  /// Mints a new, collision-resistant identifier for a not-yet-saved item
  /// (`PurchaseItem.id` is required at construction, so ids are minted
  /// before the domain object exists).
  String newItemId();

  /// The stored item with [id], fully assembled (lines, notes, attachments),
  /// or null when nothing is stored under it.
  Future<PurchaseItem?> findById(String id);

  /// Insert or update [item], replacing its child rows. Implementations wrap
  /// the write in a transaction.
  Future<void> save(PurchaseItem item);

  /// Deletes the item. Coverage lines, notes and attachment *rows* cascade;
  /// attachment *files* are cleaned up by the document store in issue #6.
  /// Returns false when no item with [id] existed.
  Future<bool> delete(String id);

  /// All stored items matching [query], newest purchase first.
  Future<List<PurchaseItem>> list(ItemQuery query);

  /// Distinct non-null categories in the registry, alphabetically sorted
  /// (evaluated with `SELECT DISTINCT` — the filter UI must not scan the
  /// whole registry client-side to build its option list).
  Future<List<String>> categories();
}
