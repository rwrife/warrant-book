import '../../domain/models/purchase_item.dart';
import '../../domain/repositories/item_repository.dart';
import '../settings/app_settings.dart';
import 'reminder_scheduler.dart';

/// Keeps notification state derived from, and never ahead of, committed DB
/// state. Scheduler/plugin failures are contained by [ReminderScheduler].
class ReschedulingItemRepository implements ItemRepository {
  ReschedulingItemRepository(this._delegate, this._scheduler, this._settings);

  final ItemRepository _delegate;
  final ReminderScheduler _scheduler;
  final AppSettings _settings;

  @override
  Future<void> save(PurchaseItem item) async {
    await _delegate.save(item);
    await _scheduler.recompute();
  }

  @override
  Future<bool> delete(String id) async {
    final deleted = await _delegate.delete(id);
    if (deleted) await _settings.removeItemReminderOverride(id);
    await _scheduler.recompute();
    return deleted;
  }

  @override
  Future<PurchaseItem?> findById(String id) => _delegate.findById(id);

  @override
  Future<List<PurchaseItem>> list(ItemQuery query) => _delegate.list(query);

  @override
  Future<List<String>> categories() => _delegate.categories();

  @override
  String newItemId() => _delegate.newItemId();
}
