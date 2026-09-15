// Warrant Book — local-first purchase warranty tracker.
//
// App bootstrap (issue #4): opens the on-device database, wires the
// repository + settings into AppScope, and shows the registry. No
// telemetry, no accounts, no network — see README.md privacy contract.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_scope.dart';
import 'data/repositories/drift_item_repository.dart';
import 'domain/models/day_date.dart';
import 'domain/repositories/item_repository.dart';
import 'features/item_detail/item_detail_page.dart';
import 'features/items/registry_home_page.dart';
import 'features/reminders/local_notifications_platform.dart';
import 'features/reminders/reminder_scheduler.dart';
import 'features/reminders/rescheduling_item_repository.dart';
import 'features/settings/app_settings.dart';
import 'l10n/generated/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final db = openWarrantBookDatabase('${dir.path}/warrant_book.db');
  final settings = await AppSettings.load(SharedPreferencesSettingsStore());
  final baseRepository = DriftItemRepository(db);
  final reminderScheduler = ReminderScheduler(
    repository: baseRepository,
    settings: settings,
    platform: LocalNotificationsPlatform(),
  );
  await reminderScheduler.initialize();
  runApp(
    WarrantBookApp(
      repository: ReschedulingItemRepository(
        baseRepository,
        reminderScheduler,
        settings,
      ),
      settings: settings,
      reminderScheduler: reminderScheduler,
    ),
  );
}

/// Root widget for Warrant Book.
///
/// [repository], [settings] and [today] are injectable so widget tests run
/// against an in-memory database with a frozen calendar day.
class WarrantBookApp extends StatefulWidget {
  const WarrantBookApp({
    required this.repository,
    required this.settings,
    this.today,
    this.reminderScheduler,
    this.clock = DateTime.now,
    super.key,
  });

  final ItemRepository repository;
  final AppSettings settings;

  /// A fixed calendar day for deterministic tests. Production leaves this
  /// null and derives the current day from [clock].
  final DayDate? today;
  final ReminderScheduler? reminderScheduler;
  final DateTime Function() clock;

  @override
  State<WarrantBookApp> createState() => _WarrantBookAppState();
}

class _WarrantBookAppState extends State<WarrantBookApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  Timer? _midnightTimer;
  late DayDate _today;

  @override
  void initState() {
    super.initState();
    _today = widget.today ?? DayDate.fromDateTime(widget.clock());
    WidgetsBinding.instance.addObserver(this);
    widget.reminderScheduler?.pendingItemTap.addListener(_routePendingTap);
    WidgetsBinding.instance.addPostFrameCallback((_) => _routePendingTap());
    _scheduleMidnightRefresh();
  }

  @override
  void didUpdateWidget(WarrantBookApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reminderScheduler != widget.reminderScheduler) {
      oldWidget.reminderScheduler?.pendingItemTap.removeListener(
        _routePendingTap,
      );
      widget.reminderScheduler?.pendingItemTap.addListener(_routePendingTap);
      WidgetsBinding.instance.addPostFrameCallback((_) => _routePendingTap());
    }
    if (oldWidget.today != widget.today || oldWidget.clock != widget.clock) {
      _refreshToday();
      _scheduleMidnightRefresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshToday();
      _scheduleMidnightRefresh();
      final scheduler = widget.reminderScheduler;
      if (scheduler != null) unawaited(scheduler.recompute());
    }
  }

  void _refreshToday() {
    final today = widget.today ?? DayDate.fromDateTime(widget.clock());
    if (today != _today && mounted) setState(() => _today = today);
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    if (widget.today != null) return;
    final now = widget.clock();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(tomorrow.difference(now), () {
      _refreshToday();
      _scheduleMidnightRefresh();
    });
  }

  Future<void> _routePendingTap() async {
    final scheduler = widget.reminderScheduler;
    final itemId = scheduler?.pendingItemTap.value;
    final navigator = _navigatorKey.currentState;
    if (scheduler == null || itemId == null || navigator == null) return;
    scheduler.consumePendingTap();
    if (await widget.repository.findById(itemId) == null || !mounted) return;
    await navigator.pushNamed('/item', arguments: itemId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    widget.reminderScheduler?.pendingItemTap.removeListener(_routePendingTap);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      repository: widget.repository,
      settings: widget.settings,
      today: _today,
      reminderScheduler: widget.reminderScheduler,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
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
        routes: {'/item': (context) => const _ItemIdRoute()},
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
