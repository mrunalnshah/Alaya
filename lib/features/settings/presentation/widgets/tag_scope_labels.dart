import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/enums/tag_scope.dart';

/// The name of each place a tag may be offered.
///
/// **One switch, shared by the list and the editor**, so a scope cannot be called one thing on the row and
/// another in the matrix that sets it. Exhaustive over [TagScope] without a `default`, so adding a seventh
/// picker to the app fails to compile here instead of shipping a chip with no label.
String tagScopeLabel(AlayaStrings strings, TagScope scope) => switch (scope) {
  TagScope.deposit => strings.tagScopeDeposit,
  TagScope.withdrawal => strings.tagScopeWithdrawal,
  TagScope.inventory => strings.tagScopeInventory,
  TagScope.shopping => strings.tagScopeShopping,
  TagScope.recurring => strings.tagScopeRecurring,
  TagScope.service => strings.tagScopeService,
};

/// What each scope actually controls, for the editor's matrix.
///
/// The help line matters more here than anywhere else in Settings: "Withdrawal" tells the reader nothing about
/// *why* unticking it would make a tag vanish from the screen they use most.
String tagScopeHelp(AlayaStrings strings, TagScope scope) => switch (scope) {
  TagScope.deposit => strings.tagScopeDepositHelp,
  TagScope.withdrawal => strings.tagScopeWithdrawalHelp,
  TagScope.inventory => strings.tagScopeInventoryHelp,
  TagScope.shopping => strings.tagScopeShoppingHelp,
  TagScope.recurring => strings.tagScopeRecurringHelp,
  TagScope.service => strings.tagScopeServiceHelp,
};
