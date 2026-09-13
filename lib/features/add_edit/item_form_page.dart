// Warrant Book — add/edit purchase form (issue #4).
//
// One form serves both flows (`existing == null` means "add"). Design
// rules from the issue's acceptance criteria:
//
// - Domain validation is enforced inline: the form parses its inputs into
//   real domain objects (which reject invalid values at construction) and
//   runs `validateItem` before saving; problems render per-field, and the
//   save button cannot bypass them.
// - Duration inputs recompute the coverage end date LIVE on every keystroke
//   and purchase-date change (issue: "duration inputs show the computed
//   end date live").
// - Price/currency are optional with missing ≠ zero: empty+empty is
//   "not recorded"; partial input is an inline error, never a silent 0.

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../domain/models/coverage_line.dart';
import '../../domain/models/day_date.dart';
import '../../domain/models/purchase_item.dart';
import '../../domain/validation.dart';
import '../../l10n/generated/app_localizations.dart';

/// Add form (`existing == null`) or edit form (aggregate supplied).
class ItemFormPage extends StatefulWidget {
  const ItemFormPage({this.existing, super.key});

  final PurchaseItem? existing;

  @override
  State<ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends State<ItemFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late DayDate _purchaseDate;
  late final TextEditingController _category;
  late final TextEditingController _store;
  late final TextEditingController _price;
  late final TextEditingController _currency;
  late final List<_LineEditor> _lines;

  /// After a failed save attempt, the domain-level problems to surface.
  List<String> _problems = const [];

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    final scope = AppScope.read(context);
    _name = TextEditingController(text: item?.name ?? '');
    _purchaseDate = item?.purchaseDate ?? scope.today;
    _category = TextEditingController(text: item?.category ?? '');
    _store = TextEditingController(text: item?.store ?? '');
    _price = TextEditingController(
      text: item?.price.amount?.toString() ?? '',
    );
    _currency = TextEditingController(text: item?.price.currencyCode ?? '');
    _lines = [
      if (item != null)
        for (final line in item.coverageLines) _LineEditor.fromLine(line)
      else
        _LineEditor(),
    ];
    for (final editor in _lines) {
      editor.addListener(_onChanged);
    }
  }

  /// Any editor keystroke can change a computed end date, so rebuild the
  /// whole form — that is what re-renders the live "Ends ..." previews.
  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final editor in _lines) {
      editor.dispose();
    }
    _name.dispose();
    _category.dispose();
    _store.dispose();
    _price.dispose();
    _currency.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  Future<void> _pickPurchaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(
          _purchaseDate.year, _purchaseDate.month, _purchaseDate.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(DateTime.now().year + 50),
    );
    if (picked != null) {
      setState(() => _purchaseDate = DayDate.fromDateTime(picked));
    }
  }

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    setState(() => _problems = const []);
    if (_formKey.currentState?.validate() != true) return;

    final scope = AppScope.of(context);
    final PurchaseItem item;
    try {
      item = _buildItem(scope.repository.newItemId());
    } on ArgumentError catch (error) {
      setState(() => _problems = ['${error.message}']);
      return;
    }

    final problems = validateItem(item);
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }

    await scope.repository.save(item);
    navigator.pop(true);
  }

  PurchaseItem _buildItem(String id) {
    final existing = widget.existing;
    final amountText = _price.text.trim();
    final currencyText = _currency.text.trim().toUpperCase();
    final price = amountText.isEmpty && currencyText.isEmpty
        ? const PurchaseRecordedPrice.missing()
        : PurchaseRecordedPrice.money(
            double.parse(amountText), currencyText);

    return PurchaseItem(
      id: existing?.id ?? id,
      name: _name.text.trim(),
      purchaseDate: _purchaseDate,
      category: _emptyToNull(_category.text),
      store: _emptyToNull(_store.text),
      price: price,
      coverageLines: [
        for (final editor in _lines) editor.toLine(_purchaseDate),
      ],
      notes: existing?.notes ?? const [],
      attachments: existing?.attachments ?? const [],
      archived: existing?.archived ?? false,
    );
  }

  static String? _emptyToNull(String text) =>
      text.trim().isEmpty ? null : text.trim();

  /// Inline error for the price/currency pair (missing ≠ zero rules).
  String? _pricePairError() {
    final l10n = AppLocalizations.of(context);
    final amountText = _price.text.trim();
    final currencyText = _currency.text.trim();
    if (amountText.isEmpty && currencyText.isEmpty) return null;
    if (amountText.isEmpty) return l10n.priceNeedsAmount;
    if (currencyText.isEmpty) return l10n.priceNeedsCurrency;
    final amount = double.tryParse(amountText);
    if (amount == null || amount < 0) return l10n.priceNeedsAmount;
    if (!_isCurrency(currencyText)) return l10n.priceNeedsCurrency;
    return null;
  }

  static bool _isCurrency(String code) {
    if (code.length != 3) return false;
    final upper = code.toUpperCase();
    for (final unit in upper.codeUnits) {
      if (unit < 0x41 || unit > 0x5A) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? l10n.editPurchase : l10n.addPurchase),
        actions: [
          TextButton(
            key: const Key('saveButton'),
            onPressed: _save,
            child: Text(l10n.save),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('nameField'),
              controller: _name,
              decoration: InputDecoration(labelText: l10n.fieldName),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? l10n.nameRequired : null,
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('purchaseDateField'),
              onTap: _pickPurchaseDate,
              child: InputDecorator(
                decoration:
                    InputDecoration(labelText: l10n.fieldPurchaseDate),
                child: Text('$_purchaseDate'),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('categoryField'),
              controller: _category,
              decoration: InputDecoration(labelText: l10n.fieldCategory),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('storeField'),
              controller: _store,
              decoration: InputDecoration(labelText: l10n.fieldStore),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('priceField'),
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _onChanged(),
              decoration: InputDecoration(
                labelText: l10n.fieldPrice,
                errorText: _pricePairError(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('currencyField'),
              controller: _currency,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => _onChanged(),
              maxLength: 3,
              decoration: InputDecoration(
                labelText: l10n.fieldCurrency,
                counterText: '',
                errorText: _pricePairError(),
              ),
            ),
            const Divider(height: 32),
            Text(l10n.coverageLinesSection,
                style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < _lines.length; i++) ...[
              const SizedBox(height: 12),
              _LineEditorCard(
                editor: _lines[i],
                purchaseDate: _purchaseDate,
                index: i,
                onRemove: _lines.length > 1
                    ? () => setState(() => _lines.removeAt(i).dispose())
                    : null,
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const Key('addLineButton'),
                onPressed: () => setState(() {
                  _lines.add(_LineEditor()..addListener(_onChanged));
                }),
                icon: const Icon(Icons.add),
                label: Text(l10n.addCoverageLine),
              ),
            ),
            if (_problems.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(l10n.validationProblems,
                  style: Theme.of(context).textTheme.labelLarge),
              for (final problem in _problems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    problem,
                    key: Key('problem-$problem'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mutable state of one coverage-line editor row.
class _LineEditor extends ChangeNotifier {
  _LineEditor({String months = '', DayDate? endDate})
      : monthsText = TextEditingController(text: months) {
    endDateValue = endDate;
    monthsText.addListener(notifyListeners);
  }

  _LineEditor.fromLine(CoverageLine line)
      : kind = line.kind,
        durationMode = line.basis is DurationFromPurchase,
        monthsText = TextEditingController(
          text: line.basis is DurationFromPurchase
              ? '${(line.basis as DurationFromPurchase).months}'
              : '',
        ),
        endDateValue = line.basis is ExplicitEndDate
            ? (line.basis as ExplicitEndDate).endDateValue
            : null,
        label = line.label {
    monthsText.addListener(notifyListeners);
  }

  CoverageLineKind kind = CoverageLineKind.manufacturerWarranty;
  bool durationMode = true;
  final TextEditingController monthsText;
  DayDate? endDateValue;
  String? label;

  /// The line currently represented, or null while input is incomplete.
  CoverageLine? tryLine() {
    final CoverageBasis basis;
    if (durationMode) {
      final months = int.tryParse(monthsText.text.trim());
      if (months == null || months < 1) return null;
      basis = DurationFromPurchase(months: months);
    } else {
      final end = endDateValue;
      if (end == null) return null;
      basis = ExplicitEndDate(endDateValue: end);
    }
    return CoverageLine(kind: kind, basis: basis, label: label);
  }

  CoverageLine toLine(DayDate purchaseDate) {
    final line = tryLine();
    if (line == null) {
      throw ArgumentError(
        durationMode
            ? 'Enter a whole number of months (at least 1).'
            : 'Pick an end date for this coverage line.',
      );
    }
    return line;
  }

  void setKind(CoverageLineKind value) {
    kind = value;
    notifyListeners();
  }

  void setDurationMode(bool value) {
    durationMode = value;
    notifyListeners();
  }

  void setEndDate(DayDate? value) {
    endDateValue = value;
    notifyListeners();
  }

  void setLabel(String? value) {
    label = value;
    notifyListeners();
  }

  @override
  void dispose() {
    monthsText.dispose();
    super.dispose();
  }
}

class _LineEditorCard extends StatelessWidget {
  const _LineEditorCard({
    required this.editor,
    required this.purchaseDate,
    required this.index,
    required this.onRemove,
  });

  final _LineEditor editor;
  final DayDate purchaseDate;
  final int index;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Live end-date preview: recomputed on every rebuild (the editor
    // notifies the parent state on any keystroke that could change it).
    final line = editor.tryLine();
    final endPreview = line == null
        ? null
        : l10n.endsOn('${line.basis.endDate(purchaseDate)}');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<CoverageLineKind>(
                    key: Key('kindField-$index'),
                    initialValue: editor.kind,
                    decoration:
                        const InputDecoration(isDense: true),
                    items: [
                      DropdownMenuItem(
                        value: CoverageLineKind.returnWindow,
                        child: Text(l10n.kindReturnWindow),
                      ),
                      DropdownMenuItem(
                        value: CoverageLineKind.manufacturerWarranty,
                        child: Text(l10n.kindManufacturerWarranty),
                      ),
                      DropdownMenuItem(
                        value: CoverageLineKind.extendedWarranty,
                        child: Text(l10n.kindExtendedWarranty),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) editor.setKind(value);
                    },
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    key: Key('removeLine-$index'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.removeCoverageLine,
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              key: Key('basisToggle-$index'),
              segments: [
                ButtonSegment(value: true, label: Text(l10n.basisDuration)),
                ButtonSegment(value: false, label: Text(l10n.basisExplicit)),
              ],
              selected: {editor.durationMode},
              onSelectionChanged: (selection) =>
                  editor.setDurationMode(selection.first),
            ),
            const SizedBox(height: 8),
            if (editor.durationMode)
              TextFormField(
                key: Key('monthsField-$index'),
                controller: editor.monthsText,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.fieldMonths,
                  errorText: editor.monthsText.text.trim().isNotEmpty &&
                          int.tryParse(editor.monthsText.text.trim()) == null
                      ? l10n.invalidMonths
                      : null,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: Key('endDateField-$index'),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime(
                            (editor.endDateValue ?? purchaseDate).year,
                            (editor.endDateValue ?? purchaseDate).month,
                            (editor.endDateValue ?? purchaseDate).day,
                          ),
                          firstDate: DateTime(1900),
                          lastDate: DateTime(DateTime.now().year + 80),
                        );
                        if (picked != null) {
                          editor.setEndDate(DayDate.fromDateTime(picked));
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(isDense: true),
                        child: Text(
                          '${editor.endDateValue ?? ''}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            TextFormField(
              key: Key('labelField-$index'),
              initialValue: editor.label ?? '',
              decoration:
                  InputDecoration(labelText: l10n.fieldLabelOptional),
              onChanged: editor.setLabel,
            ),
            if (endPreview != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  key: Key('endPreview-$index'),
                  endPreview,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
