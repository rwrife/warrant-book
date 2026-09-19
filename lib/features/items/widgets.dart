// Warrant Book — shared registry widgets (issue #4).
//
// Status chips carry an explicit icon glyph in addition to color so the
// status never depends on color alone, and they override their semantics
// label with a role + status + color-description phrase (issue #7
// accessibility pass).

import 'package:flutter/material.dart';

import '../../domain/coverage.dart';
import '../../l10n/generated/app_localizations.dart';

/// Status chip palette (issue #7 accessibility audit).
///
/// Chips render on a transparent background directly over
/// [ColorScheme.surface]; these label colors are the measured-contrast
/// set (WCAG AA >= 4.5:1 on both light and dark surfaces — the exact
/// ratios are asserted in test/features/a11y_test.dart).
class StatusChipPalette {
  /// Active (green) chip label color, light theme.
  static const Color activeLight = Color(0xFF1B5E20);

  /// Expiring (orange) chip label color, light theme.
  static const Color expiringLight = Color(0xFFBF360C);

  /// Expired (red) chip label color, light theme.
  static const Color expiredLight = Color(0xFFB71C1C);

  /// No-coverage (gray) chip label color, light theme.
  static const Color noneLight = Color(0xFF49454F);

  /// Active chip label color, dark theme.
  static const Color activeDark = Color(0xFFA5D6A7);

  /// Expiring chip label color, dark theme.
  static const Color expiringDark = Color(0xFFFFA000);

  /// Expired chip label color, dark theme.
  static const Color expiredDark = Color(0xFFFFB4AB);

  /// No-coverage chip label color, dark theme.
  static const Color noneDark = Color(0xFFCAC4D0);

  static (Color, IconData) forSeverity(
    CoverageSeverity severity,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;
    return switch (severity) {
      CoverageSeverity.active => (
          dark ? activeDark : activeLight,
          Icons.check_circle_outline,
        ),
      CoverageSeverity.expiring => (
          dark ? expiringDark : expiringLight,
          Icons.timelapse,
        ),
      CoverageSeverity.expired => (
          dark ? expiredDark : expiredLight,
          Icons.cancel_outlined,
        ),
    };
  }

  static Color noneColor(Brightness brightness) =>
      brightness == Brightness.dark ? noneDark : noneLight;
}

/// Chip for a single coverage line's status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final CoverageLineStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StatusChipBase(
      label: switch (status) {
        CoverageLineStatus.active => l10n.statusActive,
        CoverageLineStatus.expiring => l10n.statusExpiring,
        CoverageLineStatus.expired => l10n.statusExpired,
      },
      severity: switch (status) {
        CoverageLineStatus.active => CoverageSeverity.active,
        CoverageLineStatus.expiring => CoverageSeverity.expiring,
        CoverageLineStatus.expired => CoverageSeverity.expired,
      },
    );
  }
}

/// Chip for an item-level rolled-up status (adds the "no coverage lines"
/// state that a line-level chip can never represent).
class ItemStatusChip extends StatelessWidget {
  const ItemStatusChip(this.status, {super.key});

  final ItemCoverageStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (status == ItemCoverageStatus.none) {
      final scheme = Theme.of(context).colorScheme;
      final color = StatusChipPalette.noneColor(scheme.brightness);
      return Semantics(
        label: l10n.statusChipSemantics(
            l10n.statusNone, l10n.statusColorGray),
        excludeSemantics: true,
        child: Chip(
          backgroundColor: Colors.transparent,
          avatar: Icon(Icons.help_outline, size: 14, color: color),
          label: Text(l10n.statusNone),
          labelStyle: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: color),
          side: BorderSide(color: color),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return _StatusChipBase(
      label: switch (status) {
        ItemCoverageStatus.none => '',
        ItemCoverageStatus.active => l10n.statusActive,
        ItemCoverageStatus.expiring => l10n.statusExpiring,
        ItemCoverageStatus.expired => l10n.statusExpired,
      },
      severity: status.severity!,
    );
  }
}

class _StatusChipBase extends StatelessWidget {
  const _StatusChipBase({required this.label, required this.severity});

  final String label;
  final CoverageSeverity severity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Contrast-checked status palette (issue #7 accessibility audit);
    // exact measured ratios live in test/features/a11y_test.dart. The
    // chip background is transparent so the label sits directly on the
    // deterministic scaffold surface, and the icon glyph keeps the
    // distinction visible without color perception.
    final (color, glyph) =
        StatusChipPalette.forSeverity(severity, scheme.brightness);
    final colorWord = switch (severity) {
      CoverageSeverity.active => l10n.statusColorGreen,
      CoverageSeverity.expiring => l10n.statusColorOrange,
      CoverageSeverity.expired => l10n.statusColorRed,
    };
    return Semantics(
      label: l10n.statusChipSemantics(label, colorWord),
      excludeSemantics: true,
      child: Chip(
        backgroundColor: Colors.transparent,
        avatar: Icon(glyph, size: 14, color: color),
        label: Text(label),
        labelStyle:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        side: BorderSide(color: color),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Human phrasing of "how long is left" for one computed line status.
String remainingLabel(AppLocalizations l10n, LineStatus line) {
  if (line.daysRemaining > 0) return l10n.daysRemaining(line.daysRemaining);
  if (line.daysRemaining == 0) return l10n.endsToday;
  return l10n.daysOverdue(-line.daysRemaining);
}
