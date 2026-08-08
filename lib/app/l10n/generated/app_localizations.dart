import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AlayaStrings
/// returned by `AlayaStrings.of(context)`.
///
/// Applications need to include `AlayaStrings.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AlayaStrings.localizationsDelegates,
///   supportedLocales: AlayaStrings.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AlayaStrings.supportedLocales
/// property.
abstract class AlayaStrings {
  AlayaStrings(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AlayaStrings of(BuildContext context) {
    return Localizations.of<AlayaStrings>(context, AlayaStrings)!;
  }

  static const LocalizationsDelegate<AlayaStrings> delegate =
      _AlayaStringsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The app's name, shown in the drawer header.
  ///
  /// In en, this message translates to:
  /// **'Alaya'**
  String get appName;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navExpenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get navExpenses;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get navShopping;

  /// No description provided for @navRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get navRecurring;

  /// No description provided for @navServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get navServices;

  /// No description provided for @navCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get navCalendar;

  /// No description provided for @navInsights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get navInsights;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @navThemeLab.
  ///
  /// In en, this message translates to:
  /// **'Theme Lab'**
  String get navThemeLab;

  /// Commits an edit. Active voice, and the same word appears in the resulting confirmation.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get actionSave;

  /// No description provided for @actionSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get actionSaved;

  /// No description provided for @actionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get actionCancel;

  /// No description provided for @actionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get actionDelete;

  /// No description provided for @actionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get actionDeleted;

  /// No description provided for @actionUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get actionUndo;

  /// No description provided for @actionRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get actionRetry;

  /// No description provided for @actionAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get actionAdd;

  /// No description provided for @actionEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get actionEdit;

  /// No description provided for @actionDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get actionDone;

  /// No description provided for @actionClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get actionClose;

  /// No description provided for @actionSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get actionSelect;

  /// No description provided for @actionClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get actionClear;

  /// No description provided for @actionClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get actionClearAll;

  /// No description provided for @actionSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get actionSearch;

  /// No description provided for @actionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get actionConfirm;

  /// No description provided for @actionDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get actionDiscard;

  /// No description provided for @actionKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get actionKeepEditing;

  /// Accessibility label for the dismiss affordance on a removable tag chip.
  ///
  /// In en, this message translates to:
  /// **'Remove tag'**
  String get actionRemoveTag;

  /// Accessibility label for the clear button inside AlayaSearchField.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get actionClearSearch;

  /// No description provided for @addExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get addExpense;

  /// No description provided for @addIncome.
  ///
  /// In en, this message translates to:
  /// **'Add income'**
  String get addIncome;

  /// No description provided for @addTransfer.
  ///
  /// In en, this message translates to:
  /// **'Add transfer'**
  String get addTransfer;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItem;

  /// No description provided for @addToShoppingList.
  ///
  /// In en, this message translates to:
  /// **'Add to shopping list'**
  String get addToShoppingList;

  /// DateText.relative, when the date is the clock's today. Sentence case; it can begin a row.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateToday;

  /// No description provided for @dateYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dateYesterday;

  /// No description provided for @dateTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get dateTomorrow;

  /// No description provided for @emptyTitleNoTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get emptyTitleNoTransactions;

  /// An empty screen is an invitation to act, so this names the action rather than describing the emptiness.
  ///
  /// In en, this message translates to:
  /// **'Add your first expense and it will appear here.'**
  String get emptyBodyNoTransactions;

  /// No description provided for @emptyTitleNoItems.
  ///
  /// In en, this message translates to:
  /// **'Nothing in your inventory'**
  String get emptyTitleNoItems;

  /// No description provided for @emptyBodyNoItems.
  ///
  /// In en, this message translates to:
  /// **'Add an item to start tracking what you have at home.'**
  String get emptyBodyNoItems;

  /// No description provided for @emptyTitleNoShopping.
  ///
  /// In en, this message translates to:
  /// **'Your list is empty'**
  String get emptyTitleNoShopping;

  /// No description provided for @emptyBodyNoShopping.
  ///
  /// In en, this message translates to:
  /// **'Add something, or let Alaya suggest items you are low on.'**
  String get emptyBodyNoShopping;

  /// No description provided for @emptyTitleNoRecurring.
  ///
  /// In en, this message translates to:
  /// **'No recurring bills'**
  String get emptyTitleNoRecurring;

  /// No description provided for @emptyBodyNoRecurring.
  ///
  /// In en, this message translates to:
  /// **'Set up a bill or subscription and Alaya will remind you when it is due.'**
  String get emptyBodyNoRecurring;

  /// No description provided for @emptyTitleNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get emptyTitleNoResults;

  /// No description provided for @emptyBodyNoResults.
  ///
  /// In en, this message translates to:
  /// **'Try a shorter search, or check the spelling.'**
  String get emptyBodyNoResults;

  /// No description provided for @loadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loadingLabel;

  /// No description provided for @loadingTransactions.
  ///
  /// In en, this message translates to:
  /// **'Loading transactions'**
  String get loadingTransactions;

  /// Errors do not apologise and are never vague. This pairs with a specific body message.
  ///
  /// In en, this message translates to:
  /// **'That did not work'**
  String get errorTitleGeneric;

  /// No description provided for @errorBodyGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on our side. Try again.'**
  String get errorBodyGeneric;

  /// No description provided for @errorTitleNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get errorTitleNotFound;

  /// No description provided for @errorBodyNotFound.
  ///
  /// In en, this message translates to:
  /// **'This item may have been deleted.'**
  String get errorBodyNotFound;

  /// No description provided for @errorBodyNoConnection.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Alaya works offline, but rates will not refresh.'**
  String get errorBodyNoConnection;

  /// No description provided for @errorFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This is required'**
  String get errorFieldRequired;

  /// No description provided for @errorAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount'**
  String get errorAmountInvalid;

  /// No description provided for @errorAmountZero.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero'**
  String get errorAmountZero;

  /// No description provided for @errorAmountInvalidCharacter.
  ///
  /// In en, this message translates to:
  /// **'Digits only'**
  String get errorAmountInvalidCharacter;

  /// No description provided for @errorAmountNegativeNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive amount'**
  String get errorAmountNegativeNotAllowed;

  /// No description provided for @errorAmountTooManyDecimals.
  ///
  /// In en, this message translates to:
  /// **'Too many decimal places'**
  String get errorAmountTooManyDecimals;

  /// No description provided for @errorAmountTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That amount is too large'**
  String get errorAmountTooLarge;

  /// No description provided for @errorQuantityTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That quantity is too large'**
  String get errorQuantityTooLarge;

  /// No description provided for @errorQuantityInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a quantity'**
  String get errorQuantityInvalid;

  /// No description provided for @errorQuantityInvalidCharacter.
  ///
  /// In en, this message translates to:
  /// **'Digits only'**
  String get errorQuantityInvalidCharacter;

  /// No description provided for @errorQuantityNegativeNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Enter a positive quantity'**
  String get errorQuantityNegativeNotAllowed;

  /// The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded.
  ///
  /// In en, this message translates to:
  /// **'Too precise for this unit'**
  String get errorQuantityTooPrecise;

  /// No description provided for @errorDateInvalid.
  ///
  /// In en, this message translates to:
  /// **'Choose a date'**
  String get errorDateInvalid;

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this?'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'You can undo this for the next few seconds.'**
  String get confirmDeleteBody;

  /// No description provided for @confirmDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get confirmDiscardTitle;

  /// No description provided for @confirmDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'What you have typed will not be saved.'**
  String get confirmDiscardBody;

  /// No description provided for @labelAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get labelAmount;

  /// No description provided for @labelQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get labelQuantity;

  /// No description provided for @labelUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get labelUnit;

  /// No description provided for @labelDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get labelDate;

  /// No description provided for @labelAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get labelAccount;

  /// No description provided for @labelPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get labelPaymentMethod;

  /// No description provided for @labelPayee.
  ///
  /// In en, this message translates to:
  /// **'Payee'**
  String get labelPayee;

  /// No description provided for @labelCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get labelCategory;

  /// No description provided for @labelTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get labelTags;

  /// No description provided for @labelNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get labelNote;

  /// No description provided for @labelFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get labelFrom;

  /// No description provided for @labelTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get labelTo;

  /// No description provided for @labelItem.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get labelItem;

  /// No description provided for @labelExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiry'**
  String get labelExpiry;

  /// No description provided for @labelTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get labelTotal;

  /// No description provided for @hintSelectAccount.
  ///
  /// In en, this message translates to:
  /// **'Choose an account'**
  String get hintSelectAccount;

  /// No description provided for @hintSelectUnit.
  ///
  /// In en, this message translates to:
  /// **'Choose a unit'**
  String get hintSelectUnit;

  /// No description provided for @hintSelectTags.
  ///
  /// In en, this message translates to:
  /// **'Choose tags'**
  String get hintSelectTags;

  /// No description provided for @hintSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Choose a date'**
  String get hintSelectDate;

  /// No description provided for @hintSearchItems.
  ///
  /// In en, this message translates to:
  /// **'Search items'**
  String get hintSearchItems;

  /// No description provided for @hintNote.
  ///
  /// In en, this message translates to:
  /// **'Add a note'**
  String get hintNote;

  /// The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}'**
  String amountUnconverted(int count);

  /// Shown when a conversion used the nearest earlier rate rather than the exact date's.
  ///
  /// In en, this message translates to:
  /// **'Approximate rate'**
  String get amountApproximate;

  /// Overflow indicator when a row cannot show every tag.
  ///
  /// In en, this message translates to:
  /// **'+{count}'**
  String tagCountMore(int count);

  /// StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set.
  ///
  /// In en, this message translates to:
  /// **'Needs details'**
  String get statusNeedsReview;

  /// StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11).
  ///
  /// In en, this message translates to:
  /// **'Unallocated'**
  String get statusUnallocated;

  /// StatusChip on a batch whose source transaction was deleted. The food did not un-exist.
  ///
  /// In en, this message translates to:
  /// **'Receipt deleted'**
  String get statusDetached;

  /// No description provided for @statusApproximate.
  ///
  /// In en, this message translates to:
  /// **'Approximate'**
  String get statusApproximate;

  /// No description provided for @lowStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get lowStockLabel;

  /// No description provided for @expiringSoonLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiring soon'**
  String get expiringSoonLabel;

  /// No description provided for @expiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expiredLabel;

  /// No description provided for @overdueLabel.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdueLabel;

  /// No description provided for @dueTodayLabel.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueTodayLabel;

  /// No description provided for @paidLabel.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paidLabel;

  /// No description provided for @skippedLabel.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get skippedLabel;

  /// No description provided for @kindDeposit.
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get kindDeposit;

  /// No description provided for @kindWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Money out'**
  String get kindWithdrawal;

  /// No description provided for @kindTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get kindTransfer;

  /// No description provided for @kindAdjustmentIncrease.
  ///
  /// In en, this message translates to:
  /// **'Correction up'**
  String get kindAdjustmentIncrease;

  /// No description provided for @kindAdjustmentDecrease.
  ///
  /// In en, this message translates to:
  /// **'Correction down'**
  String get kindAdjustmentDecrease;

  /// No description provided for @subtypeGrocery.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get subtypeGrocery;

  /// No description provided for @subtypeHousehold.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get subtypeHousehold;

  /// No description provided for @subtypeElectronics.
  ///
  /// In en, this message translates to:
  /// **'Electronics'**
  String get subtypeElectronics;

  /// No description provided for @subtypeBill.
  ///
  /// In en, this message translates to:
  /// **'Bill'**
  String get subtypeBill;

  /// No description provided for @subtypeTransferSelf.
  ///
  /// In en, this message translates to:
  /// **'Between my accounts'**
  String get subtypeTransferSelf;

  /// No description provided for @subtypeTransferOut.
  ///
  /// In en, this message translates to:
  /// **'Sent to someone'**
  String get subtypeTransferOut;

  /// No description provided for @subtypeSalaryIn.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get subtypeSalaryIn;

  /// No description provided for @subtypeOtherIn.
  ///
  /// In en, this message translates to:
  /// **'Other income'**
  String get subtypeOtherIn;

  /// No description provided for @subtypeOtherOut.
  ///
  /// In en, this message translates to:
  /// **'Other spending'**
  String get subtypeOtherOut;

  /// Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}'**
  String needsReviewBanner(int count);

  /// No description provided for @needsReviewAction.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get needsReviewAction;

  /// No description provided for @filterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterTitle;

  /// No description provided for @filterDateRange.
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get filterDateRange;

  /// No description provided for @filterKind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get filterKind;

  /// No description provided for @filterSubtype.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get filterSubtype;

  /// No description provided for @filterApply.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get filterApply;

  /// No description provided for @filterReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get filterReset;

  /// No description provided for @filterChipAccount.
  ///
  /// In en, this message translates to:
  /// **'Account: {name}'**
  String filterChipAccount(String name);

  /// No description provided for @filterChipPayee.
  ///
  /// In en, this message translates to:
  /// **'Payee: {name}'**
  String filterChipPayee(String name);

  /// No description provided for @filterChipRange.
  ///
  /// In en, this message translates to:
  /// **'{label}'**
  String filterChipRange(String label);

  /// No description provided for @rangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get rangeToday;

  /// No description provided for @rangeLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get rangeLast7Days;

  /// No description provided for @rangeLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get rangeLast30Days;

  /// No description provided for @rangeThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get rangeThisMonth;

  /// No description provided for @rangeLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get rangeLastMonth;

  /// No description provided for @rangeThisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get rangeThisYear;

  /// No description provided for @rangeAllTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get rangeAllTime;

  /// No description provided for @rangeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get rangeCustom;

  /// No description provided for @searchTransactionsHint.
  ///
  /// In en, this message translates to:
  /// **'Search notes'**
  String get searchTransactionsHint;

  /// No description provided for @transactionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Transaction deleted'**
  String get transactionDeleted;

  /// No description provided for @quickAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick add'**
  String get quickAddTitle;

  /// No description provided for @quickAddMoneyIn.
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get quickAddMoneyIn;

  /// No description provided for @quickAddMoneyOut.
  ///
  /// In en, this message translates to:
  /// **'Money out'**
  String get quickAddMoneyOut;

  /// No description provided for @quickAddSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get quickAddSave;

  /// No description provided for @actionAddDetails.
  ///
  /// In en, this message translates to:
  /// **'Add details'**
  String get actionAddDetails;

  /// No description provided for @editorTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New transaction'**
  String get editorTitleNew;

  /// No description provided for @editorTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit transaction'**
  String get editorTitleEdit;

  /// No description provided for @sectionWhatAndHowMuch.
  ///
  /// In en, this message translates to:
  /// **'What and how much'**
  String get sectionWhatAndHowMuch;

  /// No description provided for @sectionWhereItCameFrom.
  ///
  /// In en, this message translates to:
  /// **'Where it came from'**
  String get sectionWhereItCameFrom;

  /// No description provided for @sectionWhereItWent.
  ///
  /// In en, this message translates to:
  /// **'Where it went'**
  String get sectionWhereItWent;

  /// No description provided for @sectionWhatYouBought.
  ///
  /// In en, this message translates to:
  /// **'What you bought'**
  String get sectionWhatYouBought;

  /// No description provided for @sectionWarranty.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get sectionWarranty;

  /// No description provided for @sectionSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get sectionSchedule;

  /// No description provided for @transferOwnAccount.
  ///
  /// In en, this message translates to:
  /// **'To my own account'**
  String get transferOwnAccount;

  /// No description provided for @transferSomeoneElse.
  ///
  /// In en, this message translates to:
  /// **'To someone else'**
  String get transferSomeoneElse;

  /// No description provided for @transferOwnAccountHelp.
  ///
  /// In en, this message translates to:
  /// **'Moves money between your accounts. Your total does not change.'**
  String get transferOwnAccountHelp;

  /// No description provided for @transferSomeoneElseHelp.
  ///
  /// In en, this message translates to:
  /// **'Money leaves your accounts. This is a withdrawal.'**
  String get transferSomeoneElseHelp;

  /// No description provided for @alsoAddToInventory.
  ///
  /// In en, this message translates to:
  /// **'Also add to inventory'**
  String get alsoAddToInventory;

  /// No artefact. Recorded as spending and nothing else.
  ///
  /// In en, this message translates to:
  /// **'Just an expense'**
  String get destinationNone;

  /// Creates stock. Names the Inventory module, matching navInventory.
  ///
  /// In en, this message translates to:
  /// **'Save to Inventory'**
  String get destinationInventory;

  /// Creates an asset. Names the Services module, matching navServices.
  ///
  /// In en, this message translates to:
  /// **'Save to Services'**
  String get destinationAsset;

  /// Hands off to the template builder. Matches navRecurring.
  ///
  /// In en, this message translates to:
  /// **'Save to Recurring'**
  String get destinationRecurring;

  /// No description provided for @lineAdd.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get lineAdd;

  /// No description provided for @lineDescription.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get lineDescription;

  /// No description provided for @lineUnitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get lineUnitPrice;

  /// No description provided for @lineAmount.
  ///
  /// In en, this message translates to:
  /// **'Line total'**
  String get lineAmount;

  /// Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.
  ///
  /// In en, this message translates to:
  /// **'Created: {name}'**
  String lineCreatedLink(String name);

  /// No description provided for @payeeCreate.
  ///
  /// In en, this message translates to:
  /// **'New payee “{name}”'**
  String payeeCreate(String name);

  /// No description provided for @saveExpense.
  ///
  /// In en, this message translates to:
  /// **'Save expense'**
  String get saveExpense;

  /// No description provided for @saveIncome.
  ///
  /// In en, this message translates to:
  /// **'Save income'**
  String get saveIncome;

  /// No description provided for @saveTransfer.
  ///
  /// In en, this message translates to:
  /// **'Save transfer'**
  String get saveTransfer;

  /// No description provided for @detailSectionLines.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get detailSectionLines;

  /// No description provided for @detailSectionDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get detailSectionDetails;

  /// No description provided for @actionFreezeConversion.
  ///
  /// In en, this message translates to:
  /// **'Show in another currency'**
  String get actionFreezeConversion;

  /// Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).
  ///
  /// In en, this message translates to:
  /// **'Frozen on {date} at {rate}'**
  String frozenConversionNote(String date, String rate);

  /// No description provided for @deleteReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Why? (optional)'**
  String get deleteReasonHint;

  /// No description provided for @actionDeleteTransaction.
  ///
  /// In en, this message translates to:
  /// **'Delete transaction'**
  String get actionDeleteTransaction;

  /// No description provided for @labelSubtype.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get labelSubtype;

  /// No description provided for @labelKind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get labelKind;

  /// No description provided for @themeLabTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme Lab'**
  String get themeLabTitle;

  /// No description provided for @themeLabSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every token, component and semantic colour, light and dark.'**
  String get themeLabSubtitle;

  /// No description provided for @themeLabSectionSpacing.
  ///
  /// In en, this message translates to:
  /// **'Spacing'**
  String get themeLabSectionSpacing;

  /// No description provided for @themeLabSectionRadii.
  ///
  /// In en, this message translates to:
  /// **'Radii'**
  String get themeLabSectionRadii;

  /// No description provided for @themeLabSectionTypography.
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get themeLabSectionTypography;

  /// No description provided for @themeLabSectionElevation.
  ///
  /// In en, this message translates to:
  /// **'Elevation'**
  String get themeLabSectionElevation;

  /// No description provided for @themeLabSectionSemantic.
  ///
  /// In en, this message translates to:
  /// **'Semantic colours'**
  String get themeLabSectionSemantic;

  /// No description provided for @themeLabSectionSurfaces.
  ///
  /// In en, this message translates to:
  /// **'Surface tiers'**
  String get themeLabSectionSurfaces;

  /// No description provided for @themeLabSectionComponents.
  ///
  /// In en, this message translates to:
  /// **'Components'**
  String get themeLabSectionComponents;

  /// No description provided for @themeLabSectionPalettes.
  ///
  /// In en, this message translates to:
  /// **'Palettes'**
  String get themeLabSectionPalettes;

  /// No description provided for @themeLabLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLabLight;

  /// No description provided for @themeLabDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeLabDark;

  /// No description provided for @semanticIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get semanticIncome;

  /// No description provided for @semanticExpense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get semanticExpense;

  /// No description provided for @semanticTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get semanticTransfer;

  /// No description provided for @semanticWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get semanticWarning;

  /// No description provided for @semanticDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger'**
  String get semanticDanger;

  /// No description provided for @semanticSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get semanticSuccess;

  /// No description provided for @semanticMuted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get semanticMuted;

  /// No description provided for @drawerSectionMoney.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get drawerSectionMoney;

  /// No description provided for @drawerSectionHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get drawerSectionHome;

  /// No description provided for @drawerSectionMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get drawerSectionMore;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get inventoryGroupFavourites;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get inventoryGroupUntagged;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get itemKindGeneric;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get itemKindFood;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Medicine'**
  String get itemKindMedicine;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Beauty'**
  String get itemKindBeauty;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get itemKindHousehold;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get itemKindOther;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Favourites only'**
  String get filterFavouritesOnly;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get actionFavourite;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get actionUnfavourite;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStockLabel;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 batch} other{{count} batches}}'**
  String itemBatchCount(num count);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Loading inventory'**
  String get loadingInventory;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Batches'**
  String get detailSectionBatches;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'From a purchase'**
  String get batchOriginPurchase;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Added by hand'**
  String get batchOriginManual;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get batchOriginImported;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'From an adjustment'**
  String get batchOriginAdjustment;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Purchased'**
  String get labelPurchased;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Stored in'**
  String get labelStorageLocation;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Unit cost'**
  String get labelUnitCost;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Bought'**
  String get labelInitial;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Nearest expiry'**
  String get labelNearestExpiry;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Shown in'**
  String get labelDisplayUnit;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get labelItemKind;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Low-stock level'**
  String get labelLowStockThreshold;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Warn before expiry'**
  String get labelExpiryNotifyDays;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Use some'**
  String get actionConsume;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Add a batch'**
  String get actionAddBatch;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Movement history'**
  String get actionViewHistory;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Delete item'**
  String get actionDeleteItem;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Delete this item?'**
  String get confirmDeleteItemTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.'**
  String confirmDeleteItemBody(num count);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Item deleted'**
  String get itemDeleted;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}'**
  String expiresInDays(num days);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}'**
  String expiredDaysAgo(num days);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'What it is'**
  String get sectionWhatItIs;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Stock rules'**
  String get sectionStockRules;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get unitCategoryWeight;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get unitCategoryVolume;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get unitCategoryCount;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Measured in {category}'**
  String unitCategoryLocked(Object category);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.'**
  String get unitCategoryLockedHelp;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Days of warning before a batch expires.'**
  String get expiryNotifyDaysHelp;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Favourite'**
  String get labelFavourite;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Save item'**
  String get saveItem;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'How much'**
  String get sectionHowMuch;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Batch details'**
  String get sectionBatchDetails;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Save batch'**
  String get saveBatch;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Batch saved'**
  String get batchSaved;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Freezer, pantry, bathroom shelf…'**
  String get hintStorageLocation;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Use stock'**
  String get consumeTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get consumeKindConsume;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Thrown away'**
  String get consumeKindWaste;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get consumeKindExpired;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get consumeRecorded;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Taking from'**
  String get consumeFromLabel;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Oldest expiry first.'**
  String get consumeFefoNote;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}'**
  String consumeSpansBatches(num count);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'More than you have on hand'**
  String get consumeOverAvailable;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Movement history'**
  String get historyTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Opening stock'**
  String get movementKindOpeningIn;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Bought'**
  String get movementKindPurchaseIn;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Added by hand'**
  String get movementKindManualIn;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get movementKindConsume;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Thrown away'**
  String get movementKindWaste;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get movementKindExpired;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Adjusted up'**
  String get movementKindAdjustIn;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Adjusted down'**
  String get movementKindAdjustOut;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Reversed'**
  String get movementReversed;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Reverses an earlier movement'**
  String get movementIsReversal;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Reverse'**
  String get actionReverse;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Reverse this movement?'**
  String get confirmReverseTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'An opposite movement is appended. Nothing is erased — both entries stay in the history.'**
  String get confirmReverseBody;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Movement reversed'**
  String get movementReversedSnack;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded yet'**
  String get emptyTitleNoMovements;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Using, wasting or adjusting this batch will show up here.'**
  String get emptyBodyNoMovements;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Add a batch and it will appear here with its expiry.'**
  String get emptyBodyNoBatches;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.'**
  String get batchQuantityLockedHelp;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String daysCount(num days);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Group favourites first'**
  String get groupByFavourites;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Record as used'**
  String get consumeCommitUsed;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Record as thrown away'**
  String get consumeCommitWaste;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Record as expired'**
  String get consumeCommitExpired;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Low · {count}'**
  String lowStockWithCount(Object count);

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Delete batch'**
  String get actionDeleteBatch;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Delete this batch?'**
  String get confirmDeleteBatchTitle;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.'**
  String get confirmDeleteBatchBody;

  /// Phase 6B — inventory.
  ///
  /// In en, this message translates to:
  /// **'Batch deleted'**
  String get batchDeleted;

  /// Creates a catalogued item inline while itemising a receipt.
  ///
  /// In en, this message translates to:
  /// **'New item'**
  String get itemCreate;

  /// Shown in the line editor when the item catalogue is empty.
  ///
  /// In en, this message translates to:
  /// **'No items yet — create one so this line becomes stock.'**
  String get itemCreateHint;

  /// Prompt for unitCategory on inline creation; immutable after create (Law L8).
  ///
  /// In en, this message translates to:
  /// **'How is it measured? This cannot change later.'**
  String get itemCreateCategoryPrompt;

  /// Shown when an item with the same normalized name and unit category exists.
  ///
  /// In en, this message translates to:
  /// **'You already have this item, measured the same way. Open the one you have instead of adding a second.'**
  String get itemDuplicateBody;

  /// Shown when the chosen UnitCategory has no rows in units.
  ///
  /// In en, this message translates to:
  /// **'No units are set up for this measure yet. Pick a different measure, or add units in Settings first.'**
  String get itemUnitsMissingBody;

  /// Informational note, never a block: Law L8 makes same-name/different-category distinct items.
  ///
  /// In en, this message translates to:
  /// **'You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.'**
  String get itemSimilarNote;

  /// Opens the existing item a duplicate collides with.
  ///
  /// In en, this message translates to:
  /// **'Open the one I have'**
  String get actionOpenExisting;

  /// Running total of estimated prices on a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Estimated'**
  String get shoppingEstimate;

  /// Opens the list manager from the app bar.
  ///
  /// In en, this message translates to:
  /// **'Switch list'**
  String get shoppingSwitchList;

  /// Progress line above a shopping list.
  ///
  /// In en, this message translates to:
  /// **'{checked} of {total} ticked'**
  String shoppingCheckedCount(Object checked, Object total);

  /// Shopping list empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this list yet'**
  String get emptyTitleNoEntries;

  /// Shopping list empty state body.
  ///
  /// In en, this message translates to:
  /// **'Add what you need, or pull in suggestions from what is running low.'**
  String get emptyBodyNoEntries;

  /// Adds one entry to a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addEntry;

  /// Header for entries with no tag.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get shoppingGroupUntagged;

  /// Clears every tick on a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Untick everything'**
  String get actionUncheckAll;

  /// Entry editor sheet title.
  ///
  /// In en, this message translates to:
  /// **'What do you need?'**
  String get entryEditorTitle;

  /// Free-text label for a shopping entry.
  ///
  /// In en, this message translates to:
  /// **'Name it'**
  String get entryFreeTextLabel;

  /// Hint showing that an entry need not be an inventory item.
  ///
  /// In en, this message translates to:
  /// **'Television, birthday card, light bulbs…'**
  String get entryFreeTextHint;

  /// Optional link from a shopping entry to a catalogued item.
  ///
  /// In en, this message translates to:
  /// **'Link to an item'**
  String get entryLinkItem;

  /// Dropdown option leaving itemId null.
  ///
  /// In en, this message translates to:
  /// **'Not in my inventory'**
  String get entryNoItem;

  /// Optional per-entry price estimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated price'**
  String get labelEstimatedPrice;

  /// Rejection when neither freeText nor itemId is set.
  ///
  /// In en, this message translates to:
  /// **'Give it a name, or link it to an item'**
  String get entryNeedsSomething;

  /// Chip marking an auto-generated low-stock entry.
  ///
  /// In en, this message translates to:
  /// **'Suggested'**
  String get originAutoLowStock;

  /// Chip shown once an auto entry has been edited into a manual one.
  ///
  /// In en, this message translates to:
  /// **'Yours now'**
  String get originPromoted;

  /// Hides an auto suggestion until a later date.
  ///
  /// In en, this message translates to:
  /// **'Snooze a week'**
  String get actionSnooze;

  /// Dismisses an auto suggestion until stock recovers and drops again.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get actionDismiss;

  /// Precedes a DateText on a snoozed entry.
  ///
  /// In en, this message translates to:
  /// **'Snoozed until'**
  String get snoozedUntilLabel;

  /// Low-stock suggestion sheet title.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get generateTitle;

  /// Low-stock suggestion sheet body.
  ///
  /// In en, this message translates to:
  /// **'These are below the level you set. Add the ones you want.'**
  String get generateBody;

  /// Precedes a QtyText giving threshold minus stock on hand.
  ///
  /// In en, this message translates to:
  /// **'Short by'**
  String get generateShortBy;

  /// Re-runs low-stock generation.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get generateRefresh;

  /// Generate sheet empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing is running low'**
  String get generateEmptyTitle;

  /// Generate sheet empty state body.
  ///
  /// In en, this message translates to:
  /// **'Set a low-stock level on an item and it will show up here when it drops.'**
  String get generateEmptyBody;

  /// Result snack after regeneration.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 suggestion added} other{{count} suggestions added}}'**
  String generateAdded(num count);

  /// Convert-to-purchase screen title.
  ///
  /// In en, this message translates to:
  /// **'Turn into a purchase'**
  String get convertTitle;

  /// Explains the handoff to the expense editor.
  ///
  /// In en, this message translates to:
  /// **'Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.'**
  String get convertBody;

  /// Primary action; hands off to the 6A editor.
  ///
  /// In en, this message translates to:
  /// **'Open the expense'**
  String get convertConfirm;

  /// Convert screen empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing is ticked'**
  String get convertNothingTitle;

  /// Convert screen empty state body.
  ///
  /// In en, this message translates to:
  /// **'Tick what you actually bought, then come back.'**
  String get convertNothingBody;

  /// How many lines the draft will carry.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line} other{{count} lines}}'**
  String convertLineCount(num count);

  /// List manager sheet title.
  ///
  /// In en, this message translates to:
  /// **'Your lists'**
  String get listManagerTitle;

  /// Field label when creating or renaming a list.
  ///
  /// In en, this message translates to:
  /// **'List name'**
  String get listNameLabel;

  /// Creates a shopping list.
  ///
  /// In en, this message translates to:
  /// **'New list'**
  String get listCreate;

  /// Renames a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get listRename;

  /// Marks a list as the one that opens by default.
  ///
  /// In en, this message translates to:
  /// **'Make default'**
  String get listSetDefault;

  /// Chip on the default list.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get listDefaultBadge;

  /// Archives a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get listArchive;

  /// Un-archives a shopping list.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get listUnarchive;

  /// Chip on an archived list.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get listArchivedBadge;

  /// Section header for archived lists.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get listArchivedSection;

  /// List manager empty state.
  ///
  /// In en, this message translates to:
  /// **'No lists yet'**
  String get emptyTitleNoLists;

  /// List manager empty state body.
  ///
  /// In en, this message translates to:
  /// **'Create one and it becomes your default.'**
  String get emptyBodyNoLists;

  /// Skeleton label for shopping surfaces.
  ///
  /// In en, this message translates to:
  /// **'Loading your list'**
  String get loadingShopping;

  /// Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone.
  ///
  /// In en, this message translates to:
  /// **'Add to my list'**
  String get actionAddToList;

  /// Chip on a dismissed suggestion; it stays listed so it can be accepted later.
  ///
  /// In en, this message translates to:
  /// **'Turned down'**
  String get suggestionDismissed;

  /// Title of the dedicated line-items page.
  ///
  /// In en, this message translates to:
  /// **'What you bought'**
  String get lineItemsTitle;

  /// Opens the line-items page from the transaction editor.
  ///
  /// In en, this message translates to:
  /// **'Add or edit items'**
  String get lineItemsManage;

  /// Adds one line from the line-items page.
  ///
  /// In en, this message translates to:
  /// **'Add an item'**
  String get lineItemsAdd;

  /// Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet.
  ///
  /// In en, this message translates to:
  /// **'Save & add another'**
  String get lineItemsSaveAndAnother;

  /// Running count on the line-items page.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items yet} =1{1 item} other{{count} items}}'**
  String lineItemsCount(num count);

  /// Line-items page empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing itemised yet'**
  String get emptyTitleNoLineItems;

  /// Line-items page empty state body.
  ///
  /// In en, this message translates to:
  /// **'Add what was on the receipt. Anything you leave out still counts toward the total.'**
  String get emptyBodyNoLineItems;

  /// Removes one line from a transaction.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get actionRemove;

  /// Snack after removing a line.
  ///
  /// In en, this message translates to:
  /// **'Item removed'**
  String get lineRemoved;

  /// Precedes the summed line total on the line-items page.
  ///
  /// In en, this message translates to:
  /// **'Itemised'**
  String get lineItemsAllocated;

  /// Group header for outflow templates.
  ///
  /// In en, this message translates to:
  /// **'Going out'**
  String get recurringOutflow;

  /// Group header for inflow templates — salary reads as income, not a negative bill.
  ///
  /// In en, this message translates to:
  /// **'Coming in'**
  String get recurringInflow;

  /// Precedes a DateText giving the next due date.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get recurringNextDue;

  /// Chip on an occurrence past its due date. Derived from the clock, never stored.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get recurringOverdue;

  /// Chip on a paused template.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get recurringPaused;

  /// Chip when the next occurrence falls today.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get recurringDueToday;

  /// Template list empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing recurring yet'**
  String get emptyTitleNoTemplates;

  /// Template list empty state body.
  ///
  /// In en, this message translates to:
  /// **'Add a bill, a subscription or a salary and it will appear here when it is next due.'**
  String get emptyBodyNoTemplates;

  /// Adds a recurring template.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addTemplate;

  /// Pauses a template.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get actionPause;

  /// Resumes a paused template.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get actionResume;

  /// Skeleton label for recurring surfaces.
  ///
  /// In en, this message translates to:
  /// **'Loading your schedule'**
  String get loadingRecurring;

  /// First section of the template builder.
  ///
  /// In en, this message translates to:
  /// **'What it is'**
  String get builderSectionWhat;

  /// Frequency section of the template builder.
  ///
  /// In en, this message translates to:
  /// **'How often'**
  String get builderSectionWhen;

  /// Amount and account section of the template builder.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get builderSectionDefaults;

  /// Template name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get labelTemplateName;

  /// Bill, subscription, rent or salary.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get labelRecurringKind;

  /// Whether money goes out or comes in.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get labelDirection;

  /// RecurringDirection.outflow.
  ///
  /// In en, this message translates to:
  /// **'Money out'**
  String get directionOutflow;

  /// RecurringDirection.inflow.
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get directionInflow;

  /// RecurringKind.bill.
  ///
  /// In en, this message translates to:
  /// **'Bill'**
  String get kindBill;

  /// RecurringKind.subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get kindSubscription;

  /// RecurringKind.rent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get kindRent;

  /// RecurringKind.salary.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get kindSalary;

  /// Precedes the interval count and unit.
  ///
  /// In en, this message translates to:
  /// **'Every'**
  String get labelEvery;

  /// RecurringIntervalUnit.day.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day} other{days}}'**
  String unitDay(num count);

  /// RecurringIntervalUnit.week.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{week} other{weeks}}'**
  String unitWeek(num count);

  /// RecurringIntervalUnit.month.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{month} other{months}}'**
  String unitMonth(num count);

  /// RecurringIntervalUnit.year.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{year} other{years}}'**
  String unitYear(num count);

  /// anchorDayOfMonth. Stored once, clamped at render (anomaly A13).
  ///
  /// In en, this message translates to:
  /// **'On day of the month'**
  String get labelAnchorDay;

  /// Explains that the anchor never walks backwards.
  ///
  /// In en, this message translates to:
  /// **'Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.'**
  String get anchorDayHelp;

  /// startDateKey.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get labelStartDate;

  /// endDateKey, optional.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get labelEndDate;

  /// defaultAmount — a default, not a fixed figure.
  ///
  /// In en, this message translates to:
  /// **'Usual amount'**
  String get labelDefaultAmount;

  /// remindDaysBefore.
  ///
  /// In en, this message translates to:
  /// **'Remind me'**
  String get labelRemindBefore;

  /// Commits the template.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveTemplate;

  /// Header of the frequency preview.
  ///
  /// In en, this message translates to:
  /// **'Next three'**
  String get previewTitle;

  /// Frequency preview with nothing to show.
  ///
  /// In en, this message translates to:
  /// **'Set a start date to see when this lands.'**
  String get previewEmpty;

  /// Marks a previewed date the anchor could not reach.
  ///
  /// In en, this message translates to:
  /// **'Shortened to fit the month'**
  String get previewClamped;

  /// Pay sheet title.
  ///
  /// In en, this message translates to:
  /// **'Record this payment'**
  String get payTitle;

  /// Pay sheet title for an inflow.
  ///
  /// In en, this message translates to:
  /// **'Record this receipt'**
  String get payTitleInflow;

  /// The real figure, which may differ from the default.
  ///
  /// In en, this message translates to:
  /// **'Amount actually paid'**
  String get labelActualAmount;

  /// Inflow wording for the same field.
  ///
  /// In en, this message translates to:
  /// **'Amount actually received'**
  String get labelActualAmountInflow;

  /// Precedes the default amount when the actual differs from it.
  ///
  /// In en, this message translates to:
  /// **'Usually'**
  String get payUsualWas;

  /// paidDateKey.
  ///
  /// In en, this message translates to:
  /// **'Paid on'**
  String get labelPaidOn;

  /// Commits the payment and creates the transaction.
  ///
  /// In en, this message translates to:
  /// **'Record it'**
  String get payCommit;

  /// Result snack after paying.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get payRecorded;

  /// Rejection when no account is selected.
  ///
  /// In en, this message translates to:
  /// **'Choose which account it came from'**
  String get payNeedsAccount;

  /// Confirmation before undoing.
  ///
  /// In en, this message translates to:
  /// **'Undo this payment?'**
  String get payUndoTitle;

  /// Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4).
  ///
  /// In en, this message translates to:
  /// **'The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.'**
  String get payUndoBody;

  /// Result snack after undoing.
  ///
  /// In en, this message translates to:
  /// **'Payment undone'**
  String get payUndone;

  /// Marks an occurrence deliberately skipped.
  ///
  /// In en, this message translates to:
  /// **'Skip this one'**
  String get actionSkip;

  /// Chip on a skipped occurrence, and the snack after skipping.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get occurrenceSkipped;

  /// Occurrence history screen title.
  ///
  /// In en, this message translates to:
  /// **'Payment history'**
  String get historyRecurringTitle;

  /// Badge when paidAmount != defaultAmount.
  ///
  /// In en, this message translates to:
  /// **'Differed from the usual amount'**
  String get historyDefaultVsActual;

  /// Occurrence history empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing due yet'**
  String get emptyTitleNoOccurrences;

  /// Empty state body, stating anomaly A14 plainly.
  ///
  /// In en, this message translates to:
  /// **'Occurrences appear as their due dates arrive. Nothing is ever paid for you.'**
  String get emptyBodyNoOccurrences;

  /// RecurringOccurrenceStatus.due.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get statusDue;

  /// RecurringOccurrenceStatus.paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get statusPaid;

  /// RecurringOccurrenceStatus.dismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get statusDismissed;

  /// RecurringKind.serviceFee — a recurring charge tied to an asset.
  ///
  /// In en, this message translates to:
  /// **'Service fee'**
  String get kindServiceFee;

  /// RecurringKind.other — anything the named kinds do not cover.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get kindOther;

  /// Header above the recurring bills a payment can settle.
  ///
  /// In en, this message translates to:
  /// **'Due now'**
  String get billDueSection;

  /// Opens the template builder from the bill form.
  ///
  /// In en, this message translates to:
  /// **'Set up a recurring bill'**
  String get billSetUpAction;

  /// Shown in the bill form when no occurrence is outstanding.
  ///
  /// In en, this message translates to:
  /// **'Nothing is due right now.'**
  String get billNothingDue;

  /// Snack after a line asked to become recurring.
  ///
  /// In en, this message translates to:
  /// **'Saved. Now set how often it repeats.'**
  String get recurringScheduleNext;

  /// Chip when the next occurrence has not materialised.
  ///
  /// In en, this message translates to:
  /// **'Not due yet'**
  String get recurringNotYetDue;

  /// Precedes the recurring bill this payment will settle.
  ///
  /// In en, this message translates to:
  /// **'Settling'**
  String get billSettlesLabel;

  /// Option that leaves the payment unlinked to any template.
  ///
  /// In en, this message translates to:
  /// **'Not a recurring bill'**
  String get billSettleNone;

  /// Explains that the editor is the single write path for a bill payment.
  ///
  /// In en, this message translates to:
  /// **'Pick one and the amount below becomes what you actually paid. Saving records it once.'**
  String get billSettleHelp;

  /// Helper under the amount when a bill is selected.
  ///
  /// In en, this message translates to:
  /// **'This amount is what gets recorded'**
  String get billAmountBecomesPaid;

  /// Precedes the account resolved automatically for a bill payment.
  ///
  /// In en, this message translates to:
  /// **'Paid from'**
  String get billAccountAuto;

  /// Shown only when no template default, no app default and more than one account exist.
  ///
  /// In en, this message translates to:
  /// **'Which account does this come from? Alaya remembers it on the bill.'**
  String get billAccountAskOnce;

  /// AssetType.appliance group header.
  ///
  /// In en, this message translates to:
  /// **'Appliances'**
  String get assetGroupAppliance;

  /// AssetType.electronics.
  ///
  /// In en, this message translates to:
  /// **'Electronics'**
  String get assetGroupElectronics;

  /// AssetType.vehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicles'**
  String get assetGroupVehicle;

  /// AssetType.furniture.
  ///
  /// In en, this message translates to:
  /// **'Furniture'**
  String get assetGroupFurniture;

  /// AssetType.property.
  ///
  /// In en, this message translates to:
  /// **'Property'**
  String get assetGroupProperty;

  /// AssetType.serviceProvider — a maid or gardener lives here, not in a second system.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get assetGroupServiceProvider;

  /// AssetType.subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get assetGroupSubscription;

  /// AssetType.other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get assetGroupOther;

  /// Chip when warrantyEndDateKey is still ahead.
  ///
  /// In en, this message translates to:
  /// **'In warranty'**
  String get assetUnderWarranty;

  /// Chip when the warranty ends soon.
  ///
  /// In en, this message translates to:
  /// **'Warranty ending'**
  String get assetWarrantyEnding;

  /// Chip when the warranty has passed.
  ///
  /// In en, this message translates to:
  /// **'Out of warranty'**
  String get assetWarrantyExpired;

  /// Chip when nextServiceDueDateKey has passed.
  ///
  /// In en, this message translates to:
  /// **'Service due'**
  String get assetServiceDue;

  /// Chip when a service is close.
  ///
  /// In en, this message translates to:
  /// **'Service soon'**
  String get assetServiceSoon;

  /// Chip on a disposed asset.
  ///
  /// In en, this message translates to:
  /// **'Disposed'**
  String get assetDisposedChip;

  /// AssetStatus.underRepair.
  ///
  /// In en, this message translates to:
  /// **'Being repaired'**
  String get assetUnderRepair;

  /// Filter that brings disposed assets back into the list.
  ///
  /// In en, this message translates to:
  /// **'Include disposed'**
  String get filterShowDisposed;

  /// Asset list empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing tracked yet'**
  String get emptyTitleNoAssets;

  /// Asset list empty state body, stating the serviceProvider case plainly.
  ///
  /// In en, this message translates to:
  /// **'Add an appliance, a vehicle, or the person who helps around the house — they all live here.'**
  String get emptyBodyNoAssets;

  /// Adds an asset.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAsset;

  /// Skeleton label for service surfaces.
  ///
  /// In en, this message translates to:
  /// **'Loading your things'**
  String get loadingAssets;

  /// Identity section on the detail screen.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get assetSectionIdentity;

  /// Warranty section.
  ///
  /// In en, this message translates to:
  /// **'Warranty'**
  String get assetSectionWarranty;

  /// Contact block.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get assetSectionContact;

  /// Service records section.
  ///
  /// In en, this message translates to:
  /// **'Service history'**
  String get assetSectionService;

  /// Service records section for a serviceProvider.
  ///
  /// In en, this message translates to:
  /// **'Salary history'**
  String get assetSectionSalary;

  /// Sum of every service record cost.
  ///
  /// In en, this message translates to:
  /// **'Spent on service so far'**
  String get assetLifetimeCost;

  /// The same figure for a serviceProvider.
  ///
  /// In en, this message translates to:
  /// **'Paid so far'**
  String get assetLifetimeSalary;

  /// assets.brand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get labelBrand;

  /// assets.modelNo.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get labelModelNo;

  /// assets.serialNo.
  ///
  /// In en, this message translates to:
  /// **'Serial'**
  String get labelSerialNo;

  /// assets.purchasePrice.
  ///
  /// In en, this message translates to:
  /// **'Bought for'**
  String get labelPurchasePrice;

  /// assets.warrantyStartDateKey.
  ///
  /// In en, this message translates to:
  /// **'Warranty from'**
  String get labelWarrantyStart;

  /// assets.warrantyEndDateKey.
  ///
  /// In en, this message translates to:
  /// **'Warranty until'**
  String get labelWarrantyEnd;

  /// assets.warrantyProvider.
  ///
  /// In en, this message translates to:
  /// **'Covered by'**
  String get labelWarrantyProvider;

  /// assets.serviceIntervalDays.
  ///
  /// In en, this message translates to:
  /// **'Service every'**
  String get labelServiceInterval;

  /// assets.nextServiceDueDateKey.
  ///
  /// In en, this message translates to:
  /// **'Next service'**
  String get labelNextService;

  /// assets.primaryContactName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get labelContactName;

  /// assets.primaryContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get labelContactPhone;

  /// assets.location.
  ///
  /// In en, this message translates to:
  /// **'Kept in'**
  String get labelLocation;

  /// Dials primaryContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get actionCall;

  /// Shown when the tel: intent finds no handler.
  ///
  /// In en, this message translates to:
  /// **'No app on this phone can place that call.'**
  String get callFailed;

  /// Adds a service record.
  ///
  /// In en, this message translates to:
  /// **'Record a service'**
  String get actionAddService;

  /// The same action for a serviceProvider.
  ///
  /// In en, this message translates to:
  /// **'Record a payment'**
  String get actionAddSalary;

  /// Opens the dispose sheet.
  ///
  /// In en, this message translates to:
  /// **'Dispose of it'**
  String get actionDispose;

  /// Reverses a disposal.
  ///
  /// In en, this message translates to:
  /// **'Bring it back'**
  String get actionUndispose;

  /// Chip when linkedRecurringTemplateId is set.
  ///
  /// In en, this message translates to:
  /// **'Paid on a schedule'**
  String get assetLinkedRecurring;

  /// Empty service history.
  ///
  /// In en, this message translates to:
  /// **'Nothing recorded against this yet.'**
  String get emptyBodyNoServices;

  /// assets.name.
  ///
  /// In en, this message translates to:
  /// **'What is it?'**
  String get labelAssetName;

  /// assets.type.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get labelAssetType;

  /// Explains AssetType.serviceProvider when it is chosen.
  ///
  /// In en, this message translates to:
  /// **'A person you pay regularly belongs here too — their payments become service records.'**
  String get assetTypeHelpPerson;

  /// Commits an asset.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAsset;

  /// Explains serviceIntervalDays.
  ///
  /// In en, this message translates to:
  /// **'Days between services. The next due date moves on each time you record one.'**
  String get serviceIntervalHelp;

  /// service_records.type.
  ///
  /// In en, this message translates to:
  /// **'What happened'**
  String get labelServiceType;

  /// ServiceRecordType.service.
  ///
  /// In en, this message translates to:
  /// **'Serviced'**
  String get serviceTypeService;

  /// ServiceRecordType.repair.
  ///
  /// In en, this message translates to:
  /// **'Repaired'**
  String get serviceTypeRepair;

  /// ServiceRecordType.maintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get serviceTypeMaintenance;

  /// ServiceRecordType.inspection.
  ///
  /// In en, this message translates to:
  /// **'Inspection'**
  String get serviceTypeInspection;

  /// ServiceRecordType.salaryPaid — the maid case.
  ///
  /// In en, this message translates to:
  /// **'Salary paid'**
  String get serviceTypeSalaryPaid;

  /// ServiceRecordType.other.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get serviceTypeOther;

  /// service_records.providerName.
  ///
  /// In en, this message translates to:
  /// **'Who did it'**
  String get labelProviderName;

  /// service_records.providerPhone.
  ///
  /// In en, this message translates to:
  /// **'Their number'**
  String get labelProviderPhone;

  /// service_records.serviceDateKey.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get labelServiceDate;

  /// service_records.cost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get labelServiceCost;

  /// service_records.nextDueDateKey.
  ///
  /// In en, this message translates to:
  /// **'Next one due'**
  String get labelNextDue;

  /// The alsoRecordAsExpense toggle.
  ///
  /// In en, this message translates to:
  /// **'Also record it as an expense'**
  String get alsoRecordAsExpense;

  /// Explains what the toggle writes.
  ///
  /// In en, this message translates to:
  /// **'Writes a withdrawal for the cost as well, so it shows in your ledger.'**
  String get alsoRecordHelp;

  /// Rejection when the toggle is on with no account.
  ///
  /// In en, this message translates to:
  /// **'Choose which account it comes from'**
  String get alsoRecordNeedsAccount;

  /// Rejection when the toggle is on with no cost.
  ///
  /// In en, this message translates to:
  /// **'Add a cost first'**
  String get alsoRecordNeedsCost;

  /// Commits a service record.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveService;

  /// Dispose sheet title.
  ///
  /// In en, this message translates to:
  /// **'What happened to it?'**
  String get disposeTitle;

  /// States anomaly A30 plainly: an asset is never deleted.
  ///
  /// In en, this message translates to:
  /// **'It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.'**
  String get disposeBody;

  /// AssetDisposalReason.sold.
  ///
  /// In en, this message translates to:
  /// **'Sold it'**
  String get disposeReasonSold;

  /// AssetDisposalReason.expired.
  ///
  /// In en, this message translates to:
  /// **'Wore out'**
  String get disposeReasonExpired;

  /// AssetDisposalReason.damaged.
  ///
  /// In en, this message translates to:
  /// **'Broke'**
  String get disposeReasonDamaged;

  /// AssetDisposalReason.gifted.
  ///
  /// In en, this message translates to:
  /// **'Gave it away'**
  String get disposeReasonGifted;

  /// AssetDisposalReason.lost.
  ///
  /// In en, this message translates to:
  /// **'Lost it'**
  String get disposeReasonLost;

  /// AssetDisposalReason.replaced.
  ///
  /// In en, this message translates to:
  /// **'Replaced it'**
  String get disposeReasonReplaced;

  /// AssetDisposalReason.other.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get disposeReasonOther;

  /// assets.disposalAmount — what the disposal recovered.
  ///
  /// In en, this message translates to:
  /// **'Got back'**
  String get labelDisposalAmount;

  /// assets.disposedAtDateKey.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get labelDisposalDate;

  /// Commits the disposal.
  ///
  /// In en, this message translates to:
  /// **'Record it'**
  String get disposeCommit;

  /// Snack after disposing.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get disposeDone;

  /// Snack after un-disposing.
  ///
  /// In en, this message translates to:
  /// **'Back in your list'**
  String get undisposeDone;

  /// Rejection when no reason is chosen.
  ///
  /// In en, this message translates to:
  /// **'Pick what happened'**
  String get disposeNeedsReason;

  /// Search hint on the asset list.
  ///
  /// In en, this message translates to:
  /// **'Search your things and people'**
  String get hintSearchAssets;

  /// Field error when warrantyEndDateKey precedes warrantyStartDateKey.
  ///
  /// In en, this message translates to:
  /// **'The warranty cannot end before it starts'**
  String get errorWarrantyBackwards;

  /// Header above the cost and expense controls on the service editor.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get sectionMoney;

  /// Snack after a purchase line created an asset.
  ///
  /// In en, this message translates to:
  /// **'Saved. Now say what it is and how long it is covered.'**
  String get assetCreatedFromPurchase;

  /// Explains destination none.
  ///
  /// In en, this message translates to:
  /// **'Recorded as spending and nothing else.'**
  String get destinationHelpNone;

  /// Explains destination inventory.
  ///
  /// In en, this message translates to:
  /// **'Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.'**
  String get destinationHelpInventory;

  /// Explains destination asset.
  ///
  /// In en, this message translates to:
  /// **'A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.'**
  String get destinationHelpAsset;

  /// Explains destination recurring.
  ///
  /// In en, this message translates to:
  /// **'Sets up a schedule so this comes back every month.'**
  String get destinationHelpRecurring;

  /// Informational note when an asset name repeats. Never a block: five iPhones are five assets.
  ///
  /// In en, this message translates to:
  /// **'You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.'**
  String get assetSameNameNote;

  /// Snack action opening the asset a purchase line created.
  ///
  /// In en, this message translates to:
  /// **'Set the warranty'**
  String get actionSetWarranty;

  /// Optional payment method on the service editor. Travels to the expense, never onto the record.
  ///
  /// In en, this message translates to:
  /// **'How you paid (optional)'**
  String get labelPaymentMethodOptional;

  /// Dashboard screen title.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get dashboardTitle;

  /// Label above the one headline figure on the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Total available funds'**
  String get fundsAvailable;

  /// Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 balance not converted} other{{count} balances not converted}}'**
  String fundsUnconverted(num count);

  /// Chip when the conversion used the most recent rate on or before today.
  ///
  /// In en, this message translates to:
  /// **'Rate is older than today'**
  String get fundsApproximate;

  /// Explains why the headline may be lower than the sum of every account.
  ///
  /// In en, this message translates to:
  /// **'Balances Alaya has no rate for are left out rather than guessed at.'**
  String get fundsWhyExcluded;

  /// Range label. Always stated, never implied (anomaly A33).
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get rangeLast30;

  /// Deposits over the labelled range.
  ///
  /// In en, this message translates to:
  /// **'In'**
  String get rangeMoneyIn;

  /// Withdrawals over the labelled range.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get rangeMoneyOut;

  /// Shown in place of a figure when a range holds no transactions.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get rangeNothingYet;

  /// Chip when transactions in a foreign currency could not be converted into the range total.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 left out} other{{count} left out}}'**
  String rangeExcluded(num count);

  /// The calendar side of the switchable insight card.
  ///
  /// In en, this message translates to:
  /// **'Coming up'**
  String get insightUpcoming;

  /// The analytics side of the switchable insight card.
  ///
  /// In en, this message translates to:
  /// **'Where it went'**
  String get insightSpending;

  /// Semantics label for the insight card switch.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get insightSwitchLabel;

  /// Empty state for the upcoming side.
  ///
  /// In en, this message translates to:
  /// **'Nothing needs attention in the next fortnight.'**
  String get insightNothingUpcoming;

  /// Upcoming row for a recurring occurrence.
  ///
  /// In en, this message translates to:
  /// **'Bill due'**
  String get insightBillDue;

  /// Upcoming row for an asset needing service.
  ///
  /// In en, this message translates to:
  /// **'Service due'**
  String get insightServiceDue;

  /// Upcoming row for an expiring warranty.
  ///
  /// In en, this message translates to:
  /// **'Warranty ending'**
  String get insightWarrantyEnding;

  /// Upcoming row for a batch past or near its expiry.
  ///
  /// In en, this message translates to:
  /// **'Expiring'**
  String get insightBatchExpiring;

  /// Header above the navigation tiles.
  ///
  /// In en, this message translates to:
  /// **'Where to next'**
  String get moduleGridTitle;

  /// Live number on the Expenses tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}'**
  String moduleExpenses(num count);

  /// Live number on the Inventory tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}'**
  String moduleInventory(num count);

  /// Live number on the Shopping tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}'**
  String moduleShopping(num count);

  /// Live number on the Recurring tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{all settled} =1{1 due} other{{count} due}}'**
  String moduleRecurring(num count);

  /// Live number on the Services tile.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}'**
  String moduleServices(num count);

  /// FAB action opening the editor as a deposit.
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get fabAddIncome;

  /// FAB action opening the item editor.
  ///
  /// In en, this message translates to:
  /// **'New item'**
  String get fabAddItem;

  /// Skeleton label for the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Adding it up'**
  String get loadingDashboard;

  /// Semantics label for the closed expandable FAB.
  ///
  /// In en, this message translates to:
  /// **'Add something'**
  String get fabOpenLabel;

  /// Semantics label for the open expandable FAB.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get fabCloseLabel;

  /// No description provided for @eventTypeTransaction.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get eventTypeTransaction;

  /// No description provided for @eventTypeRecurringDue.
  ///
  /// In en, this message translates to:
  /// **'Recurring bill'**
  String get eventTypeRecurringDue;

  /// No description provided for @eventTypeBatchExpiry.
  ///
  /// In en, this message translates to:
  /// **'Expiring'**
  String get eventTypeBatchExpiry;

  /// No description provided for @eventTypeWarrantyEnd.
  ///
  /// In en, this message translates to:
  /// **'Warranty ending'**
  String get eventTypeWarrantyEnd;

  /// No description provided for @eventTypeServiceDue.
  ///
  /// In en, this message translates to:
  /// **'Service due'**
  String get eventTypeServiceDue;

  /// No description provided for @eventTypeShoppingTarget.
  ///
  /// In en, this message translates to:
  /// **'Shopping target'**
  String get eventTypeShoppingTarget;

  /// No description provided for @calendarSeverityWarning.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get calendarSeverityWarning;

  /// No description provided for @calendarSeverityDanger.
  ///
  /// In en, this message translates to:
  /// **'Past its date'**
  String get calendarSeverityDanger;

  /// No description provided for @calendarLoadingDay.
  ///
  /// In en, this message translates to:
  /// **'Loading this day…'**
  String get calendarLoadingDay;

  /// No description provided for @calendarDayErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load this day'**
  String get calendarDayErrorTitle;

  /// No description provided for @calendarDayEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing on this day'**
  String get calendarDayEmptyTitle;

  /// No description provided for @calendarDayEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No transactions, bills, expiries or services fall here.'**
  String get calendarDayEmptyBody;

  /// No description provided for @calendarRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get calendarRetry;

  /// No description provided for @calendarLoadingMonth.
  ///
  /// In en, this message translates to:
  /// **'Loading this month…'**
  String get calendarLoadingMonth;

  /// No description provided for @calendarErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not load the calendar'**
  String get calendarErrorTitle;

  /// No description provided for @calendarPreviousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get calendarPreviousMonth;

  /// No description provided for @calendarNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get calendarNextMonth;

  /// No description provided for @calendarOnDay.
  ///
  /// In en, this message translates to:
  /// **'On this day'**
  String get calendarOnDay;

  /// No description provided for @calendarRangeOn.
  ///
  /// In en, this message translates to:
  /// **'Select a range'**
  String get calendarRangeOn;

  /// No description provided for @calendarRangeOff.
  ///
  /// In en, this message translates to:
  /// **'Stop selecting a range'**
  String get calendarRangeOff;

  /// Prompt after the range start is chosen.
  ///
  /// In en, this message translates to:
  /// **'From {start} — tap another day to finish.'**
  String calendarRangePickEnd(String start);

  /// How many days the chosen range spans.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String calendarInRange(int count);

  /// No description provided for @calendarRangeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing in these days'**
  String get calendarRangeEmptyTitle;

  /// No description provided for @calendarRangeEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'No transactions, bills, expiries or services fall inside the range.'**
  String get calendarRangeEmptyBody;

  /// No description provided for @calendarBackToToday.
  ///
  /// In en, this message translates to:
  /// **'Back to this month'**
  String get calendarBackToToday;

  /// No description provided for @calendarTotalOut.
  ///
  /// In en, this message translates to:
  /// **'Spent'**
  String get calendarTotalOut;

  /// No description provided for @calendarTotalIn.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get calendarTotalIn;

  /// No description provided for @dashboardOpenCalendar.
  ///
  /// In en, this message translates to:
  /// **'Open calendar'**
  String get dashboardOpenCalendar;

  /// Screen-reader label for the dashboard month card where days are too narrow to tap.
  ///
  /// In en, this message translates to:
  /// **'{month} at a glance. Opens the calendar.'**
  String dashboardCalendarSemantics(String month);

  /// No description provided for @navBackToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Back to dashboard'**
  String get navBackToDashboard;

  /// Shown in a ChartCard while its figure computes. A line rather than a spinner: a card about to hold a chart reads as slow behind one (ARCH_5 §5.2).
  ///
  /// In en, this message translates to:
  /// **'Working it out…'**
  String get chartLoading;

  /// How many of a series' data points converted against a rate from a different day (ARCH_3 §1.3). Says what it means rather than naming the rate quality.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 figure is indicative} other{{count} figures are indicative}}'**
  String chartApproximate(num count);

  /// How many amounts had no usable rate and are excluded from the figure, never counted as zero (anomaly A15).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 amount left out} other{{count} amounts left out}}'**
  String chartUnconverted(num count);

  /// Label above the analytics screen's one displayAmount.
  ///
  /// In en, this message translates to:
  /// **'Spent'**
  String get analyticsTotalSpent;

  /// Semantics label for the range chip row.
  ///
  /// In en, this message translates to:
  /// **'Reporting window'**
  String get analyticsRangeLabel;

  /// Period-over-period comparison, rising. The window compared against is the same length, not a calendar month.
  ///
  /// In en, this message translates to:
  /// **'{percent} more than the window before'**
  String analyticsComparisonUp(Object percent);

  /// Period-over-period comparison, falling.
  ///
  /// In en, this message translates to:
  /// **'{percent} less than the window before'**
  String analyticsComparisonDown(Object percent);

  /// The app-wide unconverted count, distinct from one figure's own exclusions. A transaction outside the window can still be unconvertible.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 amount needs a rate} other{{count} amounts need a rate}}'**
  String analyticsUnconvertedTotal(num count);

  /// Title of the personal-inflation card, queries 12 and 24.
  ///
  /// In en, this message translates to:
  /// **'Your own inflation'**
  String get analyticsInflationTitle;

  /// Explains that the trend is per base unit, so 2 kg and 500 g are comparable.
  ///
  /// In en, this message translates to:
  /// **'What one thing costs you, purchase by purchase'**
  String get analyticsInflationSubtitle;

  /// The personal-inflation sentence, rising. The date is rendered separately through DateText (Law U7).
  ///
  /// In en, this message translates to:
  /// **'{percent} more than the first time in this window'**
  String analyticsInflationUp(Object percent);

  /// The personal-inflation sentence, falling.
  ///
  /// In en, this message translates to:
  /// **'{percent} less than the first time in this window'**
  String analyticsInflationDown(Object percent);

  /// Precedes a DateText giving the earliest purchase in the window.
  ///
  /// In en, this message translates to:
  /// **'First bought'**
  String get analyticsInflationSince;

  /// Empty state: fewer than two priced purchases means there is no trend to draw. Names both ways out.
  ///
  /// In en, this message translates to:
  /// **'Buy something twice and its price trend appears here. Widen the window if you have.'**
  String get analyticsInflationEmpty;

  /// Section header over the spend breakdowns.
  ///
  /// In en, this message translates to:
  /// **'Where it went'**
  String get analyticsSectionSpend;

  /// Section header over the trends.
  ///
  /// In en, this message translates to:
  /// **'Over time'**
  String get analyticsSectionTime;

  /// Section header over payees and items.
  ///
  /// In en, this message translates to:
  /// **'Who and what'**
  String get analyticsSectionWhat;

  /// Section header over stock, waste and expiry.
  ///
  /// In en, this message translates to:
  /// **'Your home'**
  String get analyticsSectionHome;

  /// Section header over recurring commitments and assets.
  ///
  /// In en, this message translates to:
  /// **'Already committed'**
  String get analyticsSectionCommitments;

  /// Query 1. "Kind" rather than "subtype": the schema's word is not the user's.
  ///
  /// In en, this message translates to:
  /// **'By kind'**
  String get analyticsBySubtype;

  /// Query 2.
  ///
  /// In en, this message translates to:
  /// **'By tag'**
  String get analyticsByTag;

  /// The caveat belongs on the card: a reader comparing tag figures against the headline deserves to know why they differ.
  ///
  /// In en, this message translates to:
  /// **'A purchase with two tags counts in both, so these add up to more than the total'**
  String get analyticsByTagNote;

  /// Query 3.
  ///
  /// In en, this message translates to:
  /// **'By payment method'**
  String get analyticsByMethod;

  /// Query 22, with query 8's grocery share beneath it.
  ///
  /// In en, this message translates to:
  /// **'How concentrated'**
  String get analyticsConcentration;

  /// Query 22's headline.
  ///
  /// In en, this message translates to:
  /// **'{percent} of your spending sits in three kinds'**
  String analyticsTopShare(Object percent);

  /// Query 8, stated beneath the concentration figure.
  ///
  /// In en, this message translates to:
  /// **'Groceries are {percent} of it'**
  String analyticsGroceryShare(Object percent);

  /// Marks a parent tag that can be opened. One level only, which is all the schema permits.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 tag inside} other{{count} tags inside}}'**
  String analyticsTagChildren(num count);

  /// The parent tag's own spending, as a sibling of its children rather than folded into them.
  ///
  /// In en, this message translates to:
  /// **'{tag} on its own'**
  String analyticsTagDirect(Object tag);

  /// Tooltip on the in-place drill's back button.
  ///
  /// In en, this message translates to:
  /// **'Back to all tags'**
  String get analyticsTagBack;

  /// Empty state for a spend breakdown.
  ///
  /// In en, this message translates to:
  /// **'Nothing spent in this window'**
  String get analyticsNothingSpent;

  /// Empty state for the tag breakdown: names the action, not the absence.
  ///
  /// In en, this message translates to:
  /// **'Tag a purchase and it will appear here'**
  String get analyticsNoTaggedSpend;

  /// Empty state for the payment-method breakdown.
  ///
  /// In en, this message translates to:
  /// **'Record how you paid and it will appear here'**
  String get analyticsNoMethodSpend;

  /// Query 5.
  ///
  /// In en, this message translates to:
  /// **'In and out'**
  String get analyticsIncomeVsExpense;

  /// Empty state: one month is a pair of figures, not a trend.
  ///
  /// In en, this message translates to:
  /// **'Two months of records and the trend appears here'**
  String get analyticsNeedTwoMonths;

  /// Query 6. Named for what the figure means rather than for the ledger it comes from.
  ///
  /// In en, this message translates to:
  /// **'What you kept'**
  String get analyticsNetFlow;

  /// Explains why a transfer is absent: the ledger nets it to zero across its two legs.
  ///
  /// In en, this message translates to:
  /// **'Moving money between your own accounts does not count'**
  String get analyticsNetFlowNote;

  /// Empty state for net flow.
  ///
  /// In en, this message translates to:
  /// **'Nothing moved in this window'**
  String get analyticsNoFlow;

  /// Query 7.
  ///
  /// In en, this message translates to:
  /// **'Balance over time'**
  String get analyticsBalanceTrend;

  /// Names the account and its currency: this is the one figure on the screen not in the home currency, because converting each point would make the line move when rates moved.
  ///
  /// In en, this message translates to:
  /// **'{account}, in {currency}'**
  String analyticsBalanceIn(Object account, Object currency);

  /// Label on the balance-trend account picker.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get analyticsAccount;

  /// Empty state for the balance trend.
  ///
  /// In en, this message translates to:
  /// **'No movement on this account in this window'**
  String get analyticsNoBalanceMovement;

  /// Query 21.
  ///
  /// In en, this message translates to:
  /// **'When you spend'**
  String get analyticsHeatmap;

  /// Heatmap segment.
  ///
  /// In en, this message translates to:
  /// **'By day of week'**
  String get analyticsByWeekday;

  /// Heatmap segment.
  ///
  /// In en, this message translates to:
  /// **'By date'**
  String get analyticsByDayOfMonth;

  /// Query 4.
  ///
  /// In en, this message translates to:
  /// **'Who you paid most'**
  String get analyticsTopPayees;

  /// Empty state for top payees.
  ///
  /// In en, this message translates to:
  /// **'Name who you paid and they will appear here'**
  String get analyticsNoPayees;

  /// Query 9.
  ///
  /// In en, this message translates to:
  /// **'What cost you most'**
  String get analyticsTopItems;

  /// Empty state for top items by spend.
  ///
  /// In en, this message translates to:
  /// **'Itemise a purchase and it will appear here'**
  String get analyticsNoItemisedSpend;

  /// Query 10.
  ///
  /// In en, this message translates to:
  /// **'What you buy most of'**
  String get analyticsTopByQuantity;

  /// Explains the grouping: Law L8 makes cross-category comparison meaningless.
  ///
  /// In en, this message translates to:
  /// **'Grouped by measure, because weight and count cannot be compared'**
  String get analyticsTopByQuantityNote;

  /// Empty state for top items by quantity.
  ///
  /// In en, this message translates to:
  /// **'Record how much you bought and it will appear here'**
  String get analyticsNoQuantities;

  /// How many times an item was bought in the window.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 purchase} other{{count} purchases}}'**
  String analyticsPurchaseCount(num count);

  /// Query 11.
  ///
  /// In en, this message translates to:
  /// **'The most you have paid'**
  String get analyticsDearest;

  /// Key on the dearest-purchase card.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get analyticsDearestItem;

  /// Key on the dearest-purchase card. The figure is in the currency it was bought in, unconverted.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get analyticsDearestPrice;

  /// Key on the dearest-purchase card, paired with a DateText.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get analyticsDearestWhen;

  /// Empty state for the dearest purchase.
  ///
  /// In en, this message translates to:
  /// **'Record a unit price and this appears here'**
  String get analyticsNoUnitPrices;

  /// Query 23.
  ///
  /// In en, this message translates to:
  /// **'Your average shop'**
  String get analyticsAverageBasket;

  /// Key on the basket card.
  ///
  /// In en, this message translates to:
  /// **'Average value'**
  String get analyticsBasketValue;

  /// Key on the basket card.
  ///
  /// In en, this message translates to:
  /// **'Average items'**
  String get analyticsBasketLines;

  /// Key on the basket card. Counts the baskets that converted, which is what the average divides by.
  ///
  /// In en, this message translates to:
  /// **'Shops counted'**
  String get analyticsBasketCount;

  /// Empty state for the basket card.
  ///
  /// In en, this message translates to:
  /// **'Record a grocery shop and it will appear here'**
  String get analyticsNoBaskets;

  /// Query 13.
  ///
  /// In en, this message translates to:
  /// **'What is on your shelves'**
  String get analyticsInventoryValue;

  /// Explains why the range chip does not change this figure.
  ///
  /// In en, this message translates to:
  /// **'Right now, whatever window you have chosen'**
  String get analyticsInventoryValueNote;

  /// How many batches had both a cost and a resolvable purchase unit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 batch valued} other{{count} batches valued}}'**
  String analyticsBatchesValued(num count);

  /// Uncosted stock, reported rather than omitted: a valuation that skipped it would look complete while understating the shelf.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 batch has no cost} other{{count} batches have no cost}}'**
  String analyticsBatchesNoCost(num count);

  /// Empty state for the inventory valuation.
  ///
  /// In en, this message translates to:
  /// **'Record what a batch cost and its value appears here'**
  String get analyticsNoStockValue;

  /// Query 14, one of the app's differentiating insights.
  ///
  /// In en, this message translates to:
  /// **'What you threw away'**
  String get analyticsWaste;

  /// Empty state, and it is good news: worded as a fact rather than as missing data.
  ///
  /// In en, this message translates to:
  /// **'Nothing wasted in this window'**
  String get analyticsNoWaste;

  /// Query 15.
  ///
  /// In en, this message translates to:
  /// **'Expiring within {days} days'**
  String analyticsExpiring(int days);

  /// Empty state for the expiry card.
  ///
  /// In en, this message translates to:
  /// **'Nothing expires soon'**
  String get analyticsNothingExpiring;

  /// How long a batch has. Paired with a tone, because colour is never the only signal (Law U17).
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day left} other{{days} days left}}'**
  String analyticsDaysLeft(num days);

  /// Chip on a batch whose expiry has passed and still holds stock.
  ///
  /// In en, this message translates to:
  /// **'Past its date'**
  String get analyticsExpiredAlready;

  /// Query 16.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get analyticsLowStock;

  /// Explains why this is one figure rather than a trend.
  ///
  /// In en, this message translates to:
  /// **'A count for today, not a history: stock levels are not kept over time'**
  String get analyticsLowStockNote;

  /// Query 16's figure.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item below its threshold} other{{count} items below their threshold}}'**
  String analyticsLowStockCount(num count);

  /// Precedes a DateText on the low-stock count.
  ///
  /// In en, this message translates to:
  /// **'As of'**
  String get analyticsAsOf;

  /// Empty state for the low-stock card.
  ///
  /// In en, this message translates to:
  /// **'Nothing is running low'**
  String get analyticsNothingLow;

  /// Query 17.
  ///
  /// In en, this message translates to:
  /// **'Every month, before anything else'**
  String get analyticsCommitment;

  /// Explains the outflow-only filter: netting salary against rent would report a household as having no fixed costs.
  ///
  /// In en, this message translates to:
  /// **'Bills and subscriptions only. Income is not netted off'**
  String get analyticsCommitmentNote;

  /// How many active templates the monthly figure covers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{from 1 commitment} other{from {count} commitments}}'**
  String analyticsCommitmentCount(num count);

  /// Empty state for the commitment total.
  ///
  /// In en, this message translates to:
  /// **'Add a bill or subscription and it will appear here'**
  String get analyticsNoCommitments;

  /// Query 18.
  ///
  /// In en, this message translates to:
  /// **'Fixed against chosen'**
  String get analyticsRecurringSplit;

  /// Query 18's recurring side. The user's word, not the schema's.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get analyticsRecurring;

  /// Query 18's discretionary side.
  ///
  /// In en, this message translates to:
  /// **'Chosen'**
  String get analyticsDiscretionary;

  /// Query 18's headline.
  ///
  /// In en, this message translates to:
  /// **'{percent} of your spending was already committed'**
  String analyticsRecurringShare(Object percent);

  /// Query 19. Includes disposed assets, which is the point of a status change rather than a delete.
  ///
  /// In en, this message translates to:
  /// **'What your things cost to keep'**
  String get analyticsServiceCost;

  /// How many service records an asset has in the window.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 visit} other{{count} visits}}'**
  String analyticsServiceCount(num count);

  /// Empty state for the service-cost card.
  ///
  /// In en, this message translates to:
  /// **'Record a service or repair and it will appear here'**
  String get analyticsNoServiceCost;

  /// Query 20.
  ///
  /// In en, this message translates to:
  /// **'Warranties'**
  String get analyticsWarranty;

  /// Chip on an asset still inside its warranty window.
  ///
  /// In en, this message translates to:
  /// **'Covered'**
  String get analyticsCovered;

  /// Chip on an asset whose warranty has run out.
  ///
  /// In en, this message translates to:
  /// **'Cover ended'**
  String get analyticsCoverageEnded;

  /// Empty state for the warranty card.
  ///
  /// In en, this message translates to:
  /// **'Add a warranty date and it will appear here'**
  String get analyticsNoWarranties;

  /// Screen-level empty state. The house section stays visible beneath it, because stock is a "right now" figure.
  ///
  /// In en, this message translates to:
  /// **'Nothing to show for this window'**
  String get analyticsEmptyTitle;

  /// Names both ways out: on a fresh install the second is the answer, on a quiet month the first is.
  ///
  /// In en, this message translates to:
  /// **'Widen the window above, or record something and it will appear here.'**
  String get analyticsEmptyBody;

  /// The clear-cache action, named for what the reader gets rather than for the table it empties.
  ///
  /// In en, this message translates to:
  /// **'Recalculate everything'**
  String get analyticsCacheClear;

  /// The action's in-progress label.
  ///
  /// In en, this message translates to:
  /// **'Recalculating…'**
  String get analyticsCacheClearing;

  /// Explains what the action does. The only place analytics_cache is ever visible (ARCH_5 §7.3).
  ///
  /// In en, this message translates to:
  /// **'Some figures are kept between visits so this screen opens quickly. Clear them if a number looks stale.'**
  String get analyticsCacheExplain;

  /// Precedes a DateText giving when the cache was last cleared.
  ///
  /// In en, this message translates to:
  /// **'Recalculated'**
  String get analyticsCacheCleared;

  /// Success snack. Same word as the button, per ARCH_5 §2.8.
  ///
  /// In en, this message translates to:
  /// **'Figures recalculated'**
  String get analyticsCacheClearedSnack;

  /// Failure snack. Names what failed rather than apologising.
  ///
  /// In en, this message translates to:
  /// **'Could not clear the saved figures'**
  String get analyticsCacheFailed;

  /// Fallback title for the drill-down while its label resolves.
  ///
  /// In en, this message translates to:
  /// **'Behind this figure'**
  String get analyticsDrillTitle;

  /// Precedes the drill-down's per-currency subtotals.
  ///
  /// In en, this message translates to:
  /// **'These come to'**
  String get analyticsDrillTotal;

  /// Semantics label on the drill-down's skeleton.
  ///
  /// In en, this message translates to:
  /// **'Loading these transactions…'**
  String get analyticsDrillLoading;

  /// Drill-down empty state.
  ///
  /// In en, this message translates to:
  /// **'Nothing here in this window'**
  String get analyticsDrillEmptyTitle;

  /// Names the likely cause: the filter is what the reader just chose, the window is what they may have forgotten.
  ///
  /// In en, this message translates to:
  /// **'The window is set on the insights screen. Widen it and these may appear.'**
  String get analyticsDrillEmptyBody;

  /// Shown when the route's parameters name no filter this version knows.
  ///
  /// In en, this message translates to:
  /// **'This link does not point anywhere'**
  String get analyticsDrillUnknownTitle;

  /// Offers the way on rather than throwing: the route is reachable from outside the app.
  ///
  /// In en, this message translates to:
  /// **'Open insights and choose a figure to look behind.'**
  String get analyticsDrillUnknownBody;

  /// The grouped remainder wedge of a donut, past the sixth slice. A ring of twelve slivers is not readable, so the tail becomes one wedge that says what it is.
  ///
  /// In en, this message translates to:
  /// **'Everything else'**
  String get analyticsOtherSlices;

  /// The quiet line under the percentage in the concentration donut's centre, saying what that percentage is of.
  ///
  /// In en, this message translates to:
  /// **'in three kinds'**
  String get analyticsTopThree;

  /// No description provided for @aboutHowItWorksHeader.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get aboutHowItWorksHeader;

  /// No description provided for @aboutLicences.
  ///
  /// In en, this message translates to:
  /// **'Open source licences'**
  String get aboutLicences;

  /// No description provided for @aboutLicencesHelp.
  ///
  /// In en, this message translates to:
  /// **'The libraries Alaya is built on.'**
  String get aboutLicencesHelp;

  /// No description provided for @aboutOfflineBody.
  ///
  /// In en, this message translates to:
  /// **'Everything is stored on this device. Alaya only reaches the internet to fetch exchange rates, once a day.'**
  String get aboutOfflineBody;

  /// The same threat model the lock screen states, in the place somebody comes looking for it. Two locations is not duplication: one is a decision point, the other is where a question gets answered.
  ///
  /// In en, this message translates to:
  /// **'Your data is not encrypted, and no copy of it exists anywhere else unless you make a backup yourself.'**
  String get aboutStorageBody;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'A finance and home manager that works entirely on your phone.'**
  String get aboutTagline;

  /// No description provided for @accountCurrencyHeader.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get accountCurrencyHeader;

  /// Law L9 at its sharpest: the home currency is a display choice, but an account’s own currency is what its money is.
  ///
  /// In en, this message translates to:
  /// **'Fixed, because changing it would reinterpret every amount already recorded here.'**
  String get accountCurrencyLockedHelp;

  /// No description provided for @accountCurrencyNewHelp.
  ///
  /// In en, this message translates to:
  /// **'What this account holds. It cannot be changed once you start recording against it.'**
  String get accountCurrencyNewHelp;

  /// No description provided for @accountEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get accountEditorEditTitle;

  /// Names the thing, per archetype B — never a bare "Save".
  ///
  /// In en, this message translates to:
  /// **'Save account'**
  String get accountEditorSave;

  /// No description provided for @accountEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get accountEditorTitle;

  /// No description provided for @accountIncludeInNetWorth.
  ///
  /// In en, this message translates to:
  /// **'Count in net worth'**
  String get accountIncludeInNetWorth;

  /// ARCH_5 §7.2 requires the toggle be explained: without this line the reader cannot tell whether off means hidden or merely uncounted.
  ///
  /// In en, this message translates to:
  /// **'Off means the balance still shows here, but is left out of your total. Useful for an account you hold for someone else.'**
  String get accountIncludeInNetWorthHelp;

  /// No description provided for @accountKindBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get accountKindBank;

  /// No description provided for @accountKindCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get accountKindCard;

  /// No description provided for @accountKindCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get accountKindCash;

  /// No description provided for @accountKindHeader.
  ///
  /// In en, this message translates to:
  /// **'What kind?'**
  String get accountKindHeader;

  /// No description provided for @accountKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get accountKindOther;

  /// No description provided for @accountKindWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get accountKindWallet;

  /// No description provided for @accountNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get accountNameLabel;

  /// No description provided for @accountOpeningBalanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get accountOpeningBalanceLabel;

  /// Not "date": the question is which day the balance was correct, and "date" invites today by default.
  ///
  /// In en, this message translates to:
  /// **'True on'**
  String get accountOpeningDateLabel;

  /// No description provided for @accountsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get accountsAdd;

  /// No description provided for @accountsArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive this account'**
  String get accountsArchive;

  /// No description provided for @accountsArchiveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It will stop appearing when you record anything. Its history stays, and you can restore it here at any time.'**
  String get accountsArchiveConfirmBody;

  /// No description provided for @accountsArchiveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive this account?'**
  String get accountsArchiveConfirmTitle;

  /// Says what survives, because "archive" does not tell the reader whether their transactions go with it.
  ///
  /// In en, this message translates to:
  /// **'An archived account keeps all its history. It just stops appearing when you record something.'**
  String get accountsArchiveHelp;

  /// No description provided for @accountsArchived.
  ///
  /// In en, this message translates to:
  /// **'Account archived'**
  String get accountsArchived;

  /// No description provided for @accountsArchivedChip.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get accountsArchivedChip;

  /// No description provided for @accountsArchivedHeader.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get accountsArchivedHeader;

  /// No description provided for @accountsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add one so Alaya knows where your money is.'**
  String get accountsEmptyBody;

  /// No description provided for @accountsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get accountsEmptyTitle;

  /// No description provided for @accountsExcludedChip.
  ///
  /// In en, this message translates to:
  /// **'Not in net worth'**
  String get accountsExcludedChip;

  /// No description provided for @accountsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your accounts…'**
  String get accountsLoading;

  /// A stale deep link, or a row removed in another window. Stated rather than rendering a blank form that would silently create a second account on save.
  ///
  /// In en, this message translates to:
  /// **'It may have been removed. Go back and pick another.'**
  String get accountsMissingBody;

  /// No description provided for @accountsMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'That account is not here'**
  String get accountsMissingTitle;

  /// No description provided for @accountsRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore this account'**
  String get accountsRestore;

  /// Confirmed in both directions: restoring puts an account back into every picker, which is worth stating before it happens.
  ///
  /// In en, this message translates to:
  /// **'It will appear again everywhere you choose an account.'**
  String get accountsRestoreConfirmBody;

  /// No description provided for @accountsRestoreConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore this account?'**
  String get accountsRestoreConfirmTitle;

  /// No description provided for @accountsRestored.
  ///
  /// In en, this message translates to:
  /// **'Account restored'**
  String get accountsRestored;

  /// No description provided for @accountsSaved.
  ///
  /// In en, this message translates to:
  /// **'Account saved'**
  String get accountsSaved;

  /// No description provided for @actionBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get actionBack;

  /// No description provided for @actionContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get actionContinue;

  /// No description provided for @appearanceModeDark.
  ///
  /// In en, this message translates to:
  /// **'Always dark'**
  String get appearanceModeDark;

  /// No description provided for @appearanceModeHeader.
  ///
  /// In en, this message translates to:
  /// **'Light or dark'**
  String get appearanceModeHeader;

  /// No description provided for @appearanceModeLight.
  ///
  /// In en, this message translates to:
  /// **'Always light'**
  String get appearanceModeLight;

  /// No description provided for @appearanceModeSystem.
  ///
  /// In en, this message translates to:
  /// **'Match my phone'**
  String get appearanceModeSystem;

  /// No description provided for @appearanceModeSystemHelp.
  ///
  /// In en, this message translates to:
  /// **'Follows your phone’s light and dark setting.'**
  String get appearanceModeSystemHelp;

  /// No description provided for @appearancePaletteHeader.
  ///
  /// In en, this message translates to:
  /// **'Colours'**
  String get appearancePaletteHeader;

  /// No description provided for @appearanceThemeLabHelp.
  ///
  /// In en, this message translates to:
  /// **'See every colour, spacing and text style the app uses.'**
  String get appearanceThemeLabHelp;

  /// ARCH_3 §3.4 verbatim, on every export confirmation — not in settings, not a tooltip. Corrected in 8B: the 8A wording was a paraphrase that dropped the third sentence.
  ///
  /// In en, this message translates to:
  /// **'This backup is not encrypted. Anyone who opens this file can read every transaction, balance and account name. Only share it somewhere you trust.'**
  String get backupNotEncryptedWarning;

  /// Law L9: disabling it would leave the dashboard with no currency to aggregate into. Disabled rather than hidden, so it reads as an explanation and not a rendering fault.
  ///
  /// In en, this message translates to:
  /// **'Cannot be turned off — your totals are added up in this.'**
  String get currenciesHomeLocked;

  /// No description provided for @currenciesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading currencies…'**
  String get currenciesLoading;

  /// No description provided for @currenciesToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be changed'**
  String get currenciesToggleFailed;

  /// No description provided for @dataBackupHeader.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get dataBackupHeader;

  /// No description provided for @dataExportBody.
  ///
  /// In en, this message translates to:
  /// **'Sends a copy of your data to WhatsApp, Drive, or anywhere else you choose.'**
  String get dataExportBody;

  /// No description provided for @dataExportConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Share it'**
  String get dataExportConfirmAction;

  /// No description provided for @dataExportConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Share a backup?'**
  String get dataExportConfirmTitle;

  /// No description provided for @dataExportFailed.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be made'**
  String get dataExportFailed;

  /// No description provided for @dataExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Share a backup'**
  String get dataExportTitle;

  /// No description provided for @dataRestoreHeader.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get dataRestoreHeader;

  /// Stated as not-yet-here rather than offered and broken: restore needs the Storage Access Framework picker and a merge strategy, both of which are 8B’s.
  ///
  /// In en, this message translates to:
  /// **'Coming in the next update.'**
  String get dataRestorePending;

  /// No description provided for @dataRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get dataRestoreTitle;

  /// No description provided for @lockBackspace.
  ///
  /// In en, this message translates to:
  /// **'Delete last digit'**
  String get lockBackspace;

  /// No description provided for @lockBiometricFailed.
  ///
  /// In en, this message translates to:
  /// **'Not recognised. Enter your PIN instead.'**
  String get lockBiometricFailed;

  /// Shown by the system prompt, so it must be localised before it reaches the plugin (Law U5).
  ///
  /// In en, this message translates to:
  /// **'Unlock Alaya'**
  String get lockBiometricReason;

  /// Says what did not change, so a failed erase does not leave the user unsure whether they are locked out of a half-wiped app.
  ///
  /// In en, this message translates to:
  /// **'The data could not be deleted. Your PIN is unchanged.'**
  String get lockEraseFailed;

  /// The ten-failure auto-erase is running. It takes the whole screen, because there is nothing left to enter a PIN against.
  ///
  /// In en, this message translates to:
  /// **'Deleting everything on this device…'**
  String get lockErasing;

  /// No description provided for @lockForgotPin.
  ///
  /// In en, this message translates to:
  /// **'I have forgotten my PIN'**
  String get lockForgotPin;

  /// ARCH_3 §2.5, and the most important string in the app. No "bank-grade", no "military-grade", and no padlock glyph beside it: the database is plaintext by design (ARCH_1 §2.1) and claiming otherwise would be dishonest and a Play listing risk.
  ///
  /// In en, this message translates to:
  /// **'This PIN stops someone who picks up your unlocked phone from opening Alaya. It does not encrypt your data — anyone with access to the phone\'s files can still read them. Your phone\'s own lock screen is what protects the file itself.'**
  String get lockHonestBody;

  /// Says why the delay exists, so a throttle reads as deliberate rather than as the app having frozen.
  ///
  /// In en, this message translates to:
  /// **'The wait gets longer after each wrong attempt.'**
  String get lockThrottledWhy;

  /// No description provided for @lockTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get lockTitle;

  /// The keypad key is an icon, so this is its Semantics label (ARCH_5 §2.7).
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint'**
  String get lockUseBiometric;

  /// No description provided for @lockWrongPin.
  ///
  /// In en, this message translates to:
  /// **'That PIN is not right.'**
  String get lockWrongPin;

  /// No description provided for @onboardingAccountsBody.
  ///
  /// In en, this message translates to:
  /// **'Where do you keep your money? Add the ones you use.'**
  String get onboardingAccountsBody;

  /// No description provided for @onboardingAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your accounts'**
  String get onboardingAccountsTitle;

  /// No description provided for @onboardingAddAccount.
  ///
  /// In en, this message translates to:
  /// **'Add an account'**
  String get onboardingAddAccount;

  /// No description provided for @onboardingCurrencyBody.
  ///
  /// In en, this message translates to:
  /// **'Which currency should Alaya add your totals up in?'**
  String get onboardingCurrencyBody;

  /// Law L9 in plain words. Somebody who thinks they are converting their history would be very surprised later.
  ///
  /// In en, this message translates to:
  /// **'This changes how totals are shown. It does not change any amount you have already recorded, and each account keeps its own currency.'**
  String get onboardingCurrencyNote;

  /// No description provided for @onboardingCurrencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your currency'**
  String get onboardingCurrencyTitle;

  /// No description provided for @onboardingFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get onboardingFinish;

  /// No description provided for @onboardingLoading.
  ///
  /// In en, this message translates to:
  /// **'Getting things ready…'**
  String get onboardingLoading;

  /// No description provided for @onboardingLockOnBody.
  ///
  /// In en, this message translates to:
  /// **'Alaya will ask for your PIN when you open it. You can change or remove it in Settings › Security.'**
  String get onboardingLockOnBody;

  /// No description provided for @onboardingLockOnHeader.
  ///
  /// In en, this message translates to:
  /// **'Lock is on'**
  String get onboardingLockOnHeader;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingNoAccountsBody.
  ///
  /// In en, this message translates to:
  /// **'Add at least one so Alaya knows where your money is.'**
  String get onboardingNoAccountsBody;

  /// No description provided for @onboardingNoAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet'**
  String get onboardingNoAccountsTitle;

  /// Anomaly A03. This is the paragraph that stops an opening balance being captured without its date.
  ///
  /// In en, this message translates to:
  /// **'The opening balance is what was there on the date you give. Alaya needs both: a balance with no date cannot be placed in your ledger, and anything you record before that date would not be counted.'**
  String get onboardingOpeningNote;

  /// No description provided for @onboardingRemoveAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove this account'**
  String get onboardingRemoveAccount;

  /// No description provided for @onboardingSaveAccounts.
  ///
  /// In en, this message translates to:
  /// **'Save accounts'**
  String get onboardingSaveAccounts;

  /// No description provided for @onboardingSecurityBody.
  ///
  /// In en, this message translates to:
  /// **'You can put a PIN on Alaya. This is optional and you can add one later.'**
  String get onboardingSecurityBody;

  /// No description provided for @onboardingSecurityTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock the app?'**
  String get onboardingSecurityTitle;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingSkipBody.
  ///
  /// In en, this message translates to:
  /// **'You can change all of this later in Settings.'**
  String get onboardingSkipBody;

  /// No description provided for @onboardingSkipTitle.
  ///
  /// In en, this message translates to:
  /// **'Skip setting up?'**
  String get onboardingSkipTitle;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Alaya'**
  String get onboardingTitle;

  /// No description provided for @payeeKindEmployer.
  ///
  /// In en, this message translates to:
  /// **'Employer'**
  String get payeeKindEmployer;

  /// No description provided for @payeeKindMerchant.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get payeeKindMerchant;

  /// No description provided for @payeeKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get payeeKindOther;

  /// No description provided for @payeeKindPerson.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get payeeKindPerson;

  /// No description provided for @payeeKindUtility.
  ///
  /// In en, this message translates to:
  /// **'Utility'**
  String get payeeKindUtility;

  /// No description provided for @payeeNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get payeeNameLabel;

  /// Marked optional, because an unmarked second field reads as required and is the commonest reason a two-field sheet feels like a form.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get payeePhoneOptionalLabel;

  /// No description provided for @payeesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a payee'**
  String get payeesAdd;

  /// No description provided for @payeesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get payeesDelete;

  /// No description provided for @payeesDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Transactions that named them keep their record. They just stop being suggested.'**
  String get payeesDeleteConfirmBody;

  /// No description provided for @payeesDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this payee?'**
  String get payeesDeleteConfirmTitle;

  /// No description provided for @payeesDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be deleted'**
  String get payeesDeleteFailed;

  /// No description provided for @payeesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Payee deleted'**
  String get payeesDeleted;

  /// No description provided for @payeesEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit payee'**
  String get payeesEditTitle;

  /// No description provided for @payeesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'These build up as you record who you paid.'**
  String get payeesEmptyBody;

  /// No description provided for @payeesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No payees yet'**
  String get payeesEmptyTitle;

  /// No description provided for @payeesLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading payees…'**
  String get payeesLoading;

  /// No description provided for @payeesNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'Try part of the name.'**
  String get payeesNoMatchBody;

  /// No description provided for @payeesNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'No payees match that'**
  String get payeesNoMatchTitle;

  /// No description provided for @payeesSave.
  ///
  /// In en, this message translates to:
  /// **'Save payee'**
  String get payeesSave;

  /// No description provided for @payeesSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be saved'**
  String get payeesSaveFailed;

  /// No description provided for @payeesSaved.
  ///
  /// In en, this message translates to:
  /// **'Payee saved'**
  String get payeesSaved;

  /// No description provided for @payeesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search payees'**
  String get payeesSearchHint;

  /// No description provided for @paymentKindBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get paymentKindBankTransfer;

  /// No description provided for @paymentKindCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paymentKindCard;

  /// No description provided for @paymentKindCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentKindCash;

  /// No description provided for @paymentKindCheque.
  ///
  /// In en, this message translates to:
  /// **'Cheque'**
  String get paymentKindCheque;

  /// No description provided for @paymentKindOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get paymentKindOther;

  /// No description provided for @paymentKindUpi.
  ///
  /// In en, this message translates to:
  /// **'UPI'**
  String get paymentKindUpi;

  /// No description provided for @paymentKindWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get paymentKindWallet;

  /// No description provided for @paymentMethodNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get paymentMethodNameLabel;

  /// No description provided for @paymentMethodsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a payment method'**
  String get paymentMethodsAdd;

  /// No description provided for @paymentMethodsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get paymentMethodsDelete;

  /// No description provided for @paymentMethodsDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Transactions that used it keep their record of having done so. It just stops being offered.'**
  String get paymentMethodsDeleteConfirmBody;

  /// No description provided for @paymentMethodsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this payment method?'**
  String get paymentMethodsDeleteConfirmTitle;

  /// No description provided for @paymentMethodsDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be deleted'**
  String get paymentMethodsDeleteFailed;

  /// No description provided for @paymentMethodsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Payment method deleted'**
  String get paymentMethodsDeleted;

  /// No description provided for @paymentMethodsEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit payment method'**
  String get paymentMethodsEditTitle;

  /// No description provided for @paymentMethodsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add how you usually pay — cash, UPI, a card.'**
  String get paymentMethodsEmptyBody;

  /// No description provided for @paymentMethodsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No payment methods'**
  String get paymentMethodsEmptyTitle;

  /// No description provided for @paymentMethodsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading payment methods…'**
  String get paymentMethodsLoading;

  /// No description provided for @paymentMethodsSave.
  ///
  /// In en, this message translates to:
  /// **'Save payment method'**
  String get paymentMethodsSave;

  /// No description provided for @paymentMethodsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be saved'**
  String get paymentMethodsSaveFailed;

  /// No description provided for @paymentMethodsSaved.
  ///
  /// In en, this message translates to:
  /// **'Payment method saved'**
  String get paymentMethodsSaved;

  /// Renameable but not removable, and the chip says so before the user hunts for a delete that is not there.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get paymentMethodsSystemChip;

  /// No description provided for @pinSetupBackupBody.
  ///
  /// In en, this message translates to:
  /// **'You have just put a lock on this app. A backup means a forgotten PIN never costs you your records.'**
  String get pinSetupBackupBody;

  /// No description provided for @pinSetupBackupHeader.
  ///
  /// In en, this message translates to:
  /// **'Make a backup?'**
  String get pinSetupBackupHeader;

  /// No description provided for @pinSetupBackupLater.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get pinSetupBackupLater;

  /// No description provided for @pinSetupBackupNow.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get pinSetupBackupNow;

  /// No description provided for @pinSetupConfirmPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter it again'**
  String get pinSetupConfirmPrompt;

  /// No description provided for @pinSetupDone.
  ///
  /// In en, this message translates to:
  /// **'Your PIN is set'**
  String get pinSetupDone;

  /// No description provided for @pinSetupDoneBody.
  ///
  /// In en, this message translates to:
  /// **'Alaya will ask for it when you open the app, and again after a minute in the background.'**
  String get pinSetupDoneBody;

  /// No description provided for @pinSetupEnterPrompt.
  ///
  /// In en, this message translates to:
  /// **'Choose a PIN'**
  String get pinSetupEnterPrompt;

  /// Both entries are cleared, because somebody who mistyped does not know which of the two was wrong.
  ///
  /// In en, this message translates to:
  /// **'Those did not match. Start again.'**
  String get pinSetupMismatch;

  /// The one confirmation, and it gates the button rather than warning after the fact.
  ///
  /// In en, this message translates to:
  /// **'I have saved this code somewhere safe'**
  String get pinSetupRecoveryAck;

  /// True rather than cautious: PinService stores only a hash, so the app genuinely cannot redisplay it.
  ///
  /// In en, this message translates to:
  /// **'This is the only way back in if you forget your PIN. It is shown once and cannot be shown again.'**
  String get pinSetupRecoveryBody;

  /// No description provided for @pinSetupRecoveryCopied.
  ///
  /// In en, this message translates to:
  /// **'Recovery code copied'**
  String get pinSetupRecoveryCopied;

  /// No description provided for @pinSetupRecoveryCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get pinSetupRecoveryCopy;

  /// No description provided for @pinSetupRecoveryHeader.
  ///
  /// In en, this message translates to:
  /// **'Your recovery code'**
  String get pinSetupRecoveryHeader;

  /// No description provided for @pinSetupRecoveryWhereToKeep.
  ///
  /// In en, this message translates to:
  /// **'A password manager is a good place for it. A photo in your gallery is not.'**
  String get pinSetupRecoveryWhereToKeep;

  /// No description provided for @pinSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a PIN'**
  String get pinSetupTitle;

  /// No description provided for @recoveryCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCodeLabel;

  /// No description provided for @recoveryCodePrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery code you saved when you set your PIN.'**
  String get recoveryCodePrompt;

  /// No description provided for @recoveryDone.
  ///
  /// In en, this message translates to:
  /// **'Your PIN has been changed'**
  String get recoveryDone;

  /// No description provided for @recoveryEraseEverything.
  ///
  /// In en, this message translates to:
  /// **'Erase everything'**
  String get recoveryEraseEverything;

  /// No description provided for @recoveryExportFirst.
  ///
  /// In en, this message translates to:
  /// **'Export a copy first'**
  String get recoveryExportFirst;

  /// Asks the user to verify: a backup nobody confirmed is not a backup.
  ///
  /// In en, this message translates to:
  /// **'A copy has been shared. Check it arrived before you erase.'**
  String get recoveryExported;

  /// No description provided for @recoveryForgotBoth.
  ///
  /// In en, this message translates to:
  /// **'I do not have the recovery code either'**
  String get recoveryForgotBoth;

  /// The export is possible only because the database is plaintext — with encryption the copy would be unreadable without the key the user has lost. ARCH_4 records that as the improvement dropping encryption bought.
  ///
  /// In en, this message translates to:
  /// **'Without your PIN or your recovery code there is no way back into this data. You can export a copy first, then erase everything and start again.'**
  String get recoveryForgotBothBody;

  /// No description provided for @recoveryForgotBothTitle.
  ///
  /// In en, this message translates to:
  /// **'Starting over'**
  String get recoveryForgotBothTitle;

  /// No description provided for @recoveryNewPinPrompt.
  ///
  /// In en, this message translates to:
  /// **'Choose a new PIN'**
  String get recoveryNewPinPrompt;

  /// No description provided for @recoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Forgotten PIN'**
  String get recoveryTitle;

  /// No description provided for @securityAutoEraseConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Turn it on'**
  String get securityAutoEraseConfirmAction;

  /// No description provided for @securityAutoEraseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn on erase after repeated failures?'**
  String get securityAutoEraseConfirmTitle;

  /// No description provided for @securityAutoEraseFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be changed'**
  String get securityAutoEraseFailed;

  /// No description provided for @securityAutoEraseHeader.
  ///
  /// In en, this message translates to:
  /// **'If the PIN is entered wrongly'**
  String get securityAutoEraseHeader;

  /// No description provided for @securityAutoEraseOff.
  ///
  /// In en, this message translates to:
  /// **'Erase after repeated failures is off'**
  String get securityAutoEraseOff;

  /// No description provided for @securityAutoEraseOn.
  ///
  /// In en, this message translates to:
  /// **'Erase after repeated failures is on'**
  String get securityAutoEraseOn;

  /// No description provided for @securityAutoEraseTitle.
  ///
  /// In en, this message translates to:
  /// **'Erase everything after repeated failures'**
  String get securityAutoEraseTitle;

  /// No description provided for @securityAutoLockHeader.
  ///
  /// In en, this message translates to:
  /// **'Auto-lock'**
  String get securityAutoLockHeader;

  /// No description provided for @securityAutoLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock when I leave the app'**
  String get securityAutoLockTitle;

  /// No description provided for @securityChangePin.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get securityChangePin;

  /// Neither branch is guessed: a row saying "no PIN set" for one frame to somebody who has one would be alarming for the wrong reason.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get securityChecking;

  /// No description provided for @securityPinHeader.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get securityPinHeader;

  /// No description provided for @securityRemovePin.
  ///
  /// In en, this message translates to:
  /// **'Remove PIN'**
  String get securityRemovePin;

  /// No description provided for @securityRemovePinConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Anyone who picks up your unlocked phone will be able to open Alaya. You will be asked for your current PIN next.'**
  String get securityRemovePinConfirmBody;

  /// No description provided for @securityRemovePinConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the PIN?'**
  String get securityRemovePinConfirmTitle;

  /// No description provided for @securityRemovePinHelp.
  ///
  /// In en, this message translates to:
  /// **'You will need your current PIN to do this.'**
  String get securityRemovePinHelp;

  /// No description provided for @securitySetPin.
  ///
  /// In en, this message translates to:
  /// **'Set a PIN'**
  String get securitySetPin;

  /// No description provided for @securitySetPinHelp.
  ///
  /// In en, this message translates to:
  /// **'Alaya will ask for it when you open the app.'**
  String get securitySetPinHelp;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsAccounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get settingsAccounts;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsCurrencies.
  ///
  /// In en, this message translates to:
  /// **'Currencies'**
  String get settingsCurrencies;

  /// No description provided for @settingsData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// No description provided for @settingsGroupApp.
  ///
  /// In en, this message translates to:
  /// **'The app'**
  String get settingsGroupApp;

  /// No description provided for @settingsGroupMoney.
  ///
  /// In en, this message translates to:
  /// **'Your money'**
  String get settingsGroupMoney;

  /// No description provided for @settingsGroupThings.
  ///
  /// In en, this message translates to:
  /// **'Your things'**
  String get settingsGroupThings;

  /// Names the search rather than the tree: "no settings" in front of a list the user can see is a lie. The examples are the keywords the rows actually match on.
  ///
  /// In en, this message translates to:
  /// **'Try a different word — \"dark\", \"PIN\" and \"backup\" all find something.'**
  String get settingsNoMatchBody;

  /// No description provided for @settingsNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches that'**
  String get settingsNoMatchTitle;

  /// No description provided for @settingsPayees.
  ///
  /// In en, this message translates to:
  /// **'Payees'**
  String get settingsPayees;

  /// No description provided for @settingsPaymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get settingsPaymentMethods;

  /// No description provided for @settingsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get settingsSearchHint;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get settingsTags;

  /// No description provided for @settingsUnits.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get settingsUnits;

  /// No description provided for @tagColourHeader.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get tagColourHeader;

  /// Honest about the freeze: colorArgb is a stored int, so a tag coloured under one preset keeps that colour when the palette changes.
  ///
  /// In en, this message translates to:
  /// **'Optional. Kept as chosen, so it stays the same if you change the app’s palette later.'**
  String get tagColourHelp;

  /// No description provided for @tagColourNone.
  ///
  /// In en, this message translates to:
  /// **'No colour'**
  String get tagColourNone;

  /// The swatches are colour-only, so each needs a Semantics label (Law U17).
  ///
  /// In en, this message translates to:
  /// **'Use this colour'**
  String get tagColourSwatch;

  /// No description provided for @tagEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get tagEditorEditTitle;

  /// No description provided for @tagEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save tag'**
  String get tagEditorSave;

  /// No description provided for @tagEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get tagEditorTitle;

  /// No description provided for @tagNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get tagNameLabel;

  /// No description provided for @tagParentHeader.
  ///
  /// In en, this message translates to:
  /// **'Group under'**
  String get tagParentHeader;

  /// No description provided for @tagParentHelp.
  ///
  /// In en, this message translates to:
  /// **'Optional. Grouping keeps long tag lists readable. Only one level deep.'**
  String get tagParentHelp;

  /// No description provided for @tagParentNone.
  ///
  /// In en, this message translates to:
  /// **'No group'**
  String get tagParentNone;

  /// No description provided for @tagScopeDeposit.
  ///
  /// In en, this message translates to:
  /// **'Money in'**
  String get tagScopeDeposit;

  /// No description provided for @tagScopeDepositHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered when you record money coming in.'**
  String get tagScopeDepositHelp;

  /// No description provided for @tagScopeInventory.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get tagScopeInventory;

  /// No description provided for @tagScopeInventoryHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered on things you keep at home.'**
  String get tagScopeInventoryHelp;

  /// No description provided for @tagScopeRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get tagScopeRecurring;

  /// No description provided for @tagScopeRecurringHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered on bills and subscriptions.'**
  String get tagScopeRecurringHelp;

  /// No description provided for @tagScopeService.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get tagScopeService;

  /// No description provided for @tagScopeServiceHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered on appliances and their service records.'**
  String get tagScopeServiceHelp;

  /// No description provided for @tagScopeShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping lists'**
  String get tagScopeShopping;

  /// No description provided for @tagScopeShoppingHelp.
  ///
  /// In en, this message translates to:
  /// **'Used to group a shopping list under headings.'**
  String get tagScopeShoppingHelp;

  /// No description provided for @tagScopeWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Money out'**
  String get tagScopeWithdrawal;

  /// No description provided for @tagScopeWithdrawalHelp.
  ///
  /// In en, this message translates to:
  /// **'Offered when you record spending.'**
  String get tagScopeWithdrawalHelp;

  /// No description provided for @tagScopesHeader.
  ///
  /// In en, this message translates to:
  /// **'Where it appears'**
  String get tagScopesHeader;

  /// ARCH_5 §7.2’s allowedIn* row, said in the terms the requirement itself uses.
  ///
  /// In en, this message translates to:
  /// **'A tag is only offered where you turn it on. This is what keeps \"Kitchen\" out of the list when you record your salary.'**
  String get tagScopesHelp;

  /// No description provided for @tagsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a tag'**
  String get tagsAdd;

  /// No description provided for @tagsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete this tag'**
  String get tagsDelete;

  /// Says what survives, because a soft delete is not what "delete" usually promises (ARCH_3 §4).
  ///
  /// In en, this message translates to:
  /// **'Transactions and items already carrying it keep it in their history. It stops appearing when you tag something new.'**
  String get tagsDeleteConfirmBody;

  /// No description provided for @tagsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this tag?'**
  String get tagsDeleteConfirmTitle;

  /// No description provided for @tagsDeleteHelp.
  ///
  /// In en, this message translates to:
  /// **'Anything already tagged keeps its history. The tag just stops being offered.'**
  String get tagsDeleteHelp;

  /// No description provided for @tagsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Tag deleted'**
  String get tagsDeleted;

  /// No description provided for @tagsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tags let you group things across accounts — \"Kitchen\", \"Car\", \"Diwali\".'**
  String get tagsEmptyBody;

  /// No description provided for @tagsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get tagsEmptyTitle;

  /// No description provided for @tagsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading tags…'**
  String get tagsLoading;

  /// No description provided for @tagsMissingBody.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted. Go back and pick another.'**
  String get tagsMissingBody;

  /// No description provided for @tagsMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'That tag is not here'**
  String get tagsMissingTitle;

  /// A tag with no scopes cannot appear anywhere in the app, which makes it invisible everywhere except this screen — exactly the dead row somebody would hunt for in the pickers first.
  ///
  /// In en, this message translates to:
  /// **'This tag is not offered anywhere. Turn on at least one place below, or it will never appear.'**
  String get tagsNoScopesWarning;

  /// No description provided for @tagsSaved.
  ///
  /// In en, this message translates to:
  /// **'Tag saved'**
  String get tagsSaved;

  /// No description provided for @tagsSystemChip.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get tagsSystemChip;

  /// No description provided for @unitBaseGrams.
  ///
  /// In en, this message translates to:
  /// **'grams'**
  String get unitBaseGrams;

  /// No description provided for @unitBaseMillilitres.
  ///
  /// In en, this message translates to:
  /// **'millilitres'**
  String get unitBaseMillilitres;

  /// No description provided for @unitBasePieces.
  ///
  /// In en, this message translates to:
  /// **'pieces'**
  String get unitBasePieces;

  /// No description provided for @unitCategoryHeader.
  ///
  /// In en, this message translates to:
  /// **'What does it measure?'**
  String get unitCategoryHeader;

  /// No description provided for @unitCategoryNewHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose carefully: this cannot be changed later.'**
  String get unitCategoryNewHelp;

  /// No description provided for @unitCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'What you will see beside a quantity — kg, ml, pc.'**
  String get unitCodeHelp;

  /// No description provided for @unitCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Short code'**
  String get unitCodeLabel;

  /// No description provided for @unitCodeLockedHelp.
  ///
  /// In en, this message translates to:
  /// **'Fixed once the unit exists, because other records point at it.'**
  String get unitCodeLockedHelp;

  /// No description provided for @unitEditorEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit unit'**
  String get unitEditorEditTitle;

  /// No description provided for @unitEditorSave.
  ///
  /// In en, this message translates to:
  /// **'Save unit'**
  String get unitEditorSave;

  /// No description provided for @unitEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'New unit'**
  String get unitEditorTitle;

  /// No description provided for @unitFactorHeader.
  ///
  /// In en, this message translates to:
  /// **'How big is it?'**
  String get unitFactorHeader;

  /// Guarded rather than trusted: a zero factor would convert every quantity in the unit to nothing and divide the inventory valuation by zero.
  ///
  /// In en, this message translates to:
  /// **'That has to be more than zero.'**
  String get unitFactorMustBePositive;

  /// Stands in for the name while the field is still empty, so the question reads as a sentence either way.
  ///
  /// In en, this message translates to:
  /// **'this unit'**
  String get unitFactorThisUnit;

  /// No description provided for @unitFactorVaries.
  ///
  /// In en, this message translates to:
  /// **'It varies — I cannot give one number'**
  String get unitFactorVaries;

  /// No description provided for @unitNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get unitNameLabel;

  /// A way back, for somebody who realises on reading this that they can state an amount.
  ///
  /// In en, this message translates to:
  /// **'Actually, I can give a number'**
  String get unitVariesBack;

  /// No description provided for @unitVariesCreateItem.
  ///
  /// In en, this message translates to:
  /// **'Create an item instead'**
  String get unitVariesCreateItem;

  /// No description provided for @unitVariesInsteadBody.
  ///
  /// In en, this message translates to:
  /// **'Add \"Biscuit packet\" as its own item, counted in pieces. Then two packets is two of that item, and Alaya can price and track them properly.'**
  String get unitVariesInsteadBody;

  /// No description provided for @unitVariesInsteadTitle.
  ///
  /// In en, this message translates to:
  /// **'Make it an item instead'**
  String get unitVariesInsteadTitle;

  /// No description provided for @unitVariesTitle.
  ///
  /// In en, this message translates to:
  /// **'Then it is not a unit'**
  String get unitVariesTitle;

  /// ARCH_1 §5.3 explained by consequence rather than by quoting the rule. This is what makes the alternative obviously better instead of merely mandated.
  ///
  /// In en, this message translates to:
  /// **'A unit has to be the same amount every time. One packet of biscuits and one packet of rice are different weights, so Alaya could not add two packets together or work out what one cost.'**
  String get unitVariesWhy;

  /// No description provided for @unitsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a unit'**
  String get unitsAdd;

  /// ARCH_1 §5.3 and Law L8, stated where somebody about to add a unit reads it before trying rather than as a refusal afterwards.
  ///
  /// In en, this message translates to:
  /// **'Weight, volume and count are the only three kinds there are. Alaya never converts between them, so a kilo can never become a litre by accident.'**
  String get unitsCategoriesFixedNote;

  /// No description provided for @unitsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete this unit'**
  String get unitsDelete;

  /// The R18 failure from the other direction: a quantity whose unit has gone cannot be converted or valued.
  ///
  /// In en, this message translates to:
  /// **'Anything already bought in this unit keeps its quantity, but that quantity would no longer be readable. Only delete a unit you have not used.'**
  String get unitsDeleteConfirmBody;

  /// No description provided for @unitsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this unit?'**
  String get unitsDeleteConfirmTitle;

  /// No description provided for @unitsDeleteHelp.
  ///
  /// In en, this message translates to:
  /// **'Only possible while nothing is measured in it.'**
  String get unitsDeleteHelp;

  /// No description provided for @unitsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Unit deleted'**
  String get unitsDeleted;

  /// No description provided for @unitsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Alaya ships with the common ones. Add one if you measure something differently.'**
  String get unitsEmptyBody;

  /// No description provided for @unitsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No units'**
  String get unitsEmptyTitle;

  /// No description provided for @unitsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading units…'**
  String get unitsLoading;

  /// No description provided for @unitsMissingBody.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted. Go back and pick another.'**
  String get unitsMissingBody;

  /// No description provided for @unitsMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'That unit is not here'**
  String get unitsMissingTitle;

  /// No description provided for @unitsSaved.
  ///
  /// In en, this message translates to:
  /// **'Unit saved'**
  String get unitsSaved;

  /// No description provided for @unitsSystemChip.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get unitsSystemChip;

  /// The precision matters to the reader: JPY has none, so an amount typed as 1200 is ¥1,200 and not ¥12.00.
  ///
  /// In en, this message translates to:
  /// **'{symbol} · {digits, plural, =0{no decimal places} =1{1 decimal place} other{{digits} decimal places}}'**
  String currenciesRowSubtitle(String symbol, int digits);

  /// A currency row: the code first, because it is what the pickers show.
  ///
  /// In en, this message translates to:
  /// **'{code} · {name}'**
  String currenciesRowTitle(String code, String name);

  /// Names the file, because a backup the user cannot identify later is one they will not trust when they need it (ARCH_3 §3.4).
  ///
  /// In en, this message translates to:
  /// **'Backup saved as {fileName}'**
  String dataExportDone(String fileName);

  /// The countdown ticks. Formatted in Dart as m:ss, because a plural on "second" cannot express 1:05.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {time}'**
  String lockThrottled(String time);

  /// No description provided for @onboardingCurrencyChip.
  ///
  /// In en, this message translates to:
  /// **'{code} {symbol}'**
  String onboardingCurrencyChip(String code, String symbol);

  /// Words and a count rather than dots: the one question people abandon a setup flow over is how long it will take.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String onboardingStepOf(int step, int total);

  /// No description provided for @pinSetupLength.
  ///
  /// In en, this message translates to:
  /// **'{length} digits'**
  String pinSetupLength(int length);

  /// The word is passed in from DataTransferPort.eraseConfirmationWord and is deliberately not translated, so a support article can tell anyone what to type.
  ///
  /// In en, this message translates to:
  /// **'Type {word} to confirm'**
  String recoveryTypeToConfirm(String word);

  /// No description provided for @securityAutoEraseBody.
  ///
  /// In en, this message translates to:
  /// **'When on, {count} wrong PIN attempts in a row will delete everything on this device.'**
  String securityAutoEraseBody(int count);

  /// The scary confirm names the number. A generic "are you sure?" would not earn consent to a setting that destroys a household’s records.
  ///
  /// In en, this message translates to:
  /// **'After {count} failed attempts, every account, transaction and item on this device is deleted. There is no undo, and no copy unless you have made a backup.'**
  String securityAutoEraseConfirmBody(int count);

  /// Stated rather than configurable in 8A: autoLockDelay is a constant, and a picker writing a setting nothing reads would be a dead control.
  ///
  /// In en, this message translates to:
  /// **'Locks again after {seconds} seconds in the background.'**
  String securityAutoLockBody(int seconds);

  /// Archived accounts included, because this row is the only way to reach one and restore it.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No accounts} =1{1 account} other{{count} accounts}}'**
  String settingsAccountCount(int count);

  /// No description provided for @settingsCurrencyCount.
  ///
  /// In en, this message translates to:
  /// **'{enabled} of {total} enabled'**
  String settingsCurrencyCount(int enabled, int total);

  /// No description provided for @settingsPayeeCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No payees} =1{1 payee} other{{count} payees}}'**
  String settingsPayeeCount(int count);

  /// No description provided for @settingsPaymentMethodCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No payment methods} =1{1 payment method} other{{count} payment methods}}'**
  String settingsPaymentMethodCount(int count);

  /// No description provided for @settingsTagCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No tags} =1{1 tag} other{{count} tags}}'**
  String settingsTagCount(int count);

  /// No description provided for @settingsUnitCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No units} =1{1 unit} other{{count} units}}'**
  String settingsUnitCount(int count);

  /// The condition for being a unit at all. Somebody who reads this and cannot meet it has found the "make it an item" path.
  ///
  /// In en, this message translates to:
  /// **'One of this unit has to be the same number of {base} every time.'**
  String unitFactorHelp(String base);

  /// Asked in base units, never in the stored thousandths — reproducing that arithmetic is what ARCH_4 R18 got wrong three times.
  ///
  /// In en, this message translates to:
  /// **'How many {base} is one {unit}?'**
  String unitFactorQuestion(String base, String unit);

  /// What the unit is, assembled from the stored thousandths so the reader never meets them.
  ///
  /// In en, this message translates to:
  /// **'1 {code} = {amount} {base}'**
  String unitsEquals(String code, String amount, String base);

  /// No description provided for @unitsRowTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} ({code})'**
  String unitsRowTitle(String name, String code);

  /// No description provided for @attachmentsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an attachment'**
  String get attachmentsAdd;

  /// No description provided for @attachmentsAddFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be attached'**
  String get attachmentsAddFailed;

  /// No description provided for @attachmentsAdded.
  ///
  /// In en, this message translates to:
  /// **'Attached'**
  String get attachmentsAdded;

  /// Not "take a photo": capture needs image_picker, which ARCH_1 §7 does not pin.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get attachmentsChoosePhoto;

  /// No description provided for @attachmentsDelete.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get attachmentsDelete;

  /// No description provided for @attachmentsDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The file is deleted from this phone. Backups you have already made still contain it.'**
  String get attachmentsDeleteConfirmBody;

  /// No description provided for @attachmentsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this attachment?'**
  String get attachmentsDeleteConfirmTitle;

  /// No description provided for @attachmentsDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be removed'**
  String get attachmentsDeleteFailed;

  /// No description provided for @attachmentsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Attachment removed'**
  String get attachmentsDeleted;

  /// No description provided for @attachmentsMissing.
  ///
  /// In en, this message translates to:
  /// **'That file is missing from this phone.'**
  String get attachmentsMissing;

  /// No description provided for @attachmentsNone.
  ///
  /// In en, this message translates to:
  /// **'Nothing attached'**
  String get attachmentsNone;

  /// No description provided for @attachmentsOpen.
  ///
  /// In en, this message translates to:
  /// **'Open attachment'**
  String get attachmentsOpen;

  /// No description provided for @attachmentsStoredLocally.
  ///
  /// In en, this message translates to:
  /// **'Kept on this phone only, and included in your backups.'**
  String get attachmentsStoredLocally;

  /// No description provided for @backupConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Make the backup'**
  String get backupConfirmAction;

  /// No description provided for @backupConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Make a backup?'**
  String get backupConfirmTitle;

  /// No description provided for @backupDone.
  ///
  /// In en, this message translates to:
  /// **'Backup saved'**
  String get backupDone;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'The backup could not be made'**
  String get backupFailed;

  /// No description provided for @backupForget.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get backupForget;

  /// Says what does *not* happen: "remove" over a backup reads as deleting the file.
  ///
  /// In en, this message translates to:
  /// **'This removes it from the list only. The backup file itself stays wherever you put it — Alaya cannot reach into your Drive or your chats.'**
  String get backupForgetConfirmBody;

  /// No description provided for @backupForgetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Forget this entry?'**
  String get backupForgetConfirmTitle;

  /// No description provided for @backupForgetFailed.
  ///
  /// In en, this message translates to:
  /// **'That entry could not be removed'**
  String get backupForgetFailed;

  /// No description provided for @backupForgotten.
  ///
  /// In en, this message translates to:
  /// **'Entry removed'**
  String get backupForgotten;

  /// Says where, because a backup sitting on the device it protects is not a backup.
  ///
  /// In en, this message translates to:
  /// **'Make one now, and keep it somewhere that is not this phone.'**
  String get backupHistoryEmptyBody;

  /// No description provided for @backupHistoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No backups yet'**
  String get backupHistoryEmptyTitle;

  /// No description provided for @backupHistoryHeader.
  ///
  /// In en, this message translates to:
  /// **'Backups you have made'**
  String get backupHistoryHeader;

  /// No description provided for @backupHistoryLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your backups…'**
  String get backupHistoryLoading;

  /// No description provided for @backupMakeHeader.
  ///
  /// In en, this message translates to:
  /// **'Make a backup'**
  String get backupMakeHeader;

  /// No description provided for @backupRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'Merge a backup into what you have, or replace everything with it.'**
  String get backupRestoreBody;

  /// No description provided for @backupRestoreHeader.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get backupRestoreHeader;

  /// No description provided for @backupRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get backupRestoreTitle;

  /// No description provided for @backupSaveBody.
  ///
  /// In en, this message translates to:
  /// **'Choose where to put it. Alaya needs no storage permission — you pick the folder.'**
  String get backupSaveBody;

  /// No description provided for @backupSaveTitle.
  ///
  /// In en, this message translates to:
  /// **'Save a copy'**
  String get backupSaveTitle;

  /// No description provided for @backupShareBody.
  ///
  /// In en, this message translates to:
  /// **'Send it to WhatsApp, Drive, or anywhere else.'**
  String get backupShareBody;

  /// No description provided for @backupShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share a copy'**
  String get backupShareTitle;

  /// No description provided for @backupTitle.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupTitle;

  /// No description provided for @reminderKindExpiry.
  ///
  /// In en, this message translates to:
  /// **'Things going off'**
  String get reminderKindExpiry;

  /// No description provided for @reminderKindExpiryHelp.
  ///
  /// In en, this message translates to:
  /// **'Food and medicine reaching their use-by date.'**
  String get reminderKindExpiryHelp;

  /// No description provided for @reminderKindLowStock.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get reminderKindLowStock;

  /// The row exists because the enum does; the help says why it is not in the digest.
  ///
  /// In en, this message translates to:
  /// **'Not offered as a reminder: being low on something has no date, so it would arrive every morning until you shopped.'**
  String get reminderKindLowStockHelp;

  /// No description provided for @reminderKindRecurring.
  ///
  /// In en, this message translates to:
  /// **'Bills and subscriptions'**
  String get reminderKindRecurring;

  /// No description provided for @reminderKindRecurringHelp.
  ///
  /// In en, this message translates to:
  /// **'When a recurring payment falls due.'**
  String get reminderKindRecurringHelp;

  /// No description provided for @reminderKindService.
  ///
  /// In en, this message translates to:
  /// **'Appliance servicing'**
  String get reminderKindService;

  /// No description provided for @reminderKindServiceHelp.
  ///
  /// In en, this message translates to:
  /// **'When something is due for its next service.'**
  String get reminderKindServiceHelp;

  /// No description provided for @reminderKindWarranty.
  ///
  /// In en, this message translates to:
  /// **'Warranties ending'**
  String get reminderKindWarranty;

  /// No description provided for @reminderKindWarrantyHelp.
  ///
  /// In en, this message translates to:
  /// **'Before a warranty runs out, while you can still use it.'**
  String get reminderKindWarrantyHelp;

  /// Names the place. "Notifications are blocked" without saying where is a dead end.
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off for Alaya. Turn them on in your phone’s Settings › Apps › Alaya › Notifications.'**
  String get remindersBlocked;

  /// No description provided for @remindersDenied.
  ///
  /// In en, this message translates to:
  /// **'Alaya needs permission to send notifications.'**
  String get remindersDenied;

  /// ARCH_3 §7’s "fewer, better notifications", stated before the toggles so somebody knows what turning one on means.
  ///
  /// In en, this message translates to:
  /// **'Alaya sends one message a day about what is coming up — not a notification for every item.'**
  String get remindersDigestExplainer;

  /// No description provided for @remindersDigestRow.
  ///
  /// In en, this message translates to:
  /// **'Daily summary'**
  String get remindersDigestRow;

  /// No description provided for @remindersKindsHeader.
  ///
  /// In en, this message translates to:
  /// **'What to remind me about'**
  String get remindersKindsHeader;

  /// No description provided for @remindersLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading your reminders…'**
  String get remindersLoading;

  /// Explains rather than apologises: empty is the normal state with everything off.
  ///
  /// In en, this message translates to:
  /// **'Turn on a reminder above and Alaya will show what it has planned here.'**
  String get remindersNoneScheduledBody;

  /// No description provided for @remindersNoneScheduledTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled'**
  String get remindersNoneScheduledTitle;

  /// No description provided for @remindersScheduledHeader.
  ///
  /// In en, this message translates to:
  /// **'Currently scheduled'**
  String get remindersScheduledHeader;

  /// No description provided for @remindersTimeHeader.
  ///
  /// In en, this message translates to:
  /// **'When'**
  String get remindersTimeHeader;

  /// No description provided for @remindersTimeSaved.
  ///
  /// In en, this message translates to:
  /// **'Reminder time changed'**
  String get remindersTimeSaved;

  /// No description provided for @remindersTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily summary time'**
  String get remindersTimeTitle;

  /// No description provided for @remindersTitle.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get remindersTitle;

  /// No description provided for @remindersToggleFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be changed'**
  String get remindersToggleFailed;

  /// No description provided for @restoreApplyMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge the backup'**
  String get restoreApplyMerge;

  /// No description provided for @restoreApplyReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace everything'**
  String get restoreApplyReplace;

  /// No description provided for @restoreChooseAnother.
  ///
  /// In en, this message translates to:
  /// **'Choose another file'**
  String get restoreChooseAnother;

  /// No description provided for @restoreChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get restoreChooseFile;

  /// No description provided for @restoreChosenHeader.
  ///
  /// In en, this message translates to:
  /// **'Chosen file'**
  String get restoreChosenHeader;

  /// No description provided for @restoreContinueReplace.
  ///
  /// In en, this message translates to:
  /// **'Continue to replace'**
  String get restoreContinueReplace;

  /// No description provided for @restoreDone.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get restoreDone;

  /// ARCH_3 §3.2’s last line, on the one screen where somebody might expect otherwise. Shown at all three stages.
  ///
  /// In en, this message translates to:
  /// **'Your PIN is never restored. It is kept outside the backup, so opening someone else’s backup can never change who can open this app.'**
  String get restoreLockNotRestored;

  /// The default, and the description says why: merge keeps rows the backup does not have.
  ///
  /// In en, this message translates to:
  /// **'Adds what the backup has and updates what is newer. Nothing you have now is lost.'**
  String get restoreMergeBody;

  /// No description provided for @restoreMergeTitle.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get restoreMergeTitle;

  /// No description provided for @restoreModeHeader.
  ///
  /// In en, this message translates to:
  /// **'How should it be applied?'**
  String get restoreModeHeader;

  /// No description provided for @restoreNotADatabase.
  ///
  /// In en, this message translates to:
  /// **'That file is not an Alaya backup.'**
  String get restoreNotADatabase;

  /// No description provided for @restorePickBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a backup file. Alaya will check it before anything changes.'**
  String get restorePickBody;

  /// No description provided for @restoreReplaceBody.
  ///
  /// In en, this message translates to:
  /// **'Throws away what is on this phone and uses the backup instead.'**
  String get restoreReplaceBody;

  /// No description provided for @restoreReplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace everything'**
  String get restoreReplaceTitle;

  /// No description provided for @restoreReplaceWarning.
  ///
  /// In en, this message translates to:
  /// **'Everything currently on this phone will be thrown away and replaced by the backup. Anything recorded since that backup was made will be gone.'**
  String get restoreReplaceWarning;

  /// No description provided for @restoreRollbackAvailable.
  ///
  /// In en, this message translates to:
  /// **'Restored the wrong file? You can put your previous data back.'**
  String get restoreRollbackAvailable;

  /// Said before the typed confirmation, because somebody who knows there is a way back reads the warning as information rather than a threat.
  ///
  /// In en, this message translates to:
  /// **'Alaya takes a snapshot of your current data first, so you can undo this straight afterwards.'**
  String get restoreRollbackPromise;

  /// No description provided for @restoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreTitle;

  /// No description provided for @restoreUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo the replace'**
  String get restoreUndo;

  /// Says what happened rather than showing a button that cannot work: without consent settled, no ad is requested at all.
  ///
  /// In en, this message translates to:
  /// **'Adverts need a choice about personalisation that could not be loaded right now. Nothing has been requested.'**
  String get supportConsentUnavailable;

  /// No description provided for @supportIntro.
  ///
  /// In en, this message translates to:
  /// **'Alaya is free, works offline, and has no accounts to sign up for. If it is useful to you, there are two ways to help.'**
  String get supportIntro;

  /// No description provided for @supportLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get supportLoading;

  /// No description provided for @supportNoAd.
  ///
  /// In en, this message translates to:
  /// **'No advert available right now'**
  String get supportNoAd;

  /// Keeps this a tip rather than a paywall wearing a friendly label, and says so where somebody decides.
  ///
  /// In en, this message translates to:
  /// **'Nothing here unlocks anything. There are no paid features — the whole app is already yours.'**
  String get supportNoPaidFeatures;

  /// No description provided for @supportThanks.
  ///
  /// In en, this message translates to:
  /// **'Thank you. That genuinely helps.'**
  String get supportThanks;

  /// No description provided for @supportTipBody.
  ///
  /// In en, this message translates to:
  /// **'A one-time thank-you through the Play Store. It is not a subscription.'**
  String get supportTipBody;

  /// No description provided for @supportTipHeader.
  ///
  /// In en, this message translates to:
  /// **'Leave a tip'**
  String get supportTipHeader;

  /// No description provided for @supportTipUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Tips are not available on this device right now.'**
  String get supportTipUnavailable;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support Alaya'**
  String get supportTitle;

  /// No description provided for @supportWatchAction.
  ///
  /// In en, this message translates to:
  /// **'Watch an advert'**
  String get supportWatchAction;

  /// True by construction: one file imports the SDK and only this screen starts it.
  ///
  /// In en, this message translates to:
  /// **'One advert, when you choose to. Alaya never shows one anywhere else in the app.'**
  String get supportWatchBody;

  /// No description provided for @supportWatchHeader.
  ///
  /// In en, this message translates to:
  /// **'Watch a short advert'**
  String get supportWatchHeader;

  /// No description provided for @trashDeletedOn.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get trashDeletedOn;

  /// No description provided for @trashEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Things you delete are kept here for 30 days before they go for good.'**
  String get trashEmptyBody;

  /// No description provided for @trashEmptyNow.
  ///
  /// In en, this message translates to:
  /// **'Empty now'**
  String get trashEmptyNow;

  /// The only hard delete a user can reach, so the body says it plainly.
  ///
  /// In en, this message translates to:
  /// **'Everything in the trash is deleted permanently. This is not the trash — there is nowhere left for it to go.'**
  String get trashEmptyNowConfirmBody;

  /// No description provided for @trashEmptyNowConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty the trash?'**
  String get trashEmptyNowConfirmTitle;

  /// No description provided for @trashEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'The trash is empty'**
  String get trashEmptyTitle;

  /// Every row says when it goes: a trash that silently empties is one people stop trusting.
  ///
  /// In en, this message translates to:
  /// **'· kept for 30 days'**
  String get trashGoesOn;

  /// No description provided for @trashKindAsset.
  ///
  /// In en, this message translates to:
  /// **'Appliances'**
  String get trashKindAsset;

  /// No description provided for @trashKindItem.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get trashKindItem;

  /// No description provided for @trashKindPayee.
  ///
  /// In en, this message translates to:
  /// **'Payees'**
  String get trashKindPayee;

  /// No description provided for @trashKindRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get trashKindRecurring;

  /// No description provided for @trashKindShoppingList.
  ///
  /// In en, this message translates to:
  /// **'Shopping lists'**
  String get trashKindShoppingList;

  /// No description provided for @trashKindTag.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get trashKindTag;

  /// No description provided for @trashKindTransaction.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get trashKindTransaction;

  /// No description provided for @trashLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the trash…'**
  String get trashLoading;

  /// No description provided for @trashNoMatchBody.
  ///
  /// In en, this message translates to:
  /// **'Remove a filter to see the rest.'**
  String get trashNoMatchBody;

  /// No description provided for @trashNoMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches that filter'**
  String get trashNoMatchTitle;

  /// No description provided for @trashPurgeConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'It will not go back to the trash. There is no undo.'**
  String get trashPurgeConfirmBody;

  /// No description provided for @trashPurgeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this for good?'**
  String get trashPurgeConfirmTitle;

  /// No description provided for @trashPurgeFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be deleted'**
  String get trashPurgeFailed;

  /// No description provided for @trashPurgeOne.
  ///
  /// In en, this message translates to:
  /// **'Delete for good'**
  String get trashPurgeOne;

  /// No description provided for @trashPurgedOne.
  ///
  /// In en, this message translates to:
  /// **'Deleted for good'**
  String get trashPurgedOne;

  /// No description provided for @trashRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get trashRestore;

  /// No description provided for @trashRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'That could not be restored'**
  String get trashRestoreFailed;

  /// No description provided for @trashRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get trashRestored;

  /// No description provided for @trashTitle.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trashTitle;

  /// Names the file, because a backup you cannot identify later is one you will not trust when you need it.
  ///
  /// In en, this message translates to:
  /// **'Backup saved as {fileName}'**
  String backupDoneNamed(String fileName);

  /// The unit changes with the magnitude, so the number is formatted in Dart — a translator cannot choose between KB and MB inside a placeholder.
  ///
  /// In en, this message translates to:
  /// **'· {size}'**
  String backupHistorySize(String size);

  /// No description provided for @remindersTimeBody.
  ///
  /// In en, this message translates to:
  /// **'Sent at {time} each day'**
  String remindersTimeBody(String time);

  /// No description provided for @restoreDoneDetail.
  ///
  /// In en, this message translates to:
  /// **'{tables, plural, =1{1 table restored} other{{tables} tables restored}}'**
  String restoreDoneDetail(int tables);

  /// ARCH_3 §3.2’s gate, stated with both numbers. A refusal without them is one nobody can act on.
  ///
  /// In en, this message translates to:
  /// **'That backup is from a newer version of Alaya (version {backup}) than this app understands (version {app}). Update Alaya and try again.'**
  String restoreNewerSchema(int backup, int app);

  /// The word is not translated, so a support article can tell anyone what to type.
  ///
  /// In en, this message translates to:
  /// **'Type {word} to confirm'**
  String restoreTypeToConfirm(String word);

  /// The store’s own formatted price, never reformatted: Play localises it for the user’s account, which need not match this app’s home currency.
  ///
  /// In en, this message translates to:
  /// **'Leave a tip · {price}'**
  String supportTipAction(String price);

  /// "For good" rather than "deleted", because this is the one hard delete in the app.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing to delete} =1{1 item deleted for good} other{{count} items deleted for good}}'**
  String trashPurged(int count);

  /// No description provided for @dataBackupRowBody.
  ///
  /// In en, this message translates to:
  /// **'Save a copy, share it, or restore from one.'**
  String get dataBackupRowBody;

  /// No description provided for @dataTrashRowBody.
  ///
  /// In en, this message translates to:
  /// **'Things you delete are kept here for 30 days.'**
  String get dataTrashRowBody;

  /// No description provided for @settingsRemindersHelp.
  ///
  /// In en, this message translates to:
  /// **'One daily summary of what is coming up.'**
  String get settingsRemindersHelp;

  /// Says on the row itself that this is not a paywall, so the entry cannot read as one.
  ///
  /// In en, this message translates to:
  /// **'Optional, and nothing here unlocks anything.'**
  String get settingsSupportHelp;

  /// No description provided for @settingsTrashCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nothing in the trash} =1{1 item} other{{count} items}}'**
  String settingsTrashCount(int count);

  /// The app bar action. Says what the tap does, because a joined-hands icon alone does not — and no advert is fetched until it is pressed.
  ///
  /// In en, this message translates to:
  /// **'Watch an advert to support Alaya'**
  String get supportWatchTooltip;

  /// A ledger row spoken as one thing (ARCH_5 §6). The comma is the pause a screen reader takes, which is why it is punctuation rather than a word.
  ///
  /// In en, this message translates to:
  /// **'{title}, {amount}'**
  String ledgerRowSemantics(String title, String amount);

  /// The same, with the row’s metadata line — an account, a payment method or a review flag.
  ///
  /// In en, this message translates to:
  /// **'{title}, {amount}, {detail}'**
  String ledgerRowSemanticsDetailed(String title, String amount, String detail);
}

class _AlayaStringsDelegate extends LocalizationsDelegate<AlayaStrings> {
  const _AlayaStringsDelegate();

  @override
  Future<AlayaStrings> load(Locale locale) {
    return SynchronousFuture<AlayaStrings>(lookupAlayaStrings(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AlayaStringsDelegate old) => false;
}

AlayaStrings lookupAlayaStrings(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AlayaStringsEn();
  }

  throw FlutterError(
    'AlayaStrings.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
