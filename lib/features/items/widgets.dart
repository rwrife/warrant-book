// Warrant Book — shared registry widgets (issue #4).

import 'package:flutter/material.dart';

import '../../domain/coverage.dart';
import '../../l10n/generated/app_localizations.dart';

/// Chip for a single coverage line's status.
class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});

  final CoverageLineStatus status;

  @override
  Widget build(BuildContext context) {
    return _StatusChipBase(
      label: switch (status) {
        CoverageLineStatus.active =>
          AppLocalizations.of(context).statusActive,
        CoverageLineStatus.expiring =>
          AppLocalizations.of(context).statusExpiring,
        CoverageLineStatus.expired =>
          AppLocalizations.of(context).statusExpired,
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
    if (status == ItemCoverageStatus.none) {
      final color = Theme.of(context).colorScheme.outline;
      return Chip(
        label: Text(AppLocalizations.of(context).statusNone),
        labelStyle: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color),
        side: BorderSide(color: color),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );
    }
    return _StatusChipBase(
      label: switch (status) {
        ItemCoverageStatus.none => '',
        ItemCoverageStatus.active =>
          AppLocalizations.of(context).statusActive,
        ItemCoverageStatus.expiring =>
          AppLocalizations.of(context).statusExpiring,
        ItemCoverageStatus.expired =>
          AppLocalizations.of(context).statusExpired,
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
    final scheme = Theme.of(context).colorScheme;
    final color = switch (severity) {
      CoverageSeverity.active => scheme.primary,
      CoverageSeverity.expiring => scheme.tertiary,
      CoverageSeverity.expired => Colors.red,
    };
    return Chip(
      label: Text(label),
      labelStyle:
          Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      side: BorderSide(color: color),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Human phrasing of "how long is left" for one computed line status.
String remainingLabel(AppLocalizations l10n, LineStatus line) {
  if (line.daysRemaining > 0) return l10n.daysRemaining(line.daysRemaining);
  if (line.daysRemaining == 0) return l10n.endsToday;
  return l10n.daysOverdue(-line.daysRemaining);
}
