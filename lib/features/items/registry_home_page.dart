// Warrant Book — core registry lists (issue #4).
//
// Home screen: three status tabs (Coverage now / Expiring soon / Archive),
// a text search over name/store/notes evaluated in SQL, and a category
// filter chip row fed by `SELECT DISTINCT`. All items come from the
// repository; status filtering uses the same domain rollup as everywhere
// else. Screens own no business logic beyond rendering.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/coverage.dart';
import '../../domain/models/purchase_item.dart';
import '../../domain/repositories/item_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../add_edit/item_form_page.dart';
import '../settings/app_settings.dart';
import '../settings/settings_dialog.dart';
import 'widgets.dart';

/// Tabbed registry home screen.
class RegistryHomePage extends StatefulWidget {
  const RegistryHomePage({super.key});

  @override
  State<RegistryHomePage> createState() => _RegistryHomePageState();
}

class _RegistryHomePageState extends State<RegistryHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  AppSettings? _settings;

  /// Search text actually applied to queries (commits on submit / clear,
  /// not per keystroke — no DB fan per character).
  String _searchText = '';
  String? _category;
  List<String> _categories = const [];
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    unawaited(_refreshCategories());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = AppScope.of(context).settings;
    if (!identical(settings, _settings)) {
      _settings?.removeListener(_onSettingsChanged);
      _settings = settings..addListener(_onSettingsChanged);
    }
  }

  void _onSettingsChanged() {
    if (mounted) setState(() => _reloadToken++);
  }

  @override
  void dispose() {
    _settings?.removeListener(_onSettingsChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refreshCategories() async {
    // `read` (not `of`): this runs from initState, which may not subscribe.
    final categories = await AppScope.read(context).repository.categories();
    if (mounted) setState(() => _categories = categories);
  }

  ItemQuery _queryFor(int tabIndex, AppScope scope) {
    return ItemQuery(
      today: scope.today,
      horizonDays: scope.settings.horizonDays,
      search: _searchText,
      category: _category,
      coverageNow: tabIndex == 0,
      expiringSoon: tabIndex == 1,
      archiveView: tabIndex == 2,
    );
  }

  Future<void> _openAddForm() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ItemFormPage()),
    );
    if (changed == true) {
      await _refreshCategories();
      if (mounted) setState(() => _reloadToken++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            key: const Key('settingsButton'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsAction,
            onPressed: () => showSettingsDialog(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: l10n.tabCoverageNow),
            Tab(text: l10n.tabExpiringSoon),
            Tab(text: l10n.tabArchive),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              key: const Key('searchField'),
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) =>
                  setState(() => _searchText = value.trim()),
              onChanged: (value) {
                if (value.trim().isEmpty && _searchText.isNotEmpty) {
                  setState(() => _searchText = '');
                }
              },
            ),
          ),
          _CategoryFilterRow(
            categories: _categories,
            selected: _category,
            onSelected: (c) => setState(() => _category = c),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (var i = 0; i < 3; i++)
                  _ItemListTab(
                    query: _queryFor(i, scope),
                    tabIndex: i,
                    reloadToken: _reloadToken,
                    hasActiveSearch: _searchText.isNotEmpty,
                    onItemRoutePopped: () =>
                        setState(() => _reloadToken++),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addPurchaseButton'),
        onPressed: _openAddForm,
        icon: const Icon(Icons.add),
        label: Text(l10n.addPurchase),
      ),
    );
  }
}

class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (categories.isEmpty) return const SizedBox(height: 4);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          ChoiceChip(
            key: const Key('categoryChip-all'),
            label: Text(l10n.categoryAll),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final category in categories) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              key: Key('categoryChip-$category'),
              label: Text(category),
              selected: selected == category,
              onSelected: (_) => onSelected(category),
            ),
          ],
        ],
      ),
    );
  }
}

class _ItemListTab extends StatelessWidget {
  const _ItemListTab({
    required this.query,
    required this.tabIndex,
    required this.reloadToken,
    required this.hasActiveSearch,
    required this.onItemRoutePopped,
  });

  final ItemQuery query;
  final int tabIndex;
  final int reloadToken;
  final bool hasActiveSearch;
  final VoidCallback onItemRoutePopped;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = AppScope.of(context);

    return FutureBuilder<List<PurchaseItem>>(
      key: ValueKey('list-$tabIndex-$reloadToken-${query.category}'),
      future: scope.repository.list(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('${snapshot.error}'),
            ),
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return ListView(
            key: const PageStorageKey('empty-list'),
            children: [
              const SizedBox(height: 96),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    hasActiveSearch
                        ? l10n.emptySearch(query.search!)
                        : switch (tabIndex) {
                            0 => l10n.emptyCoverageNow,
                            1 => l10n
                                .emptyExpiringSoon(scope.settings.horizonDays),
                            _ => l10n.emptyArchive,
                          },
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) => ItemRowTile(
            item: items[index],
            onOpened: onItemRoutePopped,
          ),
        );
      },
    );
  }
}

/// One registry row: name, rolled-up status chip, next milestone hint.
class ItemRowTile extends StatelessWidget {
  const ItemRowTile({required this.item, this.onOpened, super.key});

  final PurchaseItem item;

  /// Called when the detail route opened from this row pops.
  final VoidCallback? onOpened;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = AppScope.of(context);
    final statuses = allLineStatuses(item, scope.today,
        horizonDays: scope.settings.horizonDays);
    final rolled = itemCoverageStatus(item, scope.today,
        horizonDays: scope.settings.horizonDays);

    // Highlight the soonest line that is not expired yet.
    LineStatus? highlight;
    for (final s in statuses) {
      if (s.status != CoverageLineStatus.expired &&
          (highlight == null || s.endDate.isBefore(highlight.endDate))) {
        highlight = s;
      }
    }

    return ListTile(
      key: Key('itemRow-${item.id}'),
      title: Text(item.name),
      subtitle: Text(
        item.archived
            ? '${l10n.archivedBadge} · ${item.purchaseDate}'
            : '${item.purchaseDate}'
                  '${highlight == null ? '' : ' · ${remainingLabel(l10n, highlight)}'}',
      ),
      trailing: ItemStatusChip(rolled),
      onTap: () async {
        final navigator = Navigator.of(context);
        await navigator.pushNamed('/item', arguments: item.id);
        // Returned from the detail screen: edits/archives/deletes there
        // may have changed what this list should show.
        onOpened?.call();
      },
    );
  }
}
