import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/qty_field.dart';

/// Items the line editor can attach a quantity to.
final lineEditorItemsProvider = StreamProvider.autoDispose<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Units in the category of the currently chosen item.
final lineEditorUnitsProvider = StreamProvider.autoDispose
    .family<List<Unit>, UnitCategory?>(
      (ref, category) => category == null
          ? Stream.value(const <Unit>[])
          : ref.watch(unitRepositoryProvider).watchByCategory(category),
    );

/// What [LineItemEditor] hands back: the line, and whether another should open straight away.
class LineItemDraft {
  /// Creates a result.
  const LineItemDraft({required this.line, this.addAnother = false});

  /// The line the user built.
  final TransactionLine line;

  /// Whether to reopen the editor blank once this one is stored.
  ///
  /// A grocery receipt is fifteen lines, and closing the sheet between each one made itemising an
  /// expense feel like fifteen separate tasks. The caller loops while this is true.
  final bool addAnother;
}

/// Edits one line of a transaction (ARCH_5 §3 archetype A).
///
/// **An Item can be created here, and that is what makes the receipt reach the inventory at all.**
/// `PurchaseFanOutService._planBatch` refuses a line without `itemId`, so without an inline create a
/// user on a fresh install itemises a grocery receipt, saves it, and nothing ever appears in the
/// inventory — the batch was never planned. The catalogue is discovered while typing the receipt,
/// exactly as a payee is.
///
/// **Quantity is offered only once an Item is chosen, and that is the schema talking rather than a
/// simplification.** A `Qty` is an integer plus a `UnitCategory`, and the category comes from the
/// Item — it is immutable per Item and cross-category conversion does not exist (Law L8). A free-text
/// line has no category, so a quantity on it would be a number whose meaning nothing records. It is
/// also exactly what the fan-out requires: `_planBatch` refuses a line without a catalogued item,
/// because a batch with a guessed quantity is stock the user never bought.
class LineItemEditor extends ConsumerStatefulWidget {
  /// Edits [line], or creates a new one when it is null.
  const LineItemEditor({
    required this.currencyCode,
    required this.decimalDigits,
    required this.defaultDestination,
    this.line,
    super.key,
  });

  /// The transaction's currency. A line cannot be denominated in another.
  final String currencyCode;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// What a new line should default to — inventory for a grocery or household purchase.
  final TransactionLineDestination defaultDestination;

  /// The line being edited, or null for a new one.
  final TransactionLine? line;

  /// Opens the sheet, resolving to the edited line or null.
  static Future<LineItemDraft?> show(
    BuildContext context, {
    required String currencyCode,
    required int decimalDigits,
    required TransactionLineDestination defaultDestination,
    TransactionLine? line,
  }) => AlayaBottomSheet.show<LineItemDraft>(
    context: context,
    builder: (context) => LineItemEditor(
      currencyCode: currencyCode,
      decimalDigits: decimalDigits,
      defaultDestination: defaultDestination,
      line: line,
    ),
  );

  @override
  ConsumerState<LineItemEditor> createState() => _LineItemEditorState();
}

class _LineItemEditorState extends ConsumerState<LineItemEditor> {
  late final TextEditingController _description = TextEditingController(
    text: widget.line?.description ?? '',
  );
  late TransactionLineDestination _destination =
      widget.line?.destination ?? widget.defaultDestination;
  late String? _itemId = widget.line?.itemId;
  late Qty? _quantity = widget.line?.quantity;

  /// The unit code the quantity is entered in.
  ///
  /// **Held as a code, seeded from the saved line.** `QtyField` formats its initial text against the
  /// `selectedUnit` it is handed, so a null here fell back to `units.first` — milligram — and a line
  /// saved as `50 kg` reopened as `50000000 mg`. The units list arrives asynchronously, so the code is
  /// what persists and the `Unit` is resolved from it on each build.
  late String? _unitCode = widget.line?.unitCode;
  late Money? _unitPrice = widget.line?.unitPrice;
  late Money? _lineAmount = widget.line?.lineAmount;
  bool _descriptionMissing = false;
  bool _creatingItem = false;
  UnitCategory _newItemCategory = UnitCategory.count;
  bool _createFailed = false;

  Future<void> _createItem() async {
    final name = _description.text.trim();
    if (name.isEmpty) {
      setState(() => _descriptionMissing = true);
      return;
    }
    final item = Item(
      id: ref.read(uidGeneratorProvider).generate(),
      name: name,
      normalizedName: ref.read(normalizerProvider).normalize(name),
      unitCategory: _newItemCategory,
      defaultDisplayUnitCode: _newItemCategory.baseUnitCode,
      itemKind: ItemKind.generic,
      isFavorite: false,
    );
    final saved = await ref.read(itemRepositoryProvider).save(item);
    if (!mounted) return;
    final value = saved.valueOrNull;
    setState(() {
      _createFailed = value == null;
      if (value == null) return;
      _itemId = value.id;
      _creatingItem = false;
      _unitCode = value.defaultDisplayUnitCode;
      _quantity = null;
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _submit({bool addAnother = false}) {
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _descriptionMissing = true);
      return;
    }
    final existing = widget.line;
    final line = TransactionLine(
      id: existing?.id ?? ref.read(uidGeneratorProvider).generate(),
      transactionId: existing?.transactionId ?? '',
      lineNo: existing?.lineNo ?? 1,
      description: description,
      destination: _destination,
      itemId: _itemId,
      quantity: _quantity,
      unitCode: _unitCode ?? existing?.unitCode,
      unitPrice: _unitPrice,
      lineAmount: _lineAmount,
      createdBatchId: existing?.createdBatchId,
      createdAssetId: existing?.createdAssetId,
      createdRecurringTemplateId: existing?.createdRecurringTemplateId,
      note: existing?.note,
    );
    Navigator.of(
      context,
    ).pop(LineItemDraft(line: line, addAnother: addAnother));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final items =
        ref.watch(lineEditorItemsProvider).valueOrNull ?? const <Item>[];
    Item? selectedItem;
    for (final item in items) {
      if (item.id == _itemId) {
        selectedItem = item;
        break;
      }
    }
    final units =
        ref
            .watch(lineEditorUnitsProvider(selectedItem?.unitCategory))
            .valueOrNull ??
        const <Unit>[];
    Unit? selectedUnit;
    for (final unit in units) {
      if (unit.code == _unitCode) selectedUnit = unit;
    }
    // Prefer the item's own display unit over the first in the list: a catalogue entry measured in
    // kilograms should not open in milligrams just because that sorts first.
    if (selectedUnit == null) {
      for (final unit in units) {
        if (unit.code == selectedItem?.defaultDisplayUnitCode)
          selectedUnit = unit;
      }
    }
    selectedUnit ??= units.isEmpty ? null : units.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.lineDescription,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _description,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: strings.lineDescription,
            errorText: _descriptionMissing ? strings.errorFieldRequired : null,
          ),
          onChanged: (_) {
            if (_descriptionMissing)
              setState(() => _descriptionMissing = false);
          },
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<TransactionLineDestination>(
          key: ValueKey(_destination),
          initialValue: _destination,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelCategory),
          items: [
            for (final destination in TransactionLineDestination.values)
              DropdownMenuItem(
                value: destination,
                child: Text(_destinationLabel(strings, destination)),
              ),
          ],
          onChanged: (value) => value == null
              ? null
              : setState(() {
                  _destination = value;
                  // Cleared with the fields: a stale item link on an asset line would reach
                  // `_planBatch` and be refused, for a quantity the user was never shown.
                  if (value != TransactionLineDestination.inventory) {
                    _itemId = null;
                    _quantity = null;
                    _unitCode = null;
                    _creatingItem = false;
                  }
                }),
        ),
        // **The label alone never said which was which.** "Add to inventory" and "Add to services"
        // are indistinguishable to anyone who has not read the schema, so an iPhone went to inventory,
        // was refused for want of a quantity, and appeared in neither place. The helper names a real
        // example of each: consumed versus kept is the whole distinction.
        Padding(
          padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
          child: Text(
            _destinationHelp(strings, _destination),
            style: AlayaTypography.caption.copyWith(
              color: context.semantic.muted,
            ),
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // **Only inventory needs an item, a quantity and a unit.** A television has no grams and a
        // recurring line has no stock; offering the fields anyway invited an iPhone to be filed as
        // measured stock, which `_planBatch` then refused for want of a quantity. The whole block is
        // gated on the destination rather than each field being individually pointless.
        if (_destination == TransactionLineDestination.inventory) ...[
          if (_creatingItem)
            _NewItemRow(
              category: _newItemCategory,
              onCategoryChanged: (category) =>
                  setState(() => _newItemCategory = category),
              onCreate: _createItem,
              onCancel: () => setState(() => _creatingItem = false),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: items.isEmpty
                      ? Text(
                          strings.itemCreateHint,
                          style: AlayaTypography.caption.copyWith(
                            color: context.semantic.muted,
                          ),
                        )
                      : DropdownButtonFormField<String>(
                          // **`selectedItem?.id`, not `_itemId`.** The items arrive from a stream, so on the frame
                          // right after an inline create the state already names the new item while the list has
                          // not re-emitted it — and a dropdown holding a value none of its items carry throws
                          // "There should be exactly one item", which is a red screen. Deriving the value from the
                          // list being rendered makes the mismatch unrepresentable.
                          key: ValueKey(selectedItem?.id),
                          initialValue: selectedItem?.id,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: strings.labelItem,
                          ),
                          items: [
                            for (final item in items)
                              DropdownMenuItem(
                                value: item.id,
                                child: Text(
                                  item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => setState(() {
                            // **Picking an item fills the description.** The two are different columns — the
                            // description is what the receipt said, `itemId` is what it stocks — but the receipt
                            // almost always says the item's name, and making the user retype "onion" after
                            // choosing Onion is friction with no purpose. An edit of their own is never
                            // overwritten: the fill only happens while the field is empty or still holds the
                            // previously-picked item's name.
                            final previous = _nameOf(items, _itemId);
                            _itemId = value;
                            final picked = _nameOf(items, value);
                            final typed = _description.text.trim();
                            if (picked != null &&
                                (typed.isEmpty || typed == previous)) {
                              _description.text = picked;
                              _descriptionMissing = false;
                            }
                            // The category changed, so any unit and quantity chosen against the old one is now
                            // meaningless rather than merely stale — Law L8 has no cross-category conversion.
                            _unitCode = null;
                            _quantity = null;
                          }),
                        ),
                ),
                const SizedBox(width: AlayaSpacing.xs),
                TextButton(
                  onPressed: () => setState(() => _creatingItem = true),
                  child: Text(strings.itemCreate),
                ),
              ],
            ),
          if (_createFailed) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              strings.errorBodyGeneric,
              style: AlayaTypography.caption.copyWith(
                color: context.semantic.danger,
              ),
            ),
          ],
          if (selectedItem != null &&
              units.isNotEmpty &&
              selectedUnit != null) ...[
            const SizedBox(height: AlayaSpacing.md),
            QtyField(
              key: ValueKey('${selectedItem.id}:${selectedUnit.code}'),
              category: selectedItem.unitCategory,
              units: units,
              selectedUnit: selectedUnit,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: _quantity,
              onChanged: (quantity) => _quantity = quantity,
              onUnitChanged: (unit) => setState(() => _unitCode = unit.code),
            ),
          ],
        ],
        const SizedBox(height: AlayaSpacing.md),
        AmountField(
          currencyCode: widget.currencyCode,
          decimalDigits: widget.decimalDigits,
          label: strings.lineUnitPrice,
          initialValue: _unitPrice,
          onChanged: (value) => _unitPrice = value,
        ),
        const SizedBox(height: AlayaSpacing.md),
        AmountField(
          currencyCode: widget.currencyCode,
          decimalDigits: widget.decimalDigits,
          label: strings.lineAmount,
          initialValue: _lineAmount,
          onChanged: (value) => _lineAmount = value,
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(onPressed: _submit, child: Text(strings.actionDone)),
        const SizedBox(height: AlayaSpacing.xs),
        // The bulk path. Itemising a receipt should not mean opening and closing this sheet once per
        // line, so this commits and reopens blank; the caller keeps looping while it is asked to.
        TextButton.icon(
          onPressed: () => _submit(addAnother: true),
          icon: const Icon(Icons.add, size: AlayaIconSize.sm),
          label: Text(strings.lineItemsSaveAndAnother),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }

  static String? _nameOf(List<Item> items, String? id) {
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item.name;
    }
    return null;
  }

  static String _categoryLabel(AlayaStrings strings, UnitCategory category) =>
      switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  static String _destinationLabel(
    AlayaStrings strings,
    TransactionLineDestination destination,
  ) => switch (destination) {
    TransactionLineDestination.none => strings.destinationNone,
    TransactionLineDestination.inventory => strings.destinationInventory,
    TransactionLineDestination.asset => strings.destinationAsset,
    TransactionLineDestination.recurring => strings.destinationRecurring,
  };

  static String _destinationHelp(
    AlayaStrings strings,
    TransactionLineDestination destination,
  ) => switch (destination) {
    TransactionLineDestination.none => strings.destinationHelpNone,
    TransactionLineDestination.inventory => strings.destinationHelpInventory,
    TransactionLineDestination.asset => strings.destinationHelpAsset,
    TransactionLineDestination.recurring => strings.destinationHelpRecurring,
  };
}

class _NewItemRow extends StatelessWidget {
  const _NewItemRow({
    required this.category,
    required this.onCategoryChanged,
    required this.onCreate,
    required this.onCancel,
  });

  final UnitCategory category;
  final ValueChanged<UnitCategory> onCategoryChanged;
  final VoidCallback onCreate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.itemCreateCategoryPrompt,
          style: AlayaTypography.label.copyWith(color: context.semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        SegmentedButton<UnitCategory>(
          segments: [
            for (final option in UnitCategory.values)
              ButtonSegment(
                value: option,
                label: Text(
                  _LineItemEditorState._categoryLabel(strings, option),
                ),
              ),
          ],
          selected: {category},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onCategoryChanged(selection.first),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onCreate,
                child: Text(strings.itemCreate),
              ),
            ),
            const SizedBox(width: AlayaSpacing.xs),
            TextButton(onPressed: onCancel, child: Text(strings.actionCancel)),
          ],
        ),
      ],
    );
  }
}
