// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AlayaStringsEn extends AlayaStrings {
  AlayaStringsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Alaya';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navExpenses => 'Expenses';

  @override
  String get navInventory => 'Inventory';

  @override
  String get navShopping => 'Shopping';

  @override
  String get navRecurring => 'Recurring';

  @override
  String get navServices => 'Services';

  @override
  String get navCalendar => 'Calendar';

  @override
  String get navInsights => 'Insights';

  @override
  String get navSettings => 'Settings';

  @override
  String get navThemeLab => 'Theme Lab';

  @override
  String get actionSave => 'Save';

  @override
  String get actionSaved => 'Saved';

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionDeleted => 'Deleted';

  @override
  String get actionUndo => 'Undo';

  @override
  String get actionRetry => 'Try again';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionDone => 'Done';

  @override
  String get actionClose => 'Close';

  @override
  String get actionSelect => 'Select';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionClearAll => 'Clear all';

  @override
  String get actionSearch => 'Search';

  @override
  String get actionConfirm => 'Confirm';

  @override
  String get actionDiscard => 'Discard';

  @override
  String get actionKeepEditing => 'Keep editing';

  @override
  String get actionRemoveTag => 'Remove tag';

  @override
  String get actionClearSearch => 'Clear search';

  @override
  String get addExpense => 'Add expense';

  @override
  String get addIncome => 'Add income';

  @override
  String get addTransfer => 'Add transfer';

  @override
  String get addItem => 'Add item';

  @override
  String get addToShoppingList => 'Add to shopping list';

  @override
  String get dateToday => 'Today';

  @override
  String get dateYesterday => 'Yesterday';

  @override
  String get dateTomorrow => 'Tomorrow';

  @override
  String get emptyTitleNoTransactions => 'No transactions yet';

  @override
  String get emptyBodyNoTransactions =>
      'Add your first expense and it will appear here.';

  @override
  String get emptyTitleNoItems => 'Nothing in your inventory';

  @override
  String get emptyBodyNoItems =>
      'Add an item to start tracking what you have at home.';

  @override
  String get emptyTitleNoShopping => 'Your list is empty';

  @override
  String get emptyBodyNoShopping =>
      'Add something, or let Alaya suggest items you are low on.';

  @override
  String get emptyTitleNoRecurring => 'No recurring bills';

  @override
  String get emptyBodyNoRecurring =>
      'Set up a bill or subscription and Alaya will remind you when it is due.';

  @override
  String get emptyTitleNoResults => 'No matches';

  @override
  String get emptyBodyNoResults =>
      'Try a shorter search, or check the spelling.';

  @override
  String get loadingLabel => 'Loading';

  @override
  String get loadingTransactions => 'Loading transactions';

  @override
  String get errorTitleGeneric => 'That did not work';

  @override
  String get errorBodyGeneric => 'Something went wrong on our side. Try again.';

  @override
  String get errorTitleNotFound => 'Not found';

  @override
  String get errorBodyNotFound => 'This item may have been deleted.';

  @override
  String get errorBodyNoConnection =>
      'You are offline. Alaya works offline, but rates will not refresh.';

  @override
  String get errorFieldRequired => 'This is required';

  @override
  String get errorAmountInvalid => 'Enter an amount';

  @override
  String get errorAmountZero => 'Enter an amount greater than zero';

  @override
  String get errorAmountInvalidCharacter => 'Digits only';

  @override
  String get errorAmountNegativeNotAllowed => 'Enter a positive amount';

  @override
  String get errorAmountTooManyDecimals => 'Too many decimal places';

  @override
  String get errorAmountTooLarge => 'That amount is too large';

  @override
  String get errorQuantityTooLarge => 'That quantity is too large';

  @override
  String get errorQuantityInvalid => 'Enter a quantity';

  @override
  String get errorQuantityInvalidCharacter => 'Digits only';

  @override
  String get errorQuantityNegativeNotAllowed => 'Enter a positive quantity';

  @override
  String get errorQuantityTooPrecise => 'Too precise for this unit';

  @override
  String get errorDateInvalid => 'Choose a date';

  @override
  String get confirmDeleteTitle => 'Delete this?';

  @override
  String get confirmDeleteBody => 'You can undo this for the next few seconds.';

  @override
  String get confirmDiscardTitle => 'Discard your changes?';

  @override
  String get confirmDiscardBody => 'What you have typed will not be saved.';

  @override
  String get labelAmount => 'Amount';

  @override
  String get labelQuantity => 'Quantity';

  @override
  String get labelUnit => 'Unit';

  @override
  String get labelDate => 'Date';

  @override
  String get labelAccount => 'Account';

  @override
  String get labelPaymentMethod => 'Payment method';

  @override
  String get labelPayee => 'Payee';

  @override
  String get labelCategory => 'Category';

  @override
  String get labelTags => 'Tags';

  @override
  String get labelNote => 'Note';

  @override
  String get labelFrom => 'From';

  @override
  String get labelTo => 'To';

  @override
  String get labelItem => 'Item';

  @override
  String get labelExpiry => 'Expiry';

  @override
  String get labelTotal => 'Total';

  @override
  String get hintSelectAccount => 'Choose an account';

  @override
  String get hintSelectUnit => 'Choose a unit';

  @override
  String get hintSelectTags => 'Choose tags';

  @override
  String get hintSelectDate => 'Choose a date';

  @override
  String get hintSearchItems => 'Search items';

  @override
  String get hintNote => 'Add a note';

  @override
  String amountUnconverted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count amounts not converted',
      one: '1 amount not converted',
    );
    return '$_temp0';
  }

  @override
  String get amountApproximate => 'Approximate rate';

  @override
  String tagCountMore(int count) {
    return '+$count';
  }

  @override
  String get statusNeedsReview => 'Needs details';

  @override
  String get statusUnallocated => 'Unallocated';

  @override
  String get statusDetached => 'Receipt deleted';

  @override
  String get statusApproximate => 'Approximate';

  @override
  String get lowStockLabel => 'Low';

  @override
  String get expiringSoonLabel => 'Expiring soon';

  @override
  String get expiredLabel => 'Expired';

  @override
  String get overdueLabel => 'Overdue';

  @override
  String get dueTodayLabel => 'Due today';

  @override
  String get paidLabel => 'Paid';

  @override
  String get skippedLabel => 'Skipped';

  @override
  String get kindDeposit => 'Money in';

  @override
  String get kindWithdrawal => 'Money out';

  @override
  String get kindTransfer => 'Transfer';

  @override
  String get kindAdjustmentIncrease => 'Correction up';

  @override
  String get kindAdjustmentDecrease => 'Correction down';

  @override
  String get subtypeGrocery => 'Groceries';

  @override
  String get subtypeHousehold => 'Household';

  @override
  String get subtypeElectronics => 'Electronics';

  @override
  String get subtypeBill => 'Bill';

  @override
  String get subtypeTransferSelf => 'Between my accounts';

  @override
  String get subtypeTransferOut => 'Sent to someone';

  @override
  String get subtypeSalaryIn => 'Salary';

  @override
  String get subtypeOtherIn => 'Other income';

  @override
  String get subtypeOtherOut => 'Other spending';

  @override
  String needsReviewBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count transactions need details',
      one: '1 transaction needs details',
    );
    return '$_temp0';
  }

  @override
  String get needsReviewAction => 'Review';

  @override
  String get filterTitle => 'Filter';

  @override
  String get filterDateRange => 'Date range';

  @override
  String get filterKind => 'Type';

  @override
  String get filterSubtype => 'Category';

  @override
  String get filterApply => 'Show results';

  @override
  String get filterReset => 'Reset';

  @override
  String filterChipAccount(String name) {
    return 'Account: $name';
  }

  @override
  String filterChipPayee(String name) {
    return 'Payee: $name';
  }

  @override
  String filterChipRange(String label) {
    return '$label';
  }

  @override
  String get rangeToday => 'Today';

  @override
  String get rangeLast7Days => 'Last 7 days';

  @override
  String get rangeLast30Days => 'Last 30 days';

  @override
  String get rangeThisMonth => 'This month';

  @override
  String get rangeLastMonth => 'Last month';

  @override
  String get rangeThisYear => 'This year';

  @override
  String get rangeAllTime => 'All time';

  @override
  String get rangeCustom => 'Custom';

  @override
  String get searchTransactionsHint => 'Search notes';

  @override
  String get transactionDeleted => 'Transaction deleted';

  @override
  String get quickAddTitle => 'Quick add';

  @override
  String get quickAddMoneyIn => 'Money in';

  @override
  String get quickAddMoneyOut => 'Money out';

  @override
  String get quickAddSave => 'Save';

  @override
  String get actionAddDetails => 'Add details';

  @override
  String get editorTitleNew => 'New transaction';

  @override
  String get editorTitleEdit => 'Edit transaction';

  @override
  String get sectionWhatAndHowMuch => 'What and how much';

  @override
  String get sectionWhereItCameFrom => 'Where it came from';

  @override
  String get sectionWhereItWent => 'Where it went';

  @override
  String get sectionWhatYouBought => 'What you bought';

  @override
  String get sectionWarranty => 'Warranty';

  @override
  String get sectionSchedule => 'Schedule';

  @override
  String get transferOwnAccount => 'To my own account';

  @override
  String get transferSomeoneElse => 'To someone else';

  @override
  String get transferOwnAccountHelp =>
      'Moves money between your accounts. Your total does not change.';

  @override
  String get transferSomeoneElseHelp =>
      'Money leaves your accounts. This is a withdrawal.';

  @override
  String get alsoAddToInventory => 'Also add to inventory';

  @override
  String get destinationNone => 'Just an expense';

  @override
  String get destinationInventory => 'Save to Inventory';

  @override
  String get destinationAsset => 'Save to Services';

  @override
  String get destinationRecurring => 'Save to Recurring';

  @override
  String get lineAdd => 'Add item';

  @override
  String get lineDescription => 'Item';

  @override
  String get lineUnitPrice => 'Unit price';

  @override
  String get lineAmount => 'Line total';

  @override
  String lineCreatedLink(String name) {
    return 'Created: $name';
  }

  @override
  String payeeCreate(String name) {
    return 'New payee “$name”';
  }

  @override
  String get saveExpense => 'Save expense';

  @override
  String get saveIncome => 'Save income';

  @override
  String get saveTransfer => 'Save transfer';

  @override
  String get detailSectionLines => 'Items';

  @override
  String get detailSectionDetails => 'Details';

  @override
  String get actionFreezeConversion => 'Show in another currency';

  @override
  String frozenConversionNote(String date, String rate) {
    return 'Frozen on $date at $rate';
  }

  @override
  String get deleteReasonHint => 'Why? (optional)';

  @override
  String get actionDeleteTransaction => 'Delete transaction';

  @override
  String get labelSubtype => 'Category';

  @override
  String get labelKind => 'Type';

  @override
  String get themeLabTitle => 'Theme Lab';

  @override
  String get themeLabSubtitle =>
      'Every token, component and semantic colour, light and dark.';

  @override
  String get themeLabSectionSpacing => 'Spacing';

  @override
  String get themeLabSectionRadii => 'Radii';

  @override
  String get themeLabSectionTypography => 'Typography';

  @override
  String get themeLabSectionElevation => 'Elevation';

  @override
  String get themeLabSectionSemantic => 'Semantic colours';

  @override
  String get themeLabSectionSurfaces => 'Surface tiers';

  @override
  String get themeLabSectionComponents => 'Components';

  @override
  String get themeLabSectionPalettes => 'Palettes';

  @override
  String get themeLabLight => 'Light';

  @override
  String get themeLabDark => 'Dark';

  @override
  String get semanticIncome => 'Income';

  @override
  String get semanticExpense => 'Expense';

  @override
  String get semanticTransfer => 'Transfer';

  @override
  String get semanticWarning => 'Warning';

  @override
  String get semanticDanger => 'Danger';

  @override
  String get semanticSuccess => 'Success';

  @override
  String get semanticMuted => 'Muted';

  @override
  String get drawerSectionMoney => 'Money';

  @override
  String get drawerSectionHome => 'Home';

  @override
  String get drawerSectionMore => 'More';

  @override
  String get inventoryGroupFavourites => 'Favourites';

  @override
  String get inventoryGroupUntagged => 'Everything else';

  @override
  String get itemKindGeneric => 'General';

  @override
  String get itemKindFood => 'Food';

  @override
  String get itemKindMedicine => 'Medicine';

  @override
  String get itemKindBeauty => 'Beauty';

  @override
  String get itemKindHousehold => 'Household';

  @override
  String get itemKindOther => 'Other';

  @override
  String get filterFavouritesOnly => 'Favourites only';

  @override
  String get actionFavourite => 'Add to favourites';

  @override
  String get actionUnfavourite => 'Remove from favourites';

  @override
  String get outOfStockLabel => 'Out of stock';

  @override
  String itemBatchCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count batches',
      one: '1 batch',
    );
    return '$_temp0';
  }

  @override
  String get loadingInventory => 'Loading inventory';

  @override
  String get detailSectionBatches => 'Batches';

  @override
  String get batchOriginPurchase => 'From a purchase';

  @override
  String get batchOriginManual => 'Added by hand';

  @override
  String get batchOriginImported => 'Imported';

  @override
  String get batchOriginAdjustment => 'From an adjustment';

  @override
  String get labelPurchased => 'Purchased';

  @override
  String get labelStorageLocation => 'Stored in';

  @override
  String get labelUnitCost => 'Unit cost';

  @override
  String get labelInitial => 'Bought';

  @override
  String get labelNearestExpiry => 'Nearest expiry';

  @override
  String get labelDisplayUnit => 'Shown in';

  @override
  String get labelItemKind => 'Kind';

  @override
  String get labelLowStockThreshold => 'Low-stock level';

  @override
  String get labelExpiryNotifyDays => 'Warn before expiry';

  @override
  String get actionConsume => 'Use some';

  @override
  String get actionAddBatch => 'Add a batch';

  @override
  String get actionViewHistory => 'Movement history';

  @override
  String get actionDeleteItem => 'Delete item';

  @override
  String get confirmDeleteItemTitle => 'Delete this item?';

  @override
  String confirmDeleteItemBody(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count batches',
      one: '1 batch',
    );
    return 'Its $_temp0 go with it. The movement history stays, so what you already used is still recorded.';
  }

  @override
  String get itemDeleted => 'Item deleted';

  @override
  String expiresInDays(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Expires in $days days',
      one: 'Expires tomorrow',
      zero: 'Expires today',
    );
    return '$_temp0';
  }

  @override
  String expiredDaysAgo(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Expired $days days ago',
      one: 'Expired yesterday',
    );
    return '$_temp0';
  }

  @override
  String get sectionWhatItIs => 'What it is';

  @override
  String get sectionStockRules => 'Stock rules';

  @override
  String get unitCategoryWeight => 'Weight';

  @override
  String get unitCategoryVolume => 'Volume';

  @override
  String get unitCategoryCount => 'Count';

  @override
  String unitCategoryLocked(Object category) {
    return 'Measured in $category';
  }

  @override
  String get unitCategoryLockedHelp =>
      'This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.';

  @override
  String get expiryNotifyDaysHelp => 'Days of warning before a batch expires.';

  @override
  String get labelFavourite => 'Favourite';

  @override
  String get saveItem => 'Save item';

  @override
  String get sectionHowMuch => 'How much';

  @override
  String get sectionBatchDetails => 'Batch details';

  @override
  String get saveBatch => 'Save batch';

  @override
  String get batchSaved => 'Batch saved';

  @override
  String get hintStorageLocation => 'Freezer, pantry, bathroom shelf…';

  @override
  String get consumeTitle => 'Use stock';

  @override
  String get consumeKindConsume => 'Used';

  @override
  String get consumeKindWaste => 'Thrown away';

  @override
  String get consumeKindExpired => 'Expired';

  @override
  String get consumeRecorded => 'Recorded';

  @override
  String get consumeFromLabel => 'Taking from';

  @override
  String get consumeFefoNote => 'Oldest expiry first.';

  @override
  String consumeSpansBatches(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spans $count batches, writing $count movements',
      one: 'Takes all of 1 batch',
    );
    return '$_temp0';
  }

  @override
  String get consumeOverAvailable => 'More than you have on hand';

  @override
  String get historyTitle => 'Movement history';

  @override
  String get movementKindOpeningIn => 'Opening stock';

  @override
  String get movementKindPurchaseIn => 'Bought';

  @override
  String get movementKindManualIn => 'Added by hand';

  @override
  String get movementKindConsume => 'Used';

  @override
  String get movementKindWaste => 'Thrown away';

  @override
  String get movementKindExpired => 'Expired';

  @override
  String get movementKindAdjustIn => 'Adjusted up';

  @override
  String get movementKindAdjustOut => 'Adjusted down';

  @override
  String get movementReversed => 'Reversed';

  @override
  String get movementIsReversal => 'Reverses an earlier movement';

  @override
  String get actionReverse => 'Reverse';

  @override
  String get confirmReverseTitle => 'Reverse this movement?';

  @override
  String get confirmReverseBody =>
      'An opposite movement is appended. Nothing is erased — both entries stay in the history.';

  @override
  String get movementReversedSnack => 'Movement reversed';

  @override
  String get emptyTitleNoMovements => 'Nothing recorded yet';

  @override
  String get emptyBodyNoMovements =>
      'Using, wasting or adjusting this batch will show up here.';

  @override
  String get emptyBodyNoBatches =>
      'Add a batch and it will appear here with its expiry.';

  @override
  String get batchQuantityLockedHelp =>
      'How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.';

  @override
  String daysCount(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get groupByFavourites => 'Group favourites first';

  @override
  String get consumeCommitUsed => 'Record as used';

  @override
  String get consumeCommitWaste => 'Record as thrown away';

  @override
  String get consumeCommitExpired => 'Record as expired';

  @override
  String lowStockWithCount(Object count) {
    return 'Low · $count';
  }

  @override
  String get actionDeleteBatch => 'Delete batch';

  @override
  String get confirmDeleteBatchTitle => 'Delete this batch?';

  @override
  String get confirmDeleteBatchBody =>
      'The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.';

  @override
  String get batchDeleted => 'Batch deleted';

  @override
  String get itemCreate => 'New item';

  @override
  String get itemCreateHint =>
      'No items yet — create one so this line becomes stock.';

  @override
  String get itemCreateCategoryPrompt =>
      'How is it measured? This cannot change later.';

  @override
  String get itemDuplicateBody =>
      'You already have this item, measured the same way. Open the one you have instead of adding a second.';

  @override
  String get itemUnitsMissingBody =>
      'No units are set up for this measure yet. Pick a different measure, or add units in Settings first.';

  @override
  String get itemSimilarNote =>
      'You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.';

  @override
  String get actionOpenExisting => 'Open the one I have';

  @override
  String get shoppingEstimate => 'Estimated';

  @override
  String get shoppingSwitchList => 'Switch list';

  @override
  String shoppingCheckedCount(Object checked, Object total) {
    return '$checked of $total ticked';
  }

  @override
  String get emptyTitleNoEntries => 'Nothing on this list yet';

  @override
  String get emptyBodyNoEntries =>
      'Add what you need, or pull in suggestions from what is running low.';

  @override
  String get addEntry => 'Add';

  @override
  String get shoppingGroupUntagged => 'Everything else';

  @override
  String get actionUncheckAll => 'Untick everything';

  @override
  String get entryEditorTitle => 'What do you need?';

  @override
  String get entryFreeTextLabel => 'Name it';

  @override
  String get entryFreeTextHint => 'Television, birthday card, light bulbs…';

  @override
  String get entryLinkItem => 'Link to an item';

  @override
  String get entryNoItem => 'Not in my inventory';

  @override
  String get labelEstimatedPrice => 'Estimated price';

  @override
  String get entryNeedsSomething => 'Give it a name, or link it to an item';

  @override
  String get originAutoLowStock => 'Suggested';

  @override
  String get originPromoted => 'Yours now';

  @override
  String get actionSnooze => 'Snooze a week';

  @override
  String get actionDismiss => 'Not now';

  @override
  String get snoozedUntilLabel => 'Snoozed until';

  @override
  String get generateTitle => 'Running low';

  @override
  String get generateBody =>
      'These are below the level you set. Add the ones you want.';

  @override
  String get generateShortBy => 'Short by';

  @override
  String get generateRefresh => 'Check again';

  @override
  String get generateEmptyTitle => 'Nothing is running low';

  @override
  String get generateEmptyBody =>
      'Set a low-stock level on an item and it will show up here when it drops.';

  @override
  String generateAdded(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suggestions added',
      one: '1 suggestion added',
    );
    return '$_temp0';
  }

  @override
  String get convertTitle => 'Turn into a purchase';

  @override
  String get convertBody =>
      'Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.';

  @override
  String get convertConfirm => 'Open the expense';

  @override
  String get convertNothingTitle => 'Nothing is ticked';

  @override
  String get convertNothingBody =>
      'Tick what you actually bought, then come back.';

  @override
  String convertLineCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines',
      one: '1 line',
    );
    return '$_temp0';
  }

  @override
  String get listManagerTitle => 'Your lists';

  @override
  String get listNameLabel => 'List name';

  @override
  String get listCreate => 'New list';

  @override
  String get listRename => 'Rename';

  @override
  String get listSetDefault => 'Make default';

  @override
  String get listDefaultBadge => 'Default';

  @override
  String get listArchive => 'Archive';

  @override
  String get listUnarchive => 'Restore';

  @override
  String get listArchivedBadge => 'Archived';

  @override
  String get listArchivedSection => 'Archived';

  @override
  String get emptyTitleNoLists => 'No lists yet';

  @override
  String get emptyBodyNoLists => 'Create one and it becomes your default.';

  @override
  String get loadingShopping => 'Loading your list';

  @override
  String get actionAddToList => 'Add to my list';

  @override
  String get suggestionDismissed => 'Turned down';

  @override
  String get lineItemsTitle => 'What you bought';

  @override
  String get lineItemsManage => 'Add or edit items';

  @override
  String get lineItemsAdd => 'Add an item';

  @override
  String get lineItemsSaveAndAnother => 'Save & add another';

  @override
  String lineItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'No items yet',
    );
    return '$_temp0';
  }

  @override
  String get emptyTitleNoLineItems => 'Nothing itemised yet';

  @override
  String get emptyBodyNoLineItems =>
      'Add what was on the receipt. Anything you leave out still counts toward the total.';

  @override
  String get actionRemove => 'Remove';

  @override
  String get lineRemoved => 'Item removed';

  @override
  String get lineItemsAllocated => 'Itemised';

  @override
  String get recurringOutflow => 'Going out';

  @override
  String get recurringInflow => 'Coming in';

  @override
  String get recurringNextDue => 'Next';

  @override
  String get recurringOverdue => 'Overdue';

  @override
  String get recurringPaused => 'Paused';

  @override
  String get recurringDueToday => 'Due today';

  @override
  String get emptyTitleNoTemplates => 'Nothing recurring yet';

  @override
  String get emptyBodyNoTemplates =>
      'Add a bill, a subscription or a salary and it will appear here when it is next due.';

  @override
  String get addTemplate => 'Add';

  @override
  String get actionPause => 'Pause';

  @override
  String get actionResume => 'Resume';

  @override
  String get loadingRecurring => 'Loading your schedule';

  @override
  String get builderSectionWhat => 'What it is';

  @override
  String get builderSectionWhen => 'How often';

  @override
  String get builderSectionDefaults => 'Defaults';

  @override
  String get labelTemplateName => 'Name';

  @override
  String get labelRecurringKind => 'Kind';

  @override
  String get labelDirection => 'Direction';

  @override
  String get directionOutflow => 'Money out';

  @override
  String get directionInflow => 'Money in';

  @override
  String get kindBill => 'Bill';

  @override
  String get kindSubscription => 'Subscription';

  @override
  String get kindRent => 'Rent';

  @override
  String get kindSalary => 'Salary';

  @override
  String get labelEvery => 'Every';

  @override
  String unitDay(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'days',
      one: 'day',
    );
    return '$_temp0';
  }

  @override
  String unitWeek(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'weeks',
      one: 'week',
    );
    return '$_temp0';
  }

  @override
  String unitMonth(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'months',
      one: 'month',
    );
    return '$_temp0';
  }

  @override
  String unitYear(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'years',
      one: 'year',
    );
    return '$_temp0';
  }

  @override
  String get labelAnchorDay => 'On day of the month';

  @override
  String get anchorDayHelp =>
      'Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.';

  @override
  String get labelStartDate => 'Starts';

  @override
  String get labelEndDate => 'Ends';

  @override
  String get labelDefaultAmount => 'Usual amount';

  @override
  String get labelRemindBefore => 'Remind me';

  @override
  String get saveTemplate => 'Save';

  @override
  String get previewTitle => 'Next three';

  @override
  String get previewEmpty => 'Set a start date to see when this lands.';

  @override
  String get previewClamped => 'Shortened to fit the month';

  @override
  String get payTitle => 'Record this payment';

  @override
  String get payTitleInflow => 'Record this receipt';

  @override
  String get labelActualAmount => 'Amount actually paid';

  @override
  String get labelActualAmountInflow => 'Amount actually received';

  @override
  String get payUsualWas => 'Usually';

  @override
  String get labelPaidOn => 'Paid on';

  @override
  String get payCommit => 'Record it';

  @override
  String get payRecorded => 'Recorded';

  @override
  String get payNeedsAccount => 'Choose which account it came from';

  @override
  String get payUndoTitle => 'Undo this payment?';

  @override
  String get payUndoBody =>
      'The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.';

  @override
  String get payUndone => 'Payment undone';

  @override
  String get actionSkip => 'Skip this one';

  @override
  String get occurrenceSkipped => 'Skipped';

  @override
  String get historyRecurringTitle => 'Payment history';

  @override
  String get historyDefaultVsActual => 'Differed from the usual amount';

  @override
  String get emptyTitleNoOccurrences => 'Nothing due yet';

  @override
  String get emptyBodyNoOccurrences =>
      'Occurrences appear as their due dates arrive. Nothing is ever paid for you.';

  @override
  String get statusDue => 'Due';

  @override
  String get statusPaid => 'Paid';

  @override
  String get statusDismissed => 'Dismissed';

  @override
  String get kindServiceFee => 'Service fee';

  @override
  String get kindOther => 'Something else';

  @override
  String get billDueSection => 'Due now';

  @override
  String get billSetUpAction => 'Set up a recurring bill';

  @override
  String get billNothingDue => 'Nothing is due right now.';

  @override
  String get recurringScheduleNext => 'Saved. Now set how often it repeats.';

  @override
  String get recurringNotYetDue => 'Not due yet';

  @override
  String get billSettlesLabel => 'Settling';

  @override
  String get billSettleNone => 'Not a recurring bill';

  @override
  String get billSettleHelp =>
      'Pick one and the amount below becomes what you actually paid. Saving records it once.';

  @override
  String get billAmountBecomesPaid => 'This amount is what gets recorded';

  @override
  String get billAccountAuto => 'Paid from';

  @override
  String get billAccountAskOnce =>
      'Which account does this come from? Alaya remembers it on the bill.';

  @override
  String get assetGroupAppliance => 'Appliances';

  @override
  String get assetGroupElectronics => 'Electronics';

  @override
  String get assetGroupVehicle => 'Vehicles';

  @override
  String get assetGroupFurniture => 'Furniture';

  @override
  String get assetGroupProperty => 'Property';

  @override
  String get assetGroupServiceProvider => 'People';

  @override
  String get assetGroupSubscription => 'Subscriptions';

  @override
  String get assetGroupOther => 'Other';

  @override
  String get assetUnderWarranty => 'In warranty';

  @override
  String get assetWarrantyEnding => 'Warranty ending';

  @override
  String get assetWarrantyExpired => 'Out of warranty';

  @override
  String get assetServiceDue => 'Service due';

  @override
  String get assetServiceSoon => 'Service soon';

  @override
  String get assetDisposedChip => 'Disposed';

  @override
  String get assetUnderRepair => 'Being repaired';

  @override
  String get filterShowDisposed => 'Include disposed';

  @override
  String get emptyTitleNoAssets => 'Nothing tracked yet';

  @override
  String get emptyBodyNoAssets =>
      'Add an appliance, a vehicle, or the person who helps around the house — they all live here.';

  @override
  String get addAsset => 'Add';

  @override
  String get loadingAssets => 'Loading your things';

  @override
  String get assetSectionIdentity => 'Details';

  @override
  String get assetSectionWarranty => 'Warranty';

  @override
  String get assetSectionContact => 'Contact';

  @override
  String get assetSectionService => 'Service history';

  @override
  String get assetSectionSalary => 'Salary history';

  @override
  String get assetLifetimeCost => 'Spent on service so far';

  @override
  String get assetLifetimeSalary => 'Paid so far';

  @override
  String get labelBrand => 'Brand';

  @override
  String get labelModelNo => 'Model';

  @override
  String get labelSerialNo => 'Serial';

  @override
  String get labelPurchasePrice => 'Bought for';

  @override
  String get labelWarrantyStart => 'Warranty from';

  @override
  String get labelWarrantyEnd => 'Warranty until';

  @override
  String get labelWarrantyProvider => 'Covered by';

  @override
  String get labelServiceInterval => 'Service every';

  @override
  String get labelNextService => 'Next service';

  @override
  String get labelContactName => 'Name';

  @override
  String get labelContactPhone => 'Phone';

  @override
  String get labelLocation => 'Kept in';

  @override
  String get actionCall => 'Call';

  @override
  String get callFailed => 'No app on this phone can place that call.';

  @override
  String get actionAddService => 'Record a service';

  @override
  String get actionAddSalary => 'Record a payment';

  @override
  String get actionDispose => 'Dispose of it';

  @override
  String get actionUndispose => 'Bring it back';

  @override
  String get assetLinkedRecurring => 'Paid on a schedule';

  @override
  String get emptyBodyNoServices => 'Nothing recorded against this yet.';

  @override
  String get labelAssetName => 'What is it?';

  @override
  String get labelAssetType => 'Kind';

  @override
  String get assetTypeHelpPerson =>
      'A person you pay regularly belongs here too — their payments become service records.';

  @override
  String get saveAsset => 'Save';

  @override
  String get serviceIntervalHelp =>
      'Days between services. The next due date moves on each time you record one.';

  @override
  String get labelServiceType => 'What happened';

  @override
  String get serviceTypeService => 'Serviced';

  @override
  String get serviceTypeRepair => 'Repaired';

  @override
  String get serviceTypeMaintenance => 'Maintenance';

  @override
  String get serviceTypeInspection => 'Inspection';

  @override
  String get serviceTypeSalaryPaid => 'Salary paid';

  @override
  String get serviceTypeOther => 'Something else';

  @override
  String get labelProviderName => 'Who did it';

  @override
  String get labelProviderPhone => 'Their number';

  @override
  String get labelServiceDate => 'When';

  @override
  String get labelServiceCost => 'Cost';

  @override
  String get labelNextDue => 'Next one due';

  @override
  String get alsoRecordAsExpense => 'Also record it as an expense';

  @override
  String get alsoRecordHelp =>
      'Writes a withdrawal for the cost as well, so it shows in your ledger.';

  @override
  String get alsoRecordNeedsAccount => 'Choose which account it comes from';

  @override
  String get alsoRecordNeedsCost => 'Add a cost first';

  @override
  String get saveService => 'Save';

  @override
  String get disposeTitle => 'What happened to it?';

  @override
  String get disposeBody =>
      'It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.';

  @override
  String get disposeReasonSold => 'Sold it';

  @override
  String get disposeReasonExpired => 'Wore out';

  @override
  String get disposeReasonDamaged => 'Broke';

  @override
  String get disposeReasonGifted => 'Gave it away';

  @override
  String get disposeReasonLost => 'Lost it';

  @override
  String get disposeReasonReplaced => 'Replaced it';

  @override
  String get disposeReasonOther => 'Something else';

  @override
  String get labelDisposalAmount => 'Got back';

  @override
  String get labelDisposalDate => 'When';

  @override
  String get disposeCommit => 'Record it';

  @override
  String get disposeDone => 'Recorded';

  @override
  String get undisposeDone => 'Back in your list';

  @override
  String get disposeNeedsReason => 'Pick what happened';

  @override
  String get hintSearchAssets => 'Search your things and people';

  @override
  String get errorWarrantyBackwards =>
      'The warranty cannot end before it starts';

  @override
  String get sectionMoney => 'Money';

  @override
  String get assetCreatedFromPurchase =>
      'Saved. Now say what it is and how long it is covered.';

  @override
  String get destinationHelpNone => 'Recorded as spending and nothing else.';

  @override
  String get destinationHelpInventory =>
      'Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.';

  @override
  String get destinationHelpAsset =>
      'A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.';

  @override
  String get destinationHelpRecurring =>
      'Sets up a schedule so this comes back every month.';

  @override
  String get assetSameNameNote =>
      'You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.';

  @override
  String get actionSetWarranty => 'Set the warranty';

  @override
  String get labelPaymentMethodOptional => 'How you paid (optional)';

  @override
  String get dashboardTitle => 'Home';

  @override
  String get fundsAvailable => 'Total available funds';

  @override
  String fundsUnconverted(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count balances not converted',
      one: '1 balance not converted',
    );
    return '$_temp0';
  }

  @override
  String get fundsApproximate => 'Rate is older than today';

  @override
  String get fundsWhyExcluded =>
      'Balances Alaya has no rate for are left out rather than guessed at.';

  @override
  String get rangeLast30 => 'Last 30 days';

  @override
  String get rangeMoneyIn => 'In';

  @override
  String get rangeMoneyOut => 'Out';

  @override
  String get rangeNothingYet => 'Nothing yet';

  @override
  String rangeExcluded(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count left out',
      one: '1 left out',
    );
    return '$_temp0';
  }

  @override
  String get insightUpcoming => 'Coming up';

  @override
  String get insightSpending => 'Where it went';

  @override
  String get insightSwitchLabel => 'Show';

  @override
  String get insightNothingUpcoming =>
      'Nothing needs attention in the next fortnight.';

  @override
  String get insightBillDue => 'Bill due';

  @override
  String get insightServiceDue => 'Service due';

  @override
  String get insightWarrantyEnding => 'Warranty ending';

  @override
  String get insightBatchExpiring => 'Expiring';

  @override
  String get moduleGridTitle => 'Where to next';

  @override
  String moduleExpenses(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count this month',
      one: '1 this month',
      zero: 'none this month',
    );
    return '$_temp0';
  }

  @override
  String moduleInventory(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count running low',
      one: '1 running low',
      zero: 'nothing tracked',
    );
    return '$_temp0';
  }

  @override
  String moduleShopping(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count to buy',
      one: '1 to buy',
      zero: 'list is clear',
    );
    return '$_temp0';
  }

  @override
  String moduleRecurring(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count due',
      one: '1 due',
      zero: 'all settled',
    );
    return '$_temp0';
  }

  @override
  String moduleServices(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count need attention',
      one: '1 needs attention',
      zero: 'nothing needs doing',
    );
    return '$_temp0';
  }

  @override
  String get fabAddIncome => 'Money in';

  @override
  String get fabAddItem => 'New item';

  @override
  String get loadingDashboard => 'Adding it up';

  @override
  String get fabOpenLabel => 'Add something';

  @override
  String get fabCloseLabel => 'Close';

  @override
  String get eventTypeTransaction => 'Transaction';

  @override
  String get eventTypeRecurringDue => 'Recurring bill';

  @override
  String get eventTypeBatchExpiry => 'Expiring';

  @override
  String get eventTypeWarrantyEnd => 'Warranty ending';

  @override
  String get eventTypeServiceDue => 'Service due';

  @override
  String get eventTypeShoppingTarget => 'Shopping target';

  @override
  String get calendarSeverityWarning => 'Needs attention';

  @override
  String get calendarSeverityDanger => 'Past its date';

  @override
  String get calendarLoadingDay => 'Loading this day…';

  @override
  String get calendarDayErrorTitle => 'Could not load this day';

  @override
  String get calendarDayEmptyTitle => 'Nothing on this day';

  @override
  String get calendarDayEmptyBody =>
      'No transactions, bills, expiries or services fall here.';

  @override
  String get calendarRetry => 'Try again';

  @override
  String get calendarLoadingMonth => 'Loading this month…';

  @override
  String get calendarErrorTitle => 'Could not load the calendar';

  @override
  String get calendarPreviousMonth => 'Previous month';

  @override
  String get calendarNextMonth => 'Next month';

  @override
  String get calendarOnDay => 'On this day';

  @override
  String get calendarRangeOn => 'Select a range';

  @override
  String get calendarRangeOff => 'Stop selecting a range';

  @override
  String calendarRangePickEnd(String start) {
    return 'From $start — tap another day to finish.';
  }

  @override
  String calendarInRange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get calendarRangeEmptyTitle => 'Nothing in these days';

  @override
  String get calendarRangeEmptyBody =>
      'No transactions, bills, expiries or services fall inside the range.';

  @override
  String get calendarBackToToday => 'Back to this month';

  @override
  String get calendarTotalOut => 'Spent';

  @override
  String get calendarTotalIn => 'Received';

  @override
  String get dashboardOpenCalendar => 'Open calendar';

  @override
  String dashboardCalendarSemantics(String month) {
    return '$month at a glance. Opens the calendar.';
  }

  @override
  String get navBackToDashboard => 'Back to dashboard';

  @override
  String get chartLoading => 'Working it out…';

  @override
  String chartApproximate(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figures are indicative',
      one: '1 figure is indicative',
    );
    return '$_temp0';
  }

  @override
  String chartUnconverted(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count amounts left out',
      one: '1 amount left out',
    );
    return '$_temp0';
  }

  @override
  String get analyticsTotalSpent => 'Spent';

  @override
  String get analyticsRangeLabel => 'Reporting window';

  @override
  String analyticsComparisonUp(Object percent) {
    return '$percent more than the window before';
  }

  @override
  String analyticsComparisonDown(Object percent) {
    return '$percent less than the window before';
  }

  @override
  String analyticsUnconvertedTotal(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count amounts need a rate',
      one: '1 amount needs a rate',
    );
    return '$_temp0';
  }

  @override
  String get analyticsInflationTitle => 'Your own inflation';

  @override
  String get analyticsInflationSubtitle =>
      'What one thing costs you, purchase by purchase';

  @override
  String analyticsInflationUp(Object percent) {
    return '$percent more than the first time in this window';
  }

  @override
  String analyticsInflationDown(Object percent) {
    return '$percent less than the first time in this window';
  }

  @override
  String get analyticsInflationSince => 'First bought';

  @override
  String get analyticsInflationEmpty =>
      'Buy something twice and its price trend appears here. Widen the window if you have.';

  @override
  String get analyticsSectionSpend => 'Where it went';

  @override
  String get analyticsSectionTime => 'Over time';

  @override
  String get analyticsSectionWhat => 'Who and what';

  @override
  String get analyticsSectionHome => 'Your home';

  @override
  String get analyticsSectionCommitments => 'Already committed';

  @override
  String get analyticsBySubtype => 'By kind';

  @override
  String get analyticsByTag => 'By tag';

  @override
  String get analyticsByTagNote =>
      'A purchase with two tags counts in both, so these add up to more than the total';

  @override
  String get analyticsByMethod => 'By payment method';

  @override
  String get analyticsConcentration => 'How concentrated';

  @override
  String analyticsTopShare(Object percent) {
    return '$percent of your spending sits in three kinds';
  }

  @override
  String analyticsGroceryShare(Object percent) {
    return 'Groceries are $percent of it';
  }

  @override
  String analyticsTagChildren(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags inside',
      one: '1 tag inside',
    );
    return '$_temp0';
  }

  @override
  String analyticsTagDirect(Object tag) {
    return '$tag on its own';
  }

  @override
  String get analyticsTagBack => 'Back to all tags';

  @override
  String get analyticsNothingSpent => 'Nothing spent in this window';

  @override
  String get analyticsNoTaggedSpend => 'Tag a purchase and it will appear here';

  @override
  String get analyticsNoMethodSpend =>
      'Record how you paid and it will appear here';

  @override
  String get analyticsIncomeVsExpense => 'In and out';

  @override
  String get analyticsNeedTwoMonths =>
      'Two months of records and the trend appears here';

  @override
  String get analyticsNetFlow => 'What you kept';

  @override
  String get analyticsNetFlowNote =>
      'Moving money between your own accounts does not count';

  @override
  String get analyticsNoFlow => 'Nothing moved in this window';

  @override
  String get analyticsBalanceTrend => 'Balance over time';

  @override
  String analyticsBalanceIn(Object account, Object currency) {
    return '$account, in $currency';
  }

  @override
  String get analyticsAccount => 'Account';

  @override
  String get analyticsNoBalanceMovement =>
      'No movement on this account in this window';

  @override
  String get analyticsHeatmap => 'When you spend';

  @override
  String get analyticsByWeekday => 'By day of week';

  @override
  String get analyticsByDayOfMonth => 'By date';

  @override
  String get analyticsTopPayees => 'Who you paid most';

  @override
  String get analyticsNoPayees => 'Name who you paid and they will appear here';

  @override
  String get analyticsTopItems => 'What cost you most';

  @override
  String get analyticsNoItemisedSpend =>
      'Itemise a purchase and it will appear here';

  @override
  String get analyticsTopByQuantity => 'What you buy most of';

  @override
  String get analyticsTopByQuantityNote =>
      'Grouped by measure, because weight and count cannot be compared';

  @override
  String get analyticsNoQuantities =>
      'Record how much you bought and it will appear here';

  @override
  String analyticsPurchaseCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count purchases',
      one: '1 purchase',
    );
    return '$_temp0';
  }

  @override
  String get analyticsDearest => 'The most you have paid';

  @override
  String get analyticsDearestItem => 'Item';

  @override
  String get analyticsDearestPrice => 'Unit price';

  @override
  String get analyticsDearestWhen => 'When';

  @override
  String get analyticsNoUnitPrices =>
      'Record a unit price and this appears here';

  @override
  String get analyticsAverageBasket => 'Your average shop';

  @override
  String get analyticsBasketValue => 'Average value';

  @override
  String get analyticsBasketLines => 'Average items';

  @override
  String get analyticsBasketCount => 'Shops counted';

  @override
  String get analyticsNoBaskets =>
      'Record a grocery shop and it will appear here';

  @override
  String get analyticsInventoryValue => 'What is on your shelves';

  @override
  String get analyticsInventoryValueNote =>
      'Right now, whatever window you have chosen';

  @override
  String analyticsBatchesValued(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count batches valued',
      one: '1 batch valued',
    );
    return '$_temp0';
  }

  @override
  String analyticsBatchesNoCost(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count batches have no cost',
      one: '1 batch has no cost',
    );
    return '$_temp0';
  }

  @override
  String get analyticsNoStockValue =>
      'Record what a batch cost and its value appears here';

  @override
  String get analyticsWaste => 'What you threw away';

  @override
  String get analyticsNoWaste => 'Nothing wasted in this window';

  @override
  String analyticsExpiring(int days) {
    return 'Expiring within $days days';
  }

  @override
  String get analyticsNothingExpiring => 'Nothing expires soon';

  @override
  String analyticsDaysLeft(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String get analyticsExpiredAlready => 'Past its date';

  @override
  String get analyticsLowStock => 'Running low';

  @override
  String get analyticsLowStockNote =>
      'A count for today, not a history: stock levels are not kept over time';

  @override
  String analyticsLowStockCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items below their threshold',
      one: '1 item below its threshold',
    );
    return '$_temp0';
  }

  @override
  String get analyticsAsOf => 'As of';

  @override
  String get analyticsNothingLow => 'Nothing is running low';

  @override
  String get analyticsCommitment => 'Every month, before anything else';

  @override
  String get analyticsCommitmentNote =>
      'Bills and subscriptions only. Income is not netted off';

  @override
  String analyticsCommitmentCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'from $count commitments',
      one: 'from 1 commitment',
    );
    return '$_temp0';
  }

  @override
  String get analyticsNoCommitments =>
      'Add a bill or subscription and it will appear here';

  @override
  String get analyticsRecurringSplit => 'Fixed against chosen';

  @override
  String get analyticsRecurring => 'Fixed';

  @override
  String get analyticsDiscretionary => 'Chosen';

  @override
  String analyticsRecurringShare(Object percent) {
    return '$percent of your spending was already committed';
  }

  @override
  String get analyticsServiceCost => 'What your things cost to keep';

  @override
  String analyticsServiceCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count visits',
      one: '1 visit',
    );
    return '$_temp0';
  }

  @override
  String get analyticsNoServiceCost =>
      'Record a service or repair and it will appear here';

  @override
  String get analyticsWarranty => 'Warranties';

  @override
  String get analyticsCovered => 'Covered';

  @override
  String get analyticsCoverageEnded => 'Cover ended';

  @override
  String get analyticsNoWarranties =>
      'Add a warranty date and it will appear here';

  @override
  String get analyticsEmptyTitle => 'Nothing to show for this window';

  @override
  String get analyticsEmptyBody =>
      'Widen the window above, or record something and it will appear here.';

  @override
  String get analyticsCacheClear => 'Recalculate everything';

  @override
  String get analyticsCacheClearing => 'Recalculating…';

  @override
  String get analyticsCacheExplain =>
      'Some figures are kept between visits so this screen opens quickly. Clear them if a number looks stale.';

  @override
  String get analyticsCacheCleared => 'Recalculated';

  @override
  String get analyticsCacheClearedSnack => 'Figures recalculated';

  @override
  String get analyticsCacheFailed => 'Could not clear the saved figures';

  @override
  String get analyticsDrillTitle => 'Behind this figure';

  @override
  String get analyticsDrillTotal => 'These come to';

  @override
  String get analyticsDrillLoading => 'Loading these transactions…';

  @override
  String get analyticsDrillEmptyTitle => 'Nothing here in this window';

  @override
  String get analyticsDrillEmptyBody =>
      'The window is set on the insights screen. Widen it and these may appear.';

  @override
  String get analyticsDrillUnknownTitle => 'This link does not point anywhere';

  @override
  String get analyticsDrillUnknownBody =>
      'Open insights and choose a figure to look behind.';

  @override
  String get analyticsOtherSlices => 'Everything else';

  @override
  String get analyticsTopThree => 'in three kinds';

  @override
  String get aboutHowItWorksHeader => 'How it works';

  @override
  String get aboutLicences => 'Open source licences';

  @override
  String get aboutLicencesHelp => 'The libraries Alaya is built on.';

  @override
  String get aboutOfflineBody =>
      'Everything is stored on this device. Alaya only reaches the internet to fetch exchange rates, once a day.';

  @override
  String get aboutStorageBody =>
      'Your data is not encrypted, and no copy of it exists anywhere else unless you make a backup yourself.';

  @override
  String get aboutTagline =>
      'A finance and home manager that works entirely on your phone.';

  @override
  String get accountCurrencyHeader => 'Currency';

  @override
  String get accountCurrencyLockedHelp =>
      'Fixed, because changing it would reinterpret every amount already recorded here.';

  @override
  String get accountCurrencyNewHelp =>
      'What this account holds. It cannot be changed once you start recording against it.';

  @override
  String get accountEditorEditTitle => 'Edit account';

  @override
  String get accountEditorSave => 'Save account';

  @override
  String get accountEditorTitle => 'New account';

  @override
  String get accountIncludeInNetWorth => 'Count in net worth';

  @override
  String get accountIncludeInNetWorthHelp =>
      'Off means the balance still shows here, but is left out of your total. Useful for an account you hold for someone else.';

  @override
  String get accountKindBank => 'Bank';

  @override
  String get accountKindCard => 'Card';

  @override
  String get accountKindCash => 'Cash';

  @override
  String get accountKindHeader => 'What kind?';

  @override
  String get accountKindOther => 'Other';

  @override
  String get accountKindWallet => 'Wallet';

  @override
  String get accountNameLabel => 'Name';

  @override
  String get accountOpeningBalanceLabel => 'Opening balance';

  @override
  String get accountOpeningDateLabel => 'True on';

  @override
  String get accountsAdd => 'Add an account';

  @override
  String get accountsArchive => 'Archive this account';

  @override
  String get accountsArchiveConfirmBody =>
      'It will stop appearing when you record anything. Its history stays, and you can restore it here at any time.';

  @override
  String get accountsArchiveConfirmTitle => 'Archive this account?';

  @override
  String get accountsArchiveHelp =>
      'An archived account keeps all its history. It just stops appearing when you record something.';

  @override
  String get accountsArchived => 'Account archived';

  @override
  String get accountsArchivedChip => 'Archived';

  @override
  String get accountsArchivedHeader => 'Archived';

  @override
  String get accountsEmptyBody => 'Add one so Alaya knows where your money is.';

  @override
  String get accountsEmptyTitle => 'No accounts yet';

  @override
  String get accountsExcludedChip => 'Not in net worth';

  @override
  String get accountsLoading => 'Loading your accounts…';

  @override
  String get accountsMissingBody =>
      'It may have been removed. Go back and pick another.';

  @override
  String get accountsMissingTitle => 'That account is not here';

  @override
  String get accountsRestore => 'Restore this account';

  @override
  String get accountsRestoreConfirmBody =>
      'It will appear again everywhere you choose an account.';

  @override
  String get accountsRestoreConfirmTitle => 'Restore this account?';

  @override
  String get accountsRestored => 'Account restored';

  @override
  String get accountsSaved => 'Account saved';

  @override
  String get actionBack => 'Back';

  @override
  String get actionContinue => 'Continue';

  @override
  String get appearanceModeDark => 'Always dark';

  @override
  String get appearanceModeHeader => 'Light or dark';

  @override
  String get appearanceModeLight => 'Always light';

  @override
  String get appearanceModeSystem => 'Match my phone';

  @override
  String get appearanceModeSystemHelp =>
      'Follows your phone’s light and dark setting.';

  @override
  String get appearancePaletteHeader => 'Colours';

  @override
  String get appearanceThemeLabHelp =>
      'See every colour, spacing and text style the app uses.';

  @override
  String get backupNotEncryptedWarning =>
      'This backup is not encrypted. Anyone who opens this file can read every transaction, balance and account name. Only share it somewhere you trust.';

  @override
  String get currenciesHomeLocked =>
      'Cannot be turned off — your totals are added up in this.';

  @override
  String get currenciesLoading => 'Loading currencies…';

  @override
  String get currenciesToggleFailed => 'That could not be changed';

  @override
  String get dataBackupHeader => 'Backup';

  @override
  String get dataExportBody =>
      'Sends a copy of your data to WhatsApp, Drive, or anywhere else you choose.';

  @override
  String get dataExportConfirmAction => 'Share it';

  @override
  String get dataExportConfirmTitle => 'Share a backup?';

  @override
  String get dataExportFailed => 'The backup could not be made';

  @override
  String get dataExportTitle => 'Share a backup';

  @override
  String get dataRestoreHeader => 'Restore';

  @override
  String get dataRestorePending => 'Coming in the next update.';

  @override
  String get dataRestoreTitle => 'Restore from a backup';

  @override
  String get lockBackspace => 'Delete last digit';

  @override
  String get lockBiometricFailed => 'Not recognised. Enter your PIN instead.';

  @override
  String get lockBiometricReason => 'Unlock Alaya';

  @override
  String get lockEraseFailed =>
      'The data could not be deleted. Your PIN is unchanged.';

  @override
  String get lockErasing => 'Deleting everything on this device…';

  @override
  String get lockForgotPin => 'I have forgotten my PIN';

  @override
  String get lockHonestBody =>
      'This PIN stops someone who picks up your unlocked phone from opening Alaya. It does not encrypt your data — anyone with access to the phone\'s files can still read them. Your phone\'s own lock screen is what protects the file itself.';

  @override
  String get lockThrottledWhy =>
      'The wait gets longer after each wrong attempt.';

  @override
  String get lockTitle => 'Enter your PIN';

  @override
  String get lockUseBiometric => 'Use fingerprint';

  @override
  String get lockWrongPin => 'That PIN is not right.';

  @override
  String get onboardingAccountsBody =>
      'Where do you keep your money? Add the ones you use.';

  @override
  String get onboardingAccountsTitle => 'Your accounts';

  @override
  String get onboardingAddAccount => 'Add an account';

  @override
  String get onboardingCurrencyBody =>
      'Which currency should Alaya add your totals up in?';

  @override
  String get onboardingCurrencyNote =>
      'This changes how totals are shown. It does not change any amount you have already recorded, and each account keeps its own currency.';

  @override
  String get onboardingCurrencyTitle => 'Your currency';

  @override
  String get onboardingFinish => 'Finish';

  @override
  String get onboardingLoading => 'Getting things ready…';

  @override
  String get onboardingLockOnBody =>
      'Alaya will ask for your PIN when you open it. You can change or remove it in Settings › Security.';

  @override
  String get onboardingLockOnHeader => 'Lock is on';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingNoAccountsBody =>
      'Add at least one so Alaya knows where your money is.';

  @override
  String get onboardingNoAccountsTitle => 'No accounts yet';

  @override
  String get onboardingOpeningNote =>
      'The opening balance is what was there on the date you give. Alaya needs both: a balance with no date cannot be placed in your ledger, and anything you record before that date would not be counted.';

  @override
  String get onboardingRemoveAccount => 'Remove this account';

  @override
  String get onboardingSaveAccounts => 'Save accounts';

  @override
  String get onboardingSecurityBody =>
      'You can put a PIN on Alaya. This is optional and you can add one later.';

  @override
  String get onboardingSecurityTitle => 'Lock the app?';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingSkipBody =>
      'You can change all of this later in Settings.';

  @override
  String get onboardingSkipTitle => 'Skip setting up?';

  @override
  String get onboardingTitle => 'Welcome to Alaya';

  @override
  String get payeeKindEmployer => 'Employer';

  @override
  String get payeeKindMerchant => 'Shop';

  @override
  String get payeeKindOther => 'Other';

  @override
  String get payeeKindPerson => 'Person';

  @override
  String get payeeKindUtility => 'Utility';

  @override
  String get payeeNameLabel => 'Name';

  @override
  String get payeePhoneOptionalLabel => 'Phone (optional)';

  @override
  String get payeesAdd => 'Add a payee';

  @override
  String get payeesDelete => 'Delete';

  @override
  String get payeesDeleteConfirmBody =>
      'Transactions that named them keep their record. They just stop being suggested.';

  @override
  String get payeesDeleteConfirmTitle => 'Delete this payee?';

  @override
  String get payeesDeleteFailed => 'That could not be deleted';

  @override
  String get payeesDeleted => 'Payee deleted';

  @override
  String get payeesEditTitle => 'Edit payee';

  @override
  String get payeesEmptyBody => 'These build up as you record who you paid.';

  @override
  String get payeesEmptyTitle => 'No payees yet';

  @override
  String get payeesLoading => 'Loading payees…';

  @override
  String get payeesNoMatchBody => 'Try part of the name.';

  @override
  String get payeesNoMatchTitle => 'No payees match that';

  @override
  String get payeesSave => 'Save payee';

  @override
  String get payeesSaveFailed => 'That could not be saved';

  @override
  String get payeesSaved => 'Payee saved';

  @override
  String get payeesSearchHint => 'Search payees';

  @override
  String get paymentKindBankTransfer => 'Bank transfer';

  @override
  String get paymentKindCard => 'Card';

  @override
  String get paymentKindCash => 'Cash';

  @override
  String get paymentKindCheque => 'Cheque';

  @override
  String get paymentKindOther => 'Other';

  @override
  String get paymentKindUpi => 'UPI';

  @override
  String get paymentKindWallet => 'Wallet';

  @override
  String get paymentMethodNameLabel => 'Name';

  @override
  String get paymentMethodsAdd => 'Add a payment method';

  @override
  String get paymentMethodsDelete => 'Delete';

  @override
  String get paymentMethodsDeleteConfirmBody =>
      'Transactions that used it keep their record of having done so. It just stops being offered.';

  @override
  String get paymentMethodsDeleteConfirmTitle => 'Delete this payment method?';

  @override
  String get paymentMethodsDeleteFailed => 'That could not be deleted';

  @override
  String get paymentMethodsDeleted => 'Payment method deleted';

  @override
  String get paymentMethodsEditTitle => 'Edit payment method';

  @override
  String get paymentMethodsEmptyBody =>
      'Add how you usually pay — cash, UPI, a card.';

  @override
  String get paymentMethodsEmptyTitle => 'No payment methods';

  @override
  String get paymentMethodsLoading => 'Loading payment methods…';

  @override
  String get paymentMethodsSave => 'Save payment method';

  @override
  String get paymentMethodsSaveFailed => 'That could not be saved';

  @override
  String get paymentMethodsSaved => 'Payment method saved';

  @override
  String get paymentMethodsSystemChip => 'Built in';

  @override
  String get pinSetupBackupBody =>
      'You have just put a lock on this app. A backup means a forgotten PIN never costs you your records.';

  @override
  String get pinSetupBackupHeader => 'Make a backup?';

  @override
  String get pinSetupBackupLater => 'Not now';

  @override
  String get pinSetupBackupNow => 'Back up now';

  @override
  String get pinSetupConfirmPrompt => 'Enter it again';

  @override
  String get pinSetupDone => 'Your PIN is set';

  @override
  String get pinSetupDoneBody =>
      'Alaya will ask for it when you open the app, and again after a minute in the background.';

  @override
  String get pinSetupEnterPrompt => 'Choose a PIN';

  @override
  String get pinSetupMismatch => 'Those did not match. Start again.';

  @override
  String get pinSetupRecoveryAck => 'I have saved this code somewhere safe';

  @override
  String get pinSetupRecoveryBody =>
      'This is the only way back in if you forget your PIN. It is shown once and cannot be shown again.';

  @override
  String get pinSetupRecoveryCopied => 'Recovery code copied';

  @override
  String get pinSetupRecoveryCopy => 'Copy code';

  @override
  String get pinSetupRecoveryHeader => 'Your recovery code';

  @override
  String get pinSetupRecoveryWhereToKeep =>
      'A password manager is a good place for it. A photo in your gallery is not.';

  @override
  String get pinSetupTitle => 'Set a PIN';

  @override
  String get recoveryCodeLabel => 'Recovery code';

  @override
  String get recoveryCodePrompt =>
      'Enter the recovery code you saved when you set your PIN.';

  @override
  String get recoveryDone => 'Your PIN has been changed';

  @override
  String get recoveryEraseEverything => 'Erase everything';

  @override
  String get recoveryExportFirst => 'Export a copy first';

  @override
  String get recoveryExported =>
      'A copy has been shared. Check it arrived before you erase.';

  @override
  String get recoveryForgotBoth => 'I do not have the recovery code either';

  @override
  String get recoveryForgotBothBody =>
      'Without your PIN or your recovery code there is no way back into this data. You can export a copy first, then erase everything and start again.';

  @override
  String get recoveryForgotBothTitle => 'Starting over';

  @override
  String get recoveryNewPinPrompt => 'Choose a new PIN';

  @override
  String get recoveryTitle => 'Forgotten PIN';

  @override
  String get securityAutoEraseConfirmAction => 'Turn it on';

  @override
  String get securityAutoEraseConfirmTitle =>
      'Turn on erase after repeated failures?';

  @override
  String get securityAutoEraseFailed => 'That could not be changed';

  @override
  String get securityAutoEraseHeader => 'If the PIN is entered wrongly';

  @override
  String get securityAutoEraseOff => 'Erase after repeated failures is off';

  @override
  String get securityAutoEraseOn => 'Erase after repeated failures is on';

  @override
  String get securityAutoEraseTitle =>
      'Erase everything after repeated failures';

  @override
  String get securityAutoLockHeader => 'Auto-lock';

  @override
  String get securityAutoLockTitle => 'Lock when I leave the app';

  @override
  String get securityChangePin => 'Change PIN';

  @override
  String get securityChecking => 'Checking…';

  @override
  String get securityPinHeader => 'PIN';

  @override
  String get securityRemovePin => 'Remove PIN';

  @override
  String get securityRemovePinConfirmBody =>
      'Anyone who picks up your unlocked phone will be able to open Alaya. You will be asked for your current PIN next.';

  @override
  String get securityRemovePinConfirmTitle => 'Remove the PIN?';

  @override
  String get securityRemovePinHelp =>
      'You will need your current PIN to do this.';

  @override
  String get securitySetPin => 'Set a PIN';

  @override
  String get securitySetPinHelp =>
      'Alaya will ask for it when you open the app.';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAccounts => 'Accounts';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsCurrencies => 'Currencies';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsGroupApp => 'The app';

  @override
  String get settingsGroupMoney => 'Your money';

  @override
  String get settingsGroupThings => 'Your things';

  @override
  String get settingsNoMatchBody =>
      'Try a different word — \"dark\", \"PIN\" and \"backup\" all find something.';

  @override
  String get settingsNoMatchTitle => 'Nothing matches that';

  @override
  String get settingsPayees => 'Payees';

  @override
  String get settingsPaymentMethods => 'Payment methods';

  @override
  String get settingsSearchHint => 'Search settings';

  @override
  String get settingsSecurity => 'Security';

  @override
  String get settingsTags => 'Tags';

  @override
  String get settingsUnits => 'Units';

  @override
  String get tagColourHeader => 'Colour';

  @override
  String get tagColourHelp =>
      'Optional. Kept as chosen, so it stays the same if you change the app’s palette later.';

  @override
  String get tagColourNone => 'No colour';

  @override
  String get tagColourSwatch => 'Use this colour';

  @override
  String get tagEditorEditTitle => 'Edit tag';

  @override
  String get tagEditorSave => 'Save tag';

  @override
  String get tagEditorTitle => 'New tag';

  @override
  String get tagNameLabel => 'Name';

  @override
  String get tagParentHeader => 'Group under';

  @override
  String get tagParentHelp =>
      'Optional. Grouping keeps long tag lists readable. Only one level deep.';

  @override
  String get tagParentNone => 'No group';

  @override
  String get tagScopeDeposit => 'Money in';

  @override
  String get tagScopeDepositHelp => 'Offered when you record money coming in.';

  @override
  String get tagScopeInventory => 'Items';

  @override
  String get tagScopeInventoryHelp => 'Offered on things you keep at home.';

  @override
  String get tagScopeRecurring => 'Recurring';

  @override
  String get tagScopeRecurringHelp => 'Offered on bills and subscriptions.';

  @override
  String get tagScopeService => 'Services';

  @override
  String get tagScopeServiceHelp =>
      'Offered on appliances and their service records.';

  @override
  String get tagScopeShopping => 'Shopping lists';

  @override
  String get tagScopeShoppingHelp =>
      'Used to group a shopping list under headings.';

  @override
  String get tagScopeWithdrawal => 'Money out';

  @override
  String get tagScopeWithdrawalHelp => 'Offered when you record spending.';

  @override
  String get tagScopesHeader => 'Where it appears';

  @override
  String get tagScopesHelp =>
      'A tag is only offered where you turn it on. This is what keeps \"Kitchen\" out of the list when you record your salary.';

  @override
  String get tagsAdd => 'Add a tag';

  @override
  String get tagsDelete => 'Delete this tag';

  @override
  String get tagsDeleteConfirmBody =>
      'Transactions and items already carrying it keep it in their history. It stops appearing when you tag something new.';

  @override
  String get tagsDeleteConfirmTitle => 'Delete this tag?';

  @override
  String get tagsDeleteHelp =>
      'Anything already tagged keeps its history. The tag just stops being offered.';

  @override
  String get tagsDeleted => 'Tag deleted';

  @override
  String get tagsEmptyBody =>
      'Tags let you group things across accounts — \"Kitchen\", \"Car\", \"Diwali\".';

  @override
  String get tagsEmptyTitle => 'No tags yet';

  @override
  String get tagsLoading => 'Loading tags…';

  @override
  String get tagsMissingBody =>
      'It may have been deleted. Go back and pick another.';

  @override
  String get tagsMissingTitle => 'That tag is not here';

  @override
  String get tagsNoScopesWarning =>
      'This tag is not offered anywhere. Turn on at least one place below, or it will never appear.';

  @override
  String get tagsSaved => 'Tag saved';

  @override
  String get tagsSystemChip => 'Built in';

  @override
  String get unitBaseGrams => 'grams';

  @override
  String get unitBaseMillilitres => 'millilitres';

  @override
  String get unitBasePieces => 'pieces';

  @override
  String get unitCategoryHeader => 'What does it measure?';

  @override
  String get unitCategoryNewHelp =>
      'Choose carefully: this cannot be changed later.';

  @override
  String get unitCodeHelp =>
      'What you will see beside a quantity — kg, ml, pc.';

  @override
  String get unitCodeLabel => 'Short code';

  @override
  String get unitCodeLockedHelp =>
      'Fixed once the unit exists, because other records point at it.';

  @override
  String get unitEditorEditTitle => 'Edit unit';

  @override
  String get unitEditorSave => 'Save unit';

  @override
  String get unitEditorTitle => 'New unit';

  @override
  String get unitFactorHeader => 'How big is it?';

  @override
  String get unitFactorMustBePositive => 'That has to be more than zero.';

  @override
  String get unitFactorThisUnit => 'this unit';

  @override
  String get unitFactorVaries => 'It varies — I cannot give one number';

  @override
  String get unitNameLabel => 'Name';

  @override
  String get unitVariesBack => 'Actually, I can give a number';

  @override
  String get unitVariesCreateItem => 'Create an item instead';

  @override
  String get unitVariesInsteadBody =>
      'Add \"Biscuit packet\" as its own item, counted in pieces. Then two packets is two of that item, and Alaya can price and track them properly.';

  @override
  String get unitVariesInsteadTitle => 'Make it an item instead';

  @override
  String get unitVariesTitle => 'Then it is not a unit';

  @override
  String get unitVariesWhy =>
      'A unit has to be the same amount every time. One packet of biscuits and one packet of rice are different weights, so Alaya could not add two packets together or work out what one cost.';

  @override
  String get unitsAdd => 'Add a unit';

  @override
  String get unitsCategoriesFixedNote =>
      'Weight, volume and count are the only three kinds there are. Alaya never converts between them, so a kilo can never become a litre by accident.';

  @override
  String get unitsDelete => 'Delete this unit';

  @override
  String get unitsDeleteConfirmBody =>
      'Anything already bought in this unit keeps its quantity, but that quantity would no longer be readable. Only delete a unit you have not used.';

  @override
  String get unitsDeleteConfirmTitle => 'Delete this unit?';

  @override
  String get unitsDeleteHelp =>
      'Only possible while nothing is measured in it.';

  @override
  String get unitsDeleted => 'Unit deleted';

  @override
  String get unitsEmptyBody =>
      'Alaya ships with the common ones. Add one if you measure something differently.';

  @override
  String get unitsEmptyTitle => 'No units';

  @override
  String get unitsLoading => 'Loading units…';

  @override
  String get unitsMissingBody =>
      'It may have been deleted. Go back and pick another.';

  @override
  String get unitsMissingTitle => 'That unit is not here';

  @override
  String get unitsSaved => 'Unit saved';

  @override
  String get unitsSystemChip => 'Built in';

  @override
  String currenciesRowSubtitle(String symbol, int digits) {
    String _temp0 = intl.Intl.pluralLogic(
      digits,
      locale: localeName,
      other: '$digits decimal places',
      one: '1 decimal place',
      zero: 'no decimal places',
    );
    return '$symbol · $_temp0';
  }

  @override
  String currenciesRowTitle(String code, String name) {
    return '$code · $name';
  }

  @override
  String dataExportDone(String fileName) {
    return 'Backup saved as $fileName';
  }

  @override
  String lockThrottled(String time) {
    return 'Too many attempts. Try again in $time';
  }

  @override
  String onboardingCurrencyChip(String code, String symbol) {
    return '$code $symbol';
  }

  @override
  String onboardingStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String pinSetupLength(int length) {
    return '$length digits';
  }

  @override
  String recoveryTypeToConfirm(String word) {
    return 'Type $word to confirm';
  }

  @override
  String securityAutoEraseBody(int count) {
    return 'When on, $count wrong PIN attempts in a row will delete everything on this device.';
  }

  @override
  String securityAutoEraseConfirmBody(int count) {
    return 'After $count failed attempts, every account, transaction and item on this device is deleted. There is no undo, and no copy unless you have made a backup.';
  }

  @override
  String securityAutoLockBody(int seconds) {
    return 'Locks again after $seconds seconds in the background.';
  }

  @override
  String settingsAccountCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count accounts',
      one: '1 account',
      zero: 'No accounts',
    );
    return '$_temp0';
  }

  @override
  String settingsCurrencyCount(int enabled, int total) {
    return '$enabled of $total enabled';
  }

  @override
  String settingsPayeeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payees',
      one: '1 payee',
      zero: 'No payees',
    );
    return '$_temp0';
  }

  @override
  String settingsPaymentMethodCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payment methods',
      one: '1 payment method',
      zero: 'No payment methods',
    );
    return '$_temp0';
  }

  @override
  String settingsTagCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags',
      one: '1 tag',
      zero: 'No tags',
    );
    return '$_temp0';
  }

  @override
  String settingsUnitCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count units',
      one: '1 unit',
      zero: 'No units',
    );
    return '$_temp0';
  }

  @override
  String unitFactorHelp(String base) {
    return 'One of this unit has to be the same number of $base every time.';
  }

  @override
  String unitFactorQuestion(String base, String unit) {
    return 'How many $base is one $unit?';
  }

  @override
  String unitsEquals(String code, String amount, String base) {
    return '1 $code = $amount $base';
  }

  @override
  String unitsRowTitle(String name, String code) {
    return '$name ($code)';
  }

  @override
  String get attachmentsAdd => 'Add an attachment';

  @override
  String get attachmentsAddFailed => 'That could not be attached';

  @override
  String get attachmentsAdded => 'Attached';

  @override
  String get attachmentsChoosePhoto => 'Choose a photo';

  @override
  String get attachmentsDelete => 'Remove';

  @override
  String get attachmentsDeleteConfirmBody =>
      'The file is deleted from this phone. Backups you have already made still contain it.';

  @override
  String get attachmentsDeleteConfirmTitle => 'Remove this attachment?';

  @override
  String get attachmentsDeleteFailed => 'That could not be removed';

  @override
  String get attachmentsDeleted => 'Attachment removed';

  @override
  String get attachmentsMissing => 'That file is missing from this phone.';

  @override
  String get attachmentsNone => 'Nothing attached';

  @override
  String get attachmentsOpen => 'Open attachment';

  @override
  String get attachmentsStoredLocally =>
      'Kept on this phone only, and included in your backups.';

  @override
  String get backupConfirmAction => 'Make the backup';

  @override
  String get backupConfirmTitle => 'Make a backup?';

  @override
  String get backupDone => 'Backup saved';

  @override
  String get backupFailed => 'The backup could not be made';

  @override
  String get backupForget => 'Forget';

  @override
  String get backupForgetConfirmBody =>
      'This removes it from the list only. The backup file itself stays wherever you put it — Alaya cannot reach into your Drive or your chats.';

  @override
  String get backupForgetConfirmTitle => 'Forget this entry?';

  @override
  String get backupForgetFailed => 'That entry could not be removed';

  @override
  String get backupForgotten => 'Entry removed';

  @override
  String get backupHistoryEmptyBody =>
      'Make one now, and keep it somewhere that is not this phone.';

  @override
  String get backupHistoryEmptyTitle => 'No backups yet';

  @override
  String get backupHistoryHeader => 'Backups you have made';

  @override
  String get backupHistoryLoading => 'Loading your backups…';

  @override
  String get backupMakeHeader => 'Make a backup';

  @override
  String get backupRestoreBody =>
      'Merge a backup into what you have, or replace everything with it.';

  @override
  String get backupRestoreHeader => 'Restore';

  @override
  String get backupRestoreTitle => 'Restore from a backup';

  @override
  String get backupSaveBody =>
      'Choose where to put it. Alaya needs no storage permission — you pick the folder.';

  @override
  String get backupSaveTitle => 'Save a copy';

  @override
  String get backupShareBody => 'Send it to WhatsApp, Drive, or anywhere else.';

  @override
  String get backupShareTitle => 'Share a copy';

  @override
  String get backupTitle => 'Backup';

  @override
  String get reminderKindExpiry => 'Things going off';

  @override
  String get reminderKindExpiryHelp =>
      'Food and medicine reaching their use-by date.';

  @override
  String get reminderKindLowStock => 'Running low';

  @override
  String get reminderKindLowStockHelp =>
      'Not offered as a reminder: being low on something has no date, so it would arrive every morning until you shopped.';

  @override
  String get reminderKindRecurring => 'Bills and subscriptions';

  @override
  String get reminderKindRecurringHelp => 'When a recurring payment falls due.';

  @override
  String get reminderKindService => 'Appliance servicing';

  @override
  String get reminderKindServiceHelp =>
      'When something is due for its next service.';

  @override
  String get reminderKindWarranty => 'Warranties ending';

  @override
  String get reminderKindWarrantyHelp =>
      'Before a warranty runs out, while you can still use it.';

  @override
  String get remindersBlocked =>
      'Notifications are turned off for Alaya. Turn them on in your phone’s Settings › Apps › Alaya › Notifications.';

  @override
  String get remindersDenied => 'Alaya needs permission to send notifications.';

  @override
  String get remindersDigestExplainer =>
      'Alaya sends one message a day about what is coming up — not a notification for every item.';

  @override
  String get remindersDigestRow => 'Daily summary';

  @override
  String get remindersKindsHeader => 'What to remind me about';

  @override
  String get remindersLoading => 'Loading your reminders…';

  @override
  String get remindersNoneScheduledBody =>
      'Turn on a reminder above and Alaya will show what it has planned here.';

  @override
  String get remindersNoneScheduledTitle => 'Nothing scheduled';

  @override
  String get remindersScheduledHeader => 'Currently scheduled';

  @override
  String get remindersTimeHeader => 'When';

  @override
  String get remindersTimeSaved => 'Reminder time changed';

  @override
  String get remindersTimeTitle => 'Daily summary time';

  @override
  String get remindersTitle => 'Reminders';

  @override
  String get remindersToggleFailed => 'That could not be changed';

  @override
  String get restoreApplyMerge => 'Merge the backup';

  @override
  String get restoreApplyReplace => 'Replace everything';

  @override
  String get restoreChooseAnother => 'Choose another file';

  @override
  String get restoreChooseFile => 'Choose a file';

  @override
  String get restoreChosenHeader => 'Chosen file';

  @override
  String get restoreContinueReplace => 'Continue to replace';

  @override
  String get restoreDone => 'Restored';

  @override
  String get restoreLockNotRestored =>
      'Your PIN is never restored. It is kept outside the backup, so opening someone else’s backup can never change who can open this app.';

  @override
  String get restoreMergeBody =>
      'Adds what the backup has and updates what is newer. Nothing you have now is lost.';

  @override
  String get restoreMergeTitle => 'Merge';

  @override
  String get restoreModeHeader => 'How should it be applied?';

  @override
  String get restoreNotADatabase => 'That file is not an Alaya backup.';

  @override
  String get restorePickBody =>
      'Choose a backup file. Alaya will check it before anything changes.';

  @override
  String get restoreReplaceBody =>
      'Throws away what is on this phone and uses the backup instead.';

  @override
  String get restoreReplaceTitle => 'Replace everything';

  @override
  String get restoreReplaceWarning =>
      'Everything currently on this phone will be thrown away and replaced by the backup. Anything recorded since that backup was made will be gone.';

  @override
  String get restoreRollbackAvailable =>
      'Restored the wrong file? You can put your previous data back.';

  @override
  String get restoreRollbackPromise =>
      'Alaya takes a snapshot of your current data first, so you can undo this straight afterwards.';

  @override
  String get restoreTitle => 'Restore';

  @override
  String get restoreUndo => 'Undo the replace';

  @override
  String get supportConsentUnavailable =>
      'Adverts need a choice about personalisation that could not be loaded right now. Nothing has been requested.';

  @override
  String get supportIntro =>
      'Alaya is free, works offline, and has no accounts to sign up for. If it is useful to you, there are two ways to help.';

  @override
  String get supportLoading => 'Loading…';

  @override
  String get supportNoAd => 'No advert available right now';

  @override
  String get supportNoPaidFeatures =>
      'Nothing here unlocks anything. There are no paid features — the whole app is already yours.';

  @override
  String get supportThanks => 'Thank you. That genuinely helps.';

  @override
  String get supportTipBody =>
      'A one-time thank-you through the Play Store. It is not a subscription.';

  @override
  String get supportTipHeader => 'Leave a tip';

  @override
  String get supportTipUnavailable =>
      'Tips are not available on this device right now.';

  @override
  String get supportTitle => 'Support Alaya';

  @override
  String get supportWatchAction => 'Watch an advert';

  @override
  String get supportWatchBody =>
      'One advert, when you choose to. Alaya never shows one anywhere else in the app.';

  @override
  String get supportWatchHeader => 'Watch a short advert';

  @override
  String get trashDeletedOn => 'Deleted';

  @override
  String get trashEmptyBody =>
      'Things you delete are kept here for 30 days before they go for good.';

  @override
  String get trashEmptyNow => 'Empty now';

  @override
  String get trashEmptyNowConfirmBody =>
      'Everything in the trash is deleted permanently. This is not the trash — there is nowhere left for it to go.';

  @override
  String get trashEmptyNowConfirmTitle => 'Empty the trash?';

  @override
  String get trashEmptyTitle => 'The trash is empty';

  @override
  String get trashGoesOn => '· kept for 30 days';

  @override
  String get trashKindAsset => 'Appliances';

  @override
  String get trashKindItem => 'Items';

  @override
  String get trashKindPayee => 'Payees';

  @override
  String get trashKindRecurring => 'Recurring';

  @override
  String get trashKindShoppingList => 'Shopping lists';

  @override
  String get trashKindTag => 'Tags';

  @override
  String get trashKindTransaction => 'Transactions';

  @override
  String get trashLoading => 'Loading the trash…';

  @override
  String get trashNoMatchBody => 'Remove a filter to see the rest.';

  @override
  String get trashNoMatchTitle => 'Nothing matches that filter';

  @override
  String get trashPurgeConfirmBody =>
      'It will not go back to the trash. There is no undo.';

  @override
  String get trashPurgeConfirmTitle => 'Delete this for good?';

  @override
  String get trashPurgeFailed => 'That could not be deleted';

  @override
  String get trashPurgeOne => 'Delete for good';

  @override
  String get trashPurgedOne => 'Deleted for good';

  @override
  String get trashRestore => 'Restore';

  @override
  String get trashRestoreFailed => 'That could not be restored';

  @override
  String get trashRestored => 'Restored';

  @override
  String get trashTitle => 'Trash';

  @override
  String backupDoneNamed(String fileName) {
    return 'Backup saved as $fileName';
  }

  @override
  String backupHistorySize(String size) {
    return '· $size';
  }

  @override
  String remindersTimeBody(String time) {
    return 'Sent at $time each day';
  }

  @override
  String restoreDoneDetail(int tables) {
    String _temp0 = intl.Intl.pluralLogic(
      tables,
      locale: localeName,
      other: '$tables tables restored',
      one: '1 table restored',
    );
    return '$_temp0';
  }

  @override
  String restoreNewerSchema(int backup, int app) {
    return 'That backup is from a newer version of Alaya (version $backup) than this app understands (version $app). Update Alaya and try again.';
  }

  @override
  String restoreTypeToConfirm(String word) {
    return 'Type $word to confirm';
  }

  @override
  String supportTipAction(String price) {
    return 'Leave a tip · $price';
  }

  @override
  String trashPurged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items deleted for good',
      one: '1 item deleted for good',
      zero: 'Nothing to delete',
    );
    return '$_temp0';
  }

  @override
  String get dataBackupRowBody => 'Save a copy, share it, or restore from one.';

  @override
  String get dataTrashRowBody => 'Things you delete are kept here for 30 days.';

  @override
  String get settingsRemindersHelp => 'One daily summary of what is coming up.';

  @override
  String get settingsSupportHelp =>
      'Optional, and nothing here unlocks anything.';

  @override
  String settingsTrashCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'Nothing in the trash',
    );
    return '$_temp0';
  }

  @override
  String get supportWatchTooltip => 'Watch an advert to support Alaya';

  @override
  String ledgerRowSemantics(String title, String amount) {
    return '$title, $amount';
  }

  @override
  String ledgerRowSemanticsDetailed(
    String title,
    String amount,
    String detail,
  ) {
    return '$title, $amount, $detail';
  }
}
