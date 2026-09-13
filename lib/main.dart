// Warrant Book — local-first purchase warranty tracker.
//
// App bootstrap (issue #4): opens the on-device database, wires the
// repository + settings into AppScope, and shows the registry. No
// telemetry, no accounts, no network — see README.md privacy contract.
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_scope.dart';
import 'data/repositories/drift_item_repository.dart';
import 'domain/models/day_date.dart';
import 'domain/repositories/item_repository.dart';
import 'features/item_detail/item_detail_page.dart';
import 'features/items/registry_home_page.dart';
import 'features/settings/app_settings.dart';
import 'l10n/generated/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final db = openWarrantBookDatabase('${dir.path}/warrant_book.db');
  final settings = await AppSettings.load(
    SharedPreferencesSettingsStore(),
  );
  runApp(
    WarrantBookApp(
      repository: DriftItemRepository(db),
      settings: settings,
      today: DayDate.fromDateTime(DateTime.now()),
    ),
  );
}

/// Root widget for Warrant Book.
///
/// [repository], [settings] and [today] are injectable so widget tests run
/// against an in-memory database with a frozen calendar day.
class WarrantBookApp extends StatelessWidget {
  const WarrantBookApp({
    required this.repository,
    required this.settings,
    required this.today,
    super.key,
  });

  final ItemRepository repository;
  final AppSettings settings;
  final DayDate today;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repository: repository,
      settings: settings,
      today: today,
      child: MaterialApp(
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
        home: const RegistryHomePage(),
        routes: {
          '/item': (context) => const _ItemIdRoute(),
        },
      ),
    );
  }
}

/// Resolves the item id passed as route arguments.
class _ItemIdRoute extends StatelessWidget {
  const _ItemIdRoute();

  @override
  Widget build(BuildContext context) {
    final id = ModalRoute.of(context)!.settings.arguments! as String;
    return ItemDetailPage(itemId: id);
  }
}
