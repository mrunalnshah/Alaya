/// Unit reference data for the expense forms.
///
/// Watches `unitRepositoryProvider` from `app/providers/` — no repository is declared here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Every unit, for the quantity field's picker.
final unitsProvider = StreamProvider<List<Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll(),
);

/// Units within one category.
///
/// `UnitPicker` also filters, deliberately — a picker that trusts its input to be category-correct is
/// one bad call site away from breaking Law L8. This provider narrows the stream so the common case
/// does not ship every unit to the widget.
final unitsInCategoryProvider = StreamProvider.family<List<Unit>, UnitCategory>(
  (ref, category) =>
      ref.watch(unitRepositoryProvider).watchByCategory(category),
);
