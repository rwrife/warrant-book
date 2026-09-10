// Warrant Book — local-first purchase warranty tracker.
//
// Issue #1 workspace skeleton: app bootstrap, theme, and routing placeholder.
// Feature slices land under lib/features/ in later milestones (see PLAN.md).
import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';

void main() {
  runApp(const WarrantBookApp());
}

/// Root widget for Warrant Book.
class WarrantBookApp extends StatelessWidget {
  const WarrantBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const HomePlaceholder(),
    );
  }
}

/// Placeholder home screen until the core registry UI lands (issue #4).
class HomePlaceholder extends StatelessWidget {
  const HomePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: const Center(
        child: Text('Workspace skeleton — registry UI coming in M2.'),
      ),
    );
  }
}
