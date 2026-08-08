# PHASE 6D — The Recurring module UI

`RecurringEngine` (Phase 4C) already owns every piece of arithmetic this phase needs — `nextDue`,
`clampDayOfMonth`, `isActive`, `isOverdue`, `planSettlement` — and `recurringEngineProvider` already
exposes it. Nothing is reimplemented here: the frequency preview walks `nextDue`, and overdue is
`engine.isOverdue` against `clock.today()`, never a stored flag (ARCH_2 §12.2).

`app_en.arb`, `routes.dart` and `app_router.dart` supersede their earlier versions; every other file
is new.

```
flutter gen-l10n
flutter analyze
flutter test
```

No new packages.

### `lib/app/l10n/app_en.arb`

```json
{
  "@@locale": "en",
  "appName": "Alaya",
  "@appName": {
    "description": "The app's name, shown in the drawer header."
  },
  "navDashboard": "Dashboard",
  "navExpenses": "Expenses",
  "navInventory": "Inventory",
  "navShopping": "Shopping",
  "navRecurring": "Recurring",
  "navServices": "Services",
  "navCalendar": "Calendar",
  "navInsights": "Insights",
  "navSettings": "Settings",
  "navThemeLab": "Theme Lab",
  "actionSave": "Save",
  "@actionSave": {
    "description": "Commits an edit. Active voice, and the same word appears in the resulting confirmation."
  },
  "actionSaved": "Saved",
  "actionCancel": "Cancel",
  "actionDelete": "Delete",
  "actionDeleted": "Deleted",
  "actionUndo": "Undo",
  "actionRetry": "Try again",
  "actionAdd": "Add",
  "actionEdit": "Edit",
  "actionDone": "Done",
  "actionClose": "Close",
  "actionSelect": "Select",
  "actionClear": "Clear",
  "actionClearAll": "Clear all",
  "actionSearch": "Search",
  "actionConfirm": "Confirm",
  "actionDiscard": "Discard",
  "actionKeepEditing": "Keep editing",
  "actionRemoveTag": "Remove tag",
  "@actionRemoveTag": {
    "description": "Accessibility label for the dismiss affordance on a removable tag chip."
  },
  "actionClearSearch": "Clear search",
  "@actionClearSearch": {
    "description": "Accessibility label for the clear button inside AlayaSearchField."
  },
  "addExpense": "Add expense",
  "addIncome": "Add income",
  "addTransfer": "Add transfer",
  "addItem": "Add item",
  "addToShoppingList": "Add to shopping list",
  "dateToday": "Today",
  "@dateToday": {
    "description": "DateText.relative, when the date is the clock's today. Sentence case; it can begin a row."
  },
  "dateYesterday": "Yesterday",
  "dateTomorrow": "Tomorrow",
  "emptyTitleNoTransactions": "No transactions yet",
  "emptyBodyNoTransactions": "Add your first expense and it will appear here.",
  "@emptyBodyNoTransactions": {
    "description": "An empty screen is an invitation to act, so this names the action rather than describing the emptiness."
  },
  "emptyTitleNoItems": "Nothing in your inventory",
  "emptyBodyNoItems": "Add an item to start tracking what you have at home.",
  "emptyTitleNoShopping": "Your list is empty",
  "emptyBodyNoShopping": "Add something, or let Alaya suggest items you are low on.",
  "emptyTitleNoRecurring": "No recurring bills",
  "emptyBodyNoRecurring": "Set up a bill or subscription and Alaya will remind you when it is due.",
  "emptyTitleNoResults": "No matches",
  "emptyBodyNoResults": "Try a shorter search, or check the spelling.",
  "loadingLabel": "Loading",
  "loadingTransactions": "Loading transactions",
  "errorTitleGeneric": "That did not work",
  "@errorTitleGeneric": {
    "description": "Errors do not apologise and are never vague. This pairs with a specific body message."
  },
  "errorBodyGeneric": "Something went wrong on our side. Try again.",
  "errorTitleNotFound": "Not found",
  "errorBodyNotFound": "This item may have been deleted.",
  "errorBodyNoConnection": "You are offline. Alaya works offline, but rates will not refresh.",
  "errorFieldRequired": "This is required",
  "errorAmountInvalid": "Enter an amount",
  "errorAmountZero": "Enter an amount greater than zero",
  "errorAmountInvalidCharacter": "Digits only",
  "errorAmountNegativeNotAllowed": "Enter a positive amount",
  "errorAmountTooManyDecimals": "Too many decimal places",
  "errorAmountTooLarge": "That amount is too large",
  "errorQuantityTooLarge": "That quantity is too large",
  "errorQuantityInvalid": "Enter a quantity",
  "errorQuantityInvalidCharacter": "Digits only",
  "errorQuantityNegativeNotAllowed": "Enter a positive quantity",
  "errorQuantityTooPrecise": "Too precise for this unit",
  "@errorQuantityTooPrecise": {
    "description": "The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded."
  },
  "errorDateInvalid": "Choose a date",
  "confirmDeleteTitle": "Delete this?",
  "confirmDeleteBody": "You can undo this for the next few seconds.",
  "confirmDiscardTitle": "Discard your changes?",
  "confirmDiscardBody": "What you have typed will not be saved.",
  "labelAmount": "Amount",
  "labelQuantity": "Quantity",
  "labelUnit": "Unit",
  "labelDate": "Date",
  "labelAccount": "Account",
  "labelPaymentMethod": "Payment method",
  "labelPayee": "Payee",
  "labelCategory": "Category",
  "labelTags": "Tags",
  "labelNote": "Note",
  "labelFrom": "From",
  "labelTo": "To",
  "labelItem": "Item",
  "labelExpiry": "Expiry",
  "labelTotal": "Total",
  "hintSelectAccount": "Choose an account",
  "hintSelectUnit": "Choose a unit",
  "hintSelectTags": "Choose tags",
  "hintSelectDate": "Choose a date",
  "hintSearchItems": "Search items",
  "hintNote": "Add a note",
  "amountUnconverted": "{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}",
  "@amountUnconverted": {
    "description": "The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "amountApproximate": "Approximate rate",
  "@amountApproximate": {
    "description": "Shown when a conversion used the nearest earlier rate rather than the exact date's."
  },
  "tagCountMore": "+{count}",
  "@tagCountMore": {
    "description": "Overflow indicator when a row cannot show every tag.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "statusNeedsReview": "Needs details",
  "@statusNeedsReview": {
    "description": "StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set."
  },
  "statusUnallocated": "Unallocated",
  "@statusUnallocated": {
    "description": "StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11)."
  },
  "statusDetached": "Receipt deleted",
  "@statusDetached": {
    "description": "StatusChip on a batch whose source transaction was deleted. The food did not un-exist."
  },
  "statusApproximate": "Approximate",
  "lowStockLabel": "Low",
  "expiringSoonLabel": "Expiring soon",
  "expiredLabel": "Expired",
  "overdueLabel": "Overdue",
  "dueTodayLabel": "Due today",
  "paidLabel": "Paid",
  "skippedLabel": "Skipped",
  "kindDeposit": "Money in",
  "kindWithdrawal": "Money out",
  "kindTransfer": "Transfer",
  "kindAdjustmentIncrease": "Correction up",
  "kindAdjustmentDecrease": "Correction down",
  "subtypeGrocery": "Groceries",
  "subtypeHousehold": "Household",
  "subtypeElectronics": "Electronics",
  "subtypeBill": "Bill",
  "subtypeTransferSelf": "Between my accounts",
  "subtypeTransferOut": "Sent to someone",
  "subtypeSalaryIn": "Salary",
  "subtypeOtherIn": "Other income",
  "subtypeOtherOut": "Other spending",
  "needsReviewBanner": "{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}",
  "@needsReviewBanner": {
    "description": "Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "needsReviewAction": "Review",
  "filterTitle": "Filter",
  "filterDateRange": "Date range",
  "filterKind": "Type",
  "filterSubtype": "Category",
  "filterApply": "Show results",
  "filterReset": "Reset",
  "filterChipAccount": "Account: {name}",
  "@filterChipAccount": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipPayee": "Payee: {name}",
  "@filterChipPayee": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipRange": "{label}",
  "@filterChipRange": {
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "rangeToday": "Today",
  "rangeLast7Days": "Last 7 days",
  "rangeLast30Days": "Last 30 days",
  "rangeThisMonth": "This month",
  "rangeLastMonth": "Last month",
  "rangeThisYear": "This year",
  "rangeAllTime": "All time",
  "rangeCustom": "Custom",
  "searchTransactionsHint": "Search notes",
  "transactionDeleted": "Transaction deleted",
  "quickAddTitle": "Quick add",
  "quickAddMoneyIn": "Money in",
  "quickAddMoneyOut": "Money out",
  "quickAddSave": "Save",
  "actionAddDetails": "Add details",
  "editorTitleNew": "New transaction",
  "editorTitleEdit": "Edit transaction",
  "sectionWhatAndHowMuch": "What and how much",
  "sectionWhereItCameFrom": "Where it came from",
  "sectionWhereItWent": "Where it went",
  "sectionWhatYouBought": "What you bought",
  "sectionWarranty": "Warranty",
  "sectionSchedule": "Schedule",
  "transferOwnAccount": "To my own account",
  "transferSomeoneElse": "To someone else",
  "transferOwnAccountHelp": "Moves money between your accounts. Your total does not change.",
  "transferSomeoneElseHelp": "Money leaves your accounts. This is a withdrawal.",
  "alsoAddToInventory": "Also add to inventory",
  "destinationNone": "Just an expense",
  "destinationInventory": "Save to Inventory",
  "destinationAsset": "Save to Services",
  "destinationRecurring": "Save to Recurring",
  "lineAdd": "Add item",
  "lineDescription": "Item",
  "lineUnitPrice": "Unit price",
  "lineAmount": "Line total",
  "lineCreatedLink": "Created: {name}",
  "@lineCreatedLink": {
    "description": "Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "payeeCreate": "New payee “{name}”",
  "@payeeCreate": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "saveExpense": "Save expense",
  "saveIncome": "Save income",
  "saveTransfer": "Save transfer",
  "detailSectionLines": "Items",
  "detailSectionDetails": "Details",
  "actionFreezeConversion": "Show in another currency",
  "frozenConversionNote": "Frozen on {date} at {rate}",
  "@frozenConversionNote": {
    "description": "Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).",
    "placeholders": {
      "date": {
        "type": "String"
      },
      "rate": {
        "type": "String"
      }
    }
  },
  "deleteReasonHint": "Why? (optional)",
  "actionDeleteTransaction": "Delete transaction",
  "labelSubtype": "Category",
  "labelKind": "Type",
  "themeLabTitle": "Theme Lab",
  "themeLabSubtitle": "Every token, component and semantic colour, light and dark.",
  "themeLabSectionSpacing": "Spacing",
  "themeLabSectionRadii": "Radii",
  "themeLabSectionTypography": "Typography",
  "themeLabSectionElevation": "Elevation",
  "themeLabSectionSemantic": "Semantic colours",
  "themeLabSectionSurfaces": "Surface tiers",
  "themeLabSectionComponents": "Components",
  "themeLabSectionPalettes": "Palettes",
  "themeLabLight": "Light",
  "themeLabDark": "Dark",
  "semanticIncome": "Income",
  "semanticExpense": "Expense",
  "semanticTransfer": "Transfer",
  "semanticWarning": "Warning",
  "semanticDanger": "Danger",
  "semanticSuccess": "Success",
  "semanticMuted": "Muted",
  "drawerSectionMoney": "Money",
  "drawerSectionHome": "Home",
  "drawerSectionMore": "More",
  "inventoryGroupFavourites": "Favourites",
  "@inventoryGroupFavourites": {
    "description": "Phase 6B — inventory."
  },
  "inventoryGroupUntagged": "Everything else",
  "@inventoryGroupUntagged": {
    "description": "Phase 6B — inventory."
  },
  "itemKindGeneric": "General",
  "@itemKindGeneric": {
    "description": "Phase 6B — inventory."
  },
  "itemKindFood": "Food",
  "@itemKindFood": {
    "description": "Phase 6B — inventory."
  },
  "itemKindMedicine": "Medicine",
  "@itemKindMedicine": {
    "description": "Phase 6B — inventory."
  },
  "itemKindBeauty": "Beauty",
  "@itemKindBeauty": {
    "description": "Phase 6B — inventory."
  },
  "itemKindHousehold": "Household",
  "@itemKindHousehold": {
    "description": "Phase 6B — inventory."
  },
  "itemKindOther": "Other",
  "@itemKindOther": {
    "description": "Phase 6B — inventory."
  },
  "filterFavouritesOnly": "Favourites only",
  "@filterFavouritesOnly": {
    "description": "Phase 6B — inventory."
  },
  "actionFavourite": "Add to favourites",
  "@actionFavourite": {
    "description": "Phase 6B — inventory."
  },
  "actionUnfavourite": "Remove from favourites",
  "@actionUnfavourite": {
    "description": "Phase 6B — inventory."
  },
  "outOfStockLabel": "Out of stock",
  "@outOfStockLabel": {
    "description": "Phase 6B — inventory."
  },
  "itemBatchCount": "{count, plural, =1{1 batch} other{{count} batches}}",
  "@itemBatchCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "loadingInventory": "Loading inventory",
  "@loadingInventory": {
    "description": "Phase 6B — inventory."
  },
  "detailSectionBatches": "Batches",
  "@detailSectionBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginPurchase": "From a purchase",
  "@batchOriginPurchase": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginManual": "Added by hand",
  "@batchOriginManual": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginImported": "Imported",
  "@batchOriginImported": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginAdjustment": "From an adjustment",
  "@batchOriginAdjustment": {
    "description": "Phase 6B — inventory."
  },
  "labelPurchased": "Purchased",
  "@labelPurchased": {
    "description": "Phase 6B — inventory."
  },
  "labelStorageLocation": "Stored in",
  "@labelStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "labelUnitCost": "Unit cost",
  "@labelUnitCost": {
    "description": "Phase 6B — inventory."
  },
  "labelInitial": "Bought",
  "@labelInitial": {
    "description": "Phase 6B — inventory."
  },
  "labelNearestExpiry": "Nearest expiry",
  "@labelNearestExpiry": {
    "description": "Phase 6B — inventory."
  },
  "labelDisplayUnit": "Shown in",
  "@labelDisplayUnit": {
    "description": "Phase 6B — inventory."
  },
  "labelItemKind": "Kind",
  "@labelItemKind": {
    "description": "Phase 6B — inventory."
  },
  "labelLowStockThreshold": "Low-stock level",
  "@labelLowStockThreshold": {
    "description": "Phase 6B — inventory."
  },
  "labelExpiryNotifyDays": "Warn before expiry",
  "@labelExpiryNotifyDays": {
    "description": "Phase 6B — inventory."
  },
  "actionConsume": "Use some",
  "@actionConsume": {
    "description": "Phase 6B — inventory."
  },
  "actionAddBatch": "Add a batch",
  "@actionAddBatch": {
    "description": "Phase 6B — inventory."
  },
  "actionViewHistory": "Movement history",
  "@actionViewHistory": {
    "description": "Phase 6B — inventory."
  },
  "actionDeleteItem": "Delete item",
  "@actionDeleteItem": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemTitle": "Delete this item?",
  "@confirmDeleteItemTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemBody": "Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.",
  "@confirmDeleteItemBody": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "itemDeleted": "Item deleted",
  "@itemDeleted": {
    "description": "Phase 6B — inventory."
  },
  "expiresInDays": "{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}",
  "@expiresInDays": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "expiredDaysAgo": "{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}",
  "@expiredDaysAgo": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "sectionWhatItIs": "What it is",
  "@sectionWhatItIs": {
    "description": "Phase 6B — inventory."
  },
  "sectionStockRules": "Stock rules",
  "@sectionStockRules": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryWeight": "Weight",
  "@unitCategoryWeight": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryVolume": "Volume",
  "@unitCategoryVolume": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryCount": "Count",
  "@unitCategoryCount": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryLocked": "Measured in {category}",
  "@unitCategoryLocked": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "category": {}
    }
  },
  "unitCategoryLockedHelp": "This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.",
  "@unitCategoryLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "expiryNotifyDaysHelp": "Days of warning before a batch expires.",
  "@expiryNotifyDaysHelp": {
    "description": "Phase 6B — inventory."
  },
  "labelFavourite": "Favourite",
  "@labelFavourite": {
    "description": "Phase 6B — inventory."
  },
  "saveItem": "Save item",
  "@saveItem": {
    "description": "Phase 6B — inventory."
  },
  "sectionHowMuch": "How much",
  "@sectionHowMuch": {
    "description": "Phase 6B — inventory."
  },
  "sectionBatchDetails": "Batch details",
  "@sectionBatchDetails": {
    "description": "Phase 6B — inventory."
  },
  "saveBatch": "Save batch",
  "@saveBatch": {
    "description": "Phase 6B — inventory."
  },
  "batchSaved": "Batch saved",
  "@batchSaved": {
    "description": "Phase 6B — inventory."
  },
  "hintStorageLocation": "Freezer, pantry, bathroom shelf…",
  "@hintStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "consumeTitle": "Use stock",
  "@consumeTitle": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindConsume": "Used",
  "@consumeKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindWaste": "Thrown away",
  "@consumeKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindExpired": "Expired",
  "@consumeKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "consumeRecorded": "Recorded",
  "@consumeRecorded": {
    "description": "Phase 6B — inventory."
  },
  "consumeFromLabel": "Taking from",
  "@consumeFromLabel": {
    "description": "Phase 6B — inventory."
  },
  "consumeFefoNote": "Oldest expiry first.",
  "@consumeFefoNote": {
    "description": "Phase 6B — inventory."
  },
  "consumeSpansBatches": "{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}",
  "@consumeSpansBatches": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "consumeOverAvailable": "More than you have on hand",
  "@consumeOverAvailable": {
    "description": "Phase 6B — inventory."
  },
  "historyTitle": "Movement history",
  "@historyTitle": {
    "description": "Phase 6B — inventory."
  },
  "movementKindOpeningIn": "Opening stock",
  "@movementKindOpeningIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindPurchaseIn": "Bought",
  "@movementKindPurchaseIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindManualIn": "Added by hand",
  "@movementKindManualIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindConsume": "Used",
  "@movementKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "movementKindWaste": "Thrown away",
  "@movementKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "movementKindExpired": "Expired",
  "@movementKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustIn": "Adjusted up",
  "@movementKindAdjustIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustOut": "Adjusted down",
  "@movementKindAdjustOut": {
    "description": "Phase 6B — inventory."
  },
  "movementReversed": "Reversed",
  "@movementReversed": {
    "description": "Phase 6B — inventory."
  },
  "movementIsReversal": "Reverses an earlier movement",
  "@movementIsReversal": {
    "description": "Phase 6B — inventory."
  },
  "actionReverse": "Reverse",
  "@actionReverse": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseTitle": "Reverse this movement?",
  "@confirmReverseTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseBody": "An opposite movement is appended. Nothing is erased — both entries stay in the history.",
  "@confirmReverseBody": {
    "description": "Phase 6B — inventory."
  },
  "movementReversedSnack": "Movement reversed",
  "@movementReversedSnack": {
    "description": "Phase 6B — inventory."
  },
  "emptyTitleNoMovements": "Nothing recorded yet",
  "@emptyTitleNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoMovements": "Using, wasting or adjusting this batch will show up here.",
  "@emptyBodyNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoBatches": "Add a batch and it will appear here with its expiry.",
  "@emptyBodyNoBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchQuantityLockedHelp": "How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.",
  "@batchQuantityLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "daysCount": "{days, plural, =1{1 day} other{{days} days}}",
  "@daysCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "groupByFavourites": "Group favourites first",
  "@groupByFavourites": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitUsed": "Record as used",
  "@consumeCommitUsed": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitWaste": "Record as thrown away",
  "@consumeCommitWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitExpired": "Record as expired",
  "@consumeCommitExpired": {
    "description": "Phase 6B — inventory."
  },
  "lowStockWithCount": "Low · {count}",
  "@lowStockWithCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "actionDeleteBatch": "Delete batch",
  "@actionDeleteBatch": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchTitle": "Delete this batch?",
  "@confirmDeleteBatchTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchBody": "The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.",
  "@confirmDeleteBatchBody": {
    "description": "Phase 6B — inventory."
  },
  "batchDeleted": "Batch deleted",
  "@batchDeleted": {
    "description": "Phase 6B — inventory."
  },
  "itemCreate": "New item",
  "@itemCreate": {
    "description": "Creates a catalogued item inline while itemising a receipt."
  },
  "itemCreateHint": "No items yet — create one so this line becomes stock.",
  "@itemCreateHint": {
    "description": "Shown in the line editor when the item catalogue is empty."
  },
  "itemCreateCategoryPrompt": "How is it measured? This cannot change later.",
  "@itemCreateCategoryPrompt": {
    "description": "Prompt for unitCategory on inline creation; immutable after create (Law L8)."
  },
  "itemDuplicateBody": "You already have this item, measured the same way. Open the one you have instead of adding a second.",
  "@itemDuplicateBody": {
    "description": "Shown when an item with the same normalized name and unit category exists."
  },
  "itemUnitsMissingBody": "No units are set up for this measure yet. Pick a different measure, or add units in Settings first.",
  "@itemUnitsMissingBody": {
    "description": "Shown when the chosen UnitCategory has no rows in units."
  },
  "itemSimilarNote": "You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.",
  "@itemSimilarNote": {
    "description": "Informational note, never a block: Law L8 makes same-name/different-category distinct items."
  },
  "actionOpenExisting": "Open the one I have",
  "@actionOpenExisting": {
    "description": "Opens the existing item a duplicate collides with."
  },
  "shoppingEstimate": "Estimated",
  "@shoppingEstimate": {
    "description": "Running total of estimated prices on a shopping list."
  },
  "shoppingSwitchList": "Switch list",
  "@shoppingSwitchList": {
    "description": "Opens the list manager from the app bar."
  },
  "shoppingCheckedCount": "{checked} of {total} ticked",
  "@shoppingCheckedCount": {
    "description": "Progress line above a shopping list.",
    "placeholders": {
      "checked": {},
      "total": {}
    }
  },
  "emptyTitleNoEntries": "Nothing on this list yet",
  "@emptyTitleNoEntries": {
    "description": "Shopping list empty state."
  },
  "emptyBodyNoEntries": "Add what you need, or pull in suggestions from what is running low.",
  "@emptyBodyNoEntries": {
    "description": "Shopping list empty state body."
  },
  "addEntry": "Add",
  "@addEntry": {
    "description": "Adds one entry to a shopping list."
  },
  "shoppingGroupUntagged": "Everything else",
  "@shoppingGroupUntagged": {
    "description": "Header for entries with no tag."
  },
  "actionUncheckAll": "Untick everything",
  "@actionUncheckAll": {
    "description": "Clears every tick on a shopping list."
  },
  "entryEditorTitle": "What do you need?",
  "@entryEditorTitle": {
    "description": "Entry editor sheet title."
  },
  "entryFreeTextLabel": "Name it",
  "@entryFreeTextLabel": {
    "description": "Free-text label for a shopping entry."
  },
  "entryFreeTextHint": "Television, birthday card, light bulbs…",
  "@entryFreeTextHint": {
    "description": "Hint showing that an entry need not be an inventory item."
  },
  "entryLinkItem": "Link to an item",
  "@entryLinkItem": {
    "description": "Optional link from a shopping entry to a catalogued item."
  },
  "entryNoItem": "Not in my inventory",
  "@entryNoItem": {
    "description": "Dropdown option leaving itemId null."
  },
  "labelEstimatedPrice": "Estimated price",
  "@labelEstimatedPrice": {
    "description": "Optional per-entry price estimate."
  },
  "entryNeedsSomething": "Give it a name, or link it to an item",
  "@entryNeedsSomething": {
    "description": "Rejection when neither freeText nor itemId is set."
  },
  "originAutoLowStock": "Suggested",
  "@originAutoLowStock": {
    "description": "Chip marking an auto-generated low-stock entry."
  },
  "originPromoted": "Yours now",
  "@originPromoted": {
    "description": "Chip shown once an auto entry has been edited into a manual one."
  },
  "actionSnooze": "Snooze a week",
  "@actionSnooze": {
    "description": "Hides an auto suggestion until a later date."
  },
  "actionDismiss": "Not now",
  "@actionDismiss": {
    "description": "Dismisses an auto suggestion until stock recovers and drops again."
  },
  "snoozedUntilLabel": "Snoozed until",
  "@snoozedUntilLabel": {
    "description": "Precedes a DateText on a snoozed entry."
  },
  "generateTitle": "Running low",
  "@generateTitle": {
    "description": "Low-stock suggestion sheet title."
  },
  "generateBody": "These are below the level you set. Add the ones you want.",
  "@generateBody": {
    "description": "Low-stock suggestion sheet body."
  },
  "generateShortBy": "Short by",
  "@generateShortBy": {
    "description": "Precedes a QtyText giving threshold minus stock on hand."
  },
  "generateRefresh": "Check again",
  "@generateRefresh": {
    "description": "Re-runs low-stock generation."
  },
  "generateEmptyTitle": "Nothing is running low",
  "@generateEmptyTitle": {
    "description": "Generate sheet empty state."
  },
  "generateEmptyBody": "Set a low-stock level on an item and it will show up here when it drops.",
  "@generateEmptyBody": {
    "description": "Generate sheet empty state body."
  },
  "generateAdded": "{count, plural, =1{1 suggestion added} other{{count} suggestions added}}",
  "@generateAdded": {
    "description": "Result snack after regeneration.",
    "placeholders": {
      "count": {}
    }
  },
  "convertTitle": "Turn into a purchase",
  "@convertTitle": {
    "description": "Convert-to-purchase screen title."
  },
  "convertBody": "Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.",
  "@convertBody": {
    "description": "Explains the handoff to the expense editor."
  },
  "convertConfirm": "Open the expense",
  "@convertConfirm": {
    "description": "Primary action; hands off to the 6A editor."
  },
  "convertNothingTitle": "Nothing is ticked",
  "@convertNothingTitle": {
    "description": "Convert screen empty state."
  },
  "convertNothingBody": "Tick what you actually bought, then come back.",
  "@convertNothingBody": {
    "description": "Convert screen empty state body."
  },
  "convertLineCount": "{count, plural, =1{1 line} other{{count} lines}}",
  "@convertLineCount": {
    "description": "How many lines the draft will carry.",
    "placeholders": {
      "count": {}
    }
  },
  "listManagerTitle": "Your lists",
  "@listManagerTitle": {
    "description": "List manager sheet title."
  },
  "listNameLabel": "List name",
  "@listNameLabel": {
    "description": "Field label when creating or renaming a list."
  },
  "listCreate": "New list",
  "@listCreate": {
    "description": "Creates a shopping list."
  },
  "listRename": "Rename",
  "@listRename": {
    "description": "Renames a shopping list."
  },
  "listSetDefault": "Make default",
  "@listSetDefault": {
    "description": "Marks a list as the one that opens by default."
  },
  "listDefaultBadge": "Default",
  "@listDefaultBadge": {
    "description": "Chip on the default list."
  },
  "listArchive": "Archive",
  "@listArchive": {
    "description": "Archives a shopping list."
  },
  "listUnarchive": "Restore",
  "@listUnarchive": {
    "description": "Un-archives a shopping list."
  },
  "listArchivedBadge": "Archived",
  "@listArchivedBadge": {
    "description": "Chip on an archived list."
  },
  "listArchivedSection": "Archived",
  "@listArchivedSection": {
    "description": "Section header for archived lists."
  },
  "emptyTitleNoLists": "No lists yet",
  "@emptyTitleNoLists": {
    "description": "List manager empty state."
  },
  "emptyBodyNoLists": "Create one and it becomes your default.",
  "@emptyBodyNoLists": {
    "description": "List manager empty state body."
  },
  "loadingShopping": "Loading your list",
  "@loadingShopping": {
    "description": "Skeleton label for shopping surfaces."
  },
  "actionAddToList": "Add to my list",
  "@actionAddToList": {
    "description": "Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone."
  },
  "suggestionDismissed": "Turned down",
  "@suggestionDismissed": {
    "description": "Chip on a dismissed suggestion; it stays listed so it can be accepted later."
  },
  "lineItemsTitle": "What you bought",
  "@lineItemsTitle": {
    "description": "Title of the dedicated line-items page."
  },
  "lineItemsManage": "Add or edit items",
  "@lineItemsManage": {
    "description": "Opens the line-items page from the transaction editor."
  },
  "lineItemsAdd": "Add an item",
  "@lineItemsAdd": {
    "description": "Adds one line from the line-items page."
  },
  "lineItemsSaveAndAnother": "Save & add another",
  "@lineItemsSaveAndAnother": {
    "description": "Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet."
  },
  "lineItemsCount": "{count, plural, =0{No items yet} =1{1 item} other{{count} items}}",
  "@lineItemsCount": {
    "description": "Running count on the line-items page.",
    "placeholders": {
      "count": {}
    }
  },
  "emptyTitleNoLineItems": "Nothing itemised yet",
  "@emptyTitleNoLineItems": {
    "description": "Line-items page empty state."
  },
  "emptyBodyNoLineItems": "Add what was on the receipt. Anything you leave out still counts toward the total.",
  "@emptyBodyNoLineItems": {
    "description": "Line-items page empty state body."
  },
  "actionRemove": "Remove",
  "@actionRemove": {
    "description": "Removes one line from a transaction."
  },
  "lineRemoved": "Item removed",
  "@lineRemoved": {
    "description": "Snack after removing a line."
  },
  "lineItemsAllocated": "Itemised",
  "@lineItemsAllocated": {
    "description": "Precedes the summed line total on the line-items page."
  },
  "recurringOutflow": "Going out",
  "@recurringOutflow": {
    "description": "Group header for outflow templates."
  },
  "recurringInflow": "Coming in",
  "@recurringInflow": {
    "description": "Group header for inflow templates — salary reads as income, not a negative bill."
  },
  "recurringNextDue": "Next",
  "@recurringNextDue": {
    "description": "Precedes a DateText giving the next due date."
  },
  "recurringOverdue": "Overdue",
  "@recurringOverdue": {
    "description": "Chip on an occurrence past its due date. Derived from the clock, never stored."
  },
  "recurringPaused": "Paused",
  "@recurringPaused": {
    "description": "Chip on a paused template."
  },
  "recurringDueToday": "Due today",
  "@recurringDueToday": {
    "description": "Chip when the next occurrence falls today."
  },
  "emptyTitleNoTemplates": "Nothing recurring yet",
  "@emptyTitleNoTemplates": {
    "description": "Template list empty state."
  },
  "emptyBodyNoTemplates": "Add a bill, a subscription or a salary and it will appear here when it is next due.",
  "@emptyBodyNoTemplates": {
    "description": "Template list empty state body."
  },
  "addTemplate": "Add",
  "@addTemplate": {
    "description": "Adds a recurring template."
  },
  "actionPause": "Pause",
  "@actionPause": {
    "description": "Pauses a template."
  },
  "actionResume": "Resume",
  "@actionResume": {
    "description": "Resumes a paused template."
  },
  "loadingRecurring": "Loading your schedule",
  "@loadingRecurring": {
    "description": "Skeleton label for recurring surfaces."
  },
  "builderSectionWhat": "What it is",
  "@builderSectionWhat": {
    "description": "First section of the template builder."
  },
  "builderSectionWhen": "How often",
  "@builderSectionWhen": {
    "description": "Frequency section of the template builder."
  },
  "builderSectionDefaults": "Defaults",
  "@builderSectionDefaults": {
    "description": "Amount and account section of the template builder."
  },
  "labelTemplateName": "Name",
  "@labelTemplateName": {
    "description": "Template name field."
  },
  "labelRecurringKind": "Kind",
  "@labelRecurringKind": {
    "description": "Bill, subscription, rent or salary."
  },
  "labelDirection": "Direction",
  "@labelDirection": {
    "description": "Whether money goes out or comes in."
  },
  "directionOutflow": "Money out",
  "@directionOutflow": {
    "description": "RecurringDirection.outflow."
  },
  "directionInflow": "Money in",
  "@directionInflow": {
    "description": "RecurringDirection.inflow."
  },
  "kindBill": "Bill",
  "@kindBill": {
    "description": "RecurringKind.bill."
  },
  "kindSubscription": "Subscription",
  "@kindSubscription": {
    "description": "RecurringKind.subscription."
  },
  "kindRent": "Rent",
  "@kindRent": {
    "description": "RecurringKind.rent."
  },
  "kindSalary": "Salary",
  "@kindSalary": {
    "description": "RecurringKind.salary."
  },
  "labelEvery": "Every",
  "@labelEvery": {
    "description": "Precedes the interval count and unit."
  },
  "unitDay": "{count, plural, =1{day} other{days}}",
  "@unitDay": {
    "description": "RecurringIntervalUnit.day.",
    "placeholders": {
      "count": {}
    }
  },
  "unitWeek": "{count, plural, =1{week} other{weeks}}",
  "@unitWeek": {
    "description": "RecurringIntervalUnit.week.",
    "placeholders": {
      "count": {}
    }
  },
  "unitMonth": "{count, plural, =1{month} other{months}}",
  "@unitMonth": {
    "description": "RecurringIntervalUnit.month.",
    "placeholders": {
      "count": {}
    }
  },
  "unitYear": "{count, plural, =1{year} other{years}}",
  "@unitYear": {
    "description": "RecurringIntervalUnit.year.",
    "placeholders": {
      "count": {}
    }
  },
  "labelAnchorDay": "On day of the month",
  "@labelAnchorDay": {
    "description": "anchorDayOfMonth. Stored once, clamped at render (anomaly A13)."
  },
  "anchorDayHelp": "Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.",
  "@anchorDayHelp": {
    "description": "Explains that the anchor never walks backwards."
  },
  "labelStartDate": "Starts",
  "@labelStartDate": {
    "description": "startDateKey."
  },
  "labelEndDate": "Ends",
  "@labelEndDate": {
    "description": "endDateKey, optional."
  },
  "labelDefaultAmount": "Usual amount",
  "@labelDefaultAmount": {
    "description": "defaultAmount — a default, not a fixed figure."
  },
  "labelRemindBefore": "Remind me",
  "@labelRemindBefore": {
    "description": "remindDaysBefore."
  },
  "saveTemplate": "Save",
  "@saveTemplate": {
    "description": "Commits the template."
  },
  "previewTitle": "Next three",
  "@previewTitle": {
    "description": "Header of the frequency preview."
  },
  "previewEmpty": "Set a start date to see when this lands.",
  "@previewEmpty": {
    "description": "Frequency preview with nothing to show."
  },
  "previewClamped": "Shortened to fit the month",
  "@previewClamped": {
    "description": "Marks a previewed date the anchor could not reach."
  },
  "payTitle": "Record this payment",
  "@payTitle": {
    "description": "Pay sheet title."
  },
  "payTitleInflow": "Record this receipt",
  "@payTitleInflow": {
    "description": "Pay sheet title for an inflow."
  },
  "labelActualAmount": "Amount actually paid",
  "@labelActualAmount": {
    "description": "The real figure, which may differ from the default."
  },
  "labelActualAmountInflow": "Amount actually received",
  "@labelActualAmountInflow": {
    "description": "Inflow wording for the same field."
  },
  "payUsualWas": "Usually",
  "@payUsualWas": {
    "description": "Precedes the default amount when the actual differs from it."
  },
  "labelPaidOn": "Paid on",
  "@labelPaidOn": {
    "description": "paidDateKey."
  },
  "payCommit": "Record it",
  "@payCommit": {
    "description": "Commits the payment and creates the transaction."
  },
  "payRecorded": "Recorded",
  "@payRecorded": {
    "description": "Result snack after paying."
  },
  "payNeedsAccount": "Choose which account it came from",
  "@payNeedsAccount": {
    "description": "Rejection when no account is selected."
  },
  "payUndoTitle": "Undo this payment?",
  "@payUndoTitle": {
    "description": "Confirmation before undoing."
  },
  "payUndoBody": "The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.",
  "@payUndoBody": {
    "description": "Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4)."
  },
  "payUndone": "Payment undone",
  "@payUndone": {
    "description": "Result snack after undoing."
  },
  "actionSkip": "Skip this one",
  "@actionSkip": {
    "description": "Marks an occurrence deliberately skipped."
  },
  "occurrenceSkipped": "Skipped",
  "@occurrenceSkipped": {
    "description": "Chip on a skipped occurrence, and the snack after skipping."
  },
  "historyRecurringTitle": "Payment history",
  "@historyRecurringTitle": {
    "description": "Occurrence history screen title."
  },
  "historyDefaultVsActual": "Differed from the usual amount",
  "@historyDefaultVsActual": {
    "description": "Badge when paidAmount != defaultAmount."
  },
  "emptyTitleNoOccurrences": "Nothing due yet",
  "@emptyTitleNoOccurrences": {
    "description": "Occurrence history empty state."
  },
  "emptyBodyNoOccurrences": "Occurrences appear as their due dates arrive. Nothing is ever paid for you.",
  "@emptyBodyNoOccurrences": {
    "description": "Empty state body, stating anomaly A14 plainly."
  },
  "statusDue": "Due",
  "@statusDue": {
    "description": "RecurringOccurrenceStatus.due."
  },
  "statusPaid": "Paid",
  "@statusPaid": {
    "description": "RecurringOccurrenceStatus.paid."
  },
  "statusDismissed": "Dismissed",
  "@statusDismissed": {
    "description": "RecurringOccurrenceStatus.dismissed."
  },
  "kindServiceFee": "Service fee",
  "@kindServiceFee": {
    "description": "RecurringKind.serviceFee — a recurring charge tied to an asset."
  },
  "kindOther": "Something else",
  "@kindOther": {
    "description": "RecurringKind.other — anything the named kinds do not cover."
  },
  "billDueSection": "Due now",
  "@billDueSection": {
    "description": "Header above the recurring bills a payment can settle."
  },
  "billSetUpAction": "Set up a recurring bill",
  "@billSetUpAction": {
    "description": "Opens the template builder from the bill form."
  },
  "billNothingDue": "Nothing is due right now.",
  "@billNothingDue": {
    "description": "Shown in the bill form when no occurrence is outstanding."
  },
  "recurringScheduleNext": "Saved. Now set how often it repeats.",
  "@recurringScheduleNext": {
    "description": "Snack after a line asked to become recurring."
  },
  "recurringNotYetDue": "Not due yet",
  "@recurringNotYetDue": {
    "description": "Chip when the next occurrence has not materialised."
  },
  "billSettlesLabel": "Settling",
  "@billSettlesLabel": {
    "description": "Precedes the recurring bill this payment will settle."
  },
  "billSettleNone": "Not a recurring bill",
  "@billSettleNone": {
    "description": "Option that leaves the payment unlinked to any template."
  },
  "billSettleHelp": "Pick one and the amount below becomes what you actually paid. Saving records it once.",
  "@billSettleHelp": {
    "description": "Explains that the editor is the single write path for a bill payment."
  },
  "billAmountBecomesPaid": "This amount is what gets recorded",
  "@billAmountBecomesPaid": {
    "description": "Helper under the amount when a bill is selected."
  },
  "billAccountAuto": "Paid from",
  "@billAccountAuto": {
    "description": "Precedes the account resolved automatically for a bill payment."
  },
  "billAccountAskOnce": "Which account does this come from? Alaya remembers it on the bill.",
  "@billAccountAskOnce": {
    "description": "Shown only when no template default, no app default and more than one account exist."
  },
  "assetGroupAppliance": "Appliances",
  "@assetGroupAppliance": {
    "description": "AssetType.appliance group header."
  },
  "assetGroupElectronics": "Electronics",
  "@assetGroupElectronics": {
    "description": "AssetType.electronics."
  },
  "assetGroupVehicle": "Vehicles",
  "@assetGroupVehicle": {
    "description": "AssetType.vehicle."
  },
  "assetGroupFurniture": "Furniture",
  "@assetGroupFurniture": {
    "description": "AssetType.furniture."
  },
  "assetGroupProperty": "Property",
  "@assetGroupProperty": {
    "description": "AssetType.property."
  },
  "assetGroupServiceProvider": "People",
  "@assetGroupServiceProvider": {
    "description": "AssetType.serviceProvider — a maid or gardener lives here, not in a second system."
  },
  "assetGroupSubscription": "Subscriptions",
  "@assetGroupSubscription": {
    "description": "AssetType.subscription."
  },
  "assetGroupOther": "Other",
  "@assetGroupOther": {
    "description": "AssetType.other."
  },
  "assetUnderWarranty": "In warranty",
  "@assetUnderWarranty": {
    "description": "Chip when warrantyEndDateKey is still ahead."
  },
  "assetWarrantyEnding": "Warranty ending",
  "@assetWarrantyEnding": {
    "description": "Chip when the warranty ends soon."
  },
  "assetWarrantyExpired": "Out of warranty",
  "@assetWarrantyExpired": {
    "description": "Chip when the warranty has passed."
  },
  "assetServiceDue": "Service due",
  "@assetServiceDue": {
    "description": "Chip when nextServiceDueDateKey has passed."
  },
  "assetServiceSoon": "Service soon",
  "@assetServiceSoon": {
    "description": "Chip when a service is close."
  },
  "assetDisposedChip": "Disposed",
  "@assetDisposedChip": {
    "description": "Chip on a disposed asset."
  },
  "assetUnderRepair": "Being repaired",
  "@assetUnderRepair": {
    "description": "AssetStatus.underRepair."
  },
  "filterShowDisposed": "Include disposed",
  "@filterShowDisposed": {
    "description": "Filter that brings disposed assets back into the list."
  },
  "emptyTitleNoAssets": "Nothing tracked yet",
  "@emptyTitleNoAssets": {
    "description": "Asset list empty state."
  },
  "emptyBodyNoAssets": "Add an appliance, a vehicle, or the person who helps around the house — they all live here.",
  "@emptyBodyNoAssets": {
    "description": "Asset list empty state body, stating the serviceProvider case plainly."
  },
  "addAsset": "Add",
  "@addAsset": {
    "description": "Adds an asset."
  },
  "loadingAssets": "Loading your things",
  "@loadingAssets": {
    "description": "Skeleton label for service surfaces."
  },
  "assetSectionIdentity": "Details",
  "@assetSectionIdentity": {
    "description": "Identity section on the detail screen."
  },
  "assetSectionWarranty": "Warranty",
  "@assetSectionWarranty": {
    "description": "Warranty section."
  },
  "assetSectionContact": "Contact",
  "@assetSectionContact": {
    "description": "Contact block."
  },
  "assetSectionService": "Service history",
  "@assetSectionService": {
    "description": "Service records section."
  },
  "assetSectionSalary": "Salary history",
  "@assetSectionSalary": {
    "description": "Service records section for a serviceProvider."
  },
  "assetLifetimeCost": "Spent on service so far",
  "@assetLifetimeCost": {
    "description": "Sum of every service record cost."
  },
  "assetLifetimeSalary": "Paid so far",
  "@assetLifetimeSalary": {
    "description": "The same figure for a serviceProvider."
  },
  "labelBrand": "Brand",
  "@labelBrand": {
    "description": "assets.brand."
  },
  "labelModelNo": "Model",
  "@labelModelNo": {
    "description": "assets.modelNo."
  },
  "labelSerialNo": "Serial",
  "@labelSerialNo": {
    "description": "assets.serialNo."
  },
  "labelPurchasePrice": "Bought for",
  "@labelPurchasePrice": {
    "description": "assets.purchasePrice."
  },
  "labelWarrantyStart": "Warranty from",
  "@labelWarrantyStart": {
    "description": "assets.warrantyStartDateKey."
  },
  "labelWarrantyEnd": "Warranty until",
  "@labelWarrantyEnd": {
    "description": "assets.warrantyEndDateKey."
  },
  "labelWarrantyProvider": "Covered by",
  "@labelWarrantyProvider": {
    "description": "assets.warrantyProvider."
  },
  "labelServiceInterval": "Service every",
  "@labelServiceInterval": {
    "description": "assets.serviceIntervalDays."
  },
  "labelNextService": "Next service",
  "@labelNextService": {
    "description": "assets.nextServiceDueDateKey."
  },
  "labelContactName": "Name",
  "@labelContactName": {
    "description": "assets.primaryContactName."
  },
  "labelContactPhone": "Phone",
  "@labelContactPhone": {
    "description": "assets.primaryContactPhone."
  },
  "labelLocation": "Kept in",
  "@labelLocation": {
    "description": "assets.location."
  },
  "actionCall": "Call",
  "@actionCall": {
    "description": "Dials primaryContactPhone."
  },
  "callFailed": "No app on this phone can place that call.",
  "@callFailed": {
    "description": "Shown when the tel: intent finds no handler."
  },
  "actionAddService": "Record a service",
  "@actionAddService": {
    "description": "Adds a service record."
  },
  "actionAddSalary": "Record a payment",
  "@actionAddSalary": {
    "description": "The same action for a serviceProvider."
  },
  "actionDispose": "Dispose of it",
  "@actionDispose": {
    "description": "Opens the dispose sheet."
  },
  "actionUndispose": "Bring it back",
  "@actionUndispose": {
    "description": "Reverses a disposal."
  },
  "assetLinkedRecurring": "Paid on a schedule",
  "@assetLinkedRecurring": {
    "description": "Chip when linkedRecurringTemplateId is set."
  },
  "emptyBodyNoServices": "Nothing recorded against this yet.",
  "@emptyBodyNoServices": {
    "description": "Empty service history."
  },
  "labelAssetName": "What is it?",
  "@labelAssetName": {
    "description": "assets.name."
  },
  "labelAssetType": "Kind",
  "@labelAssetType": {
    "description": "assets.type."
  },
  "assetTypeHelpPerson": "A person you pay regularly belongs here too — their payments become service records.",
  "@assetTypeHelpPerson": {
    "description": "Explains AssetType.serviceProvider when it is chosen."
  },
  "saveAsset": "Save",
  "@saveAsset": {
    "description": "Commits an asset."
  },
  "serviceIntervalHelp": "Days between services. The next due date moves on each time you record one.",
  "@serviceIntervalHelp": {
    "description": "Explains serviceIntervalDays."
  },
  "labelServiceType": "What happened",
  "@labelServiceType": {
    "description": "service_records.type."
  },
  "serviceTypeService": "Serviced",
  "@serviceTypeService": {
    "description": "ServiceRecordType.service."
  },
  "serviceTypeRepair": "Repaired",
  "@serviceTypeRepair": {
    "description": "ServiceRecordType.repair."
  },
  "serviceTypeMaintenance": "Maintenance",
  "@serviceTypeMaintenance": {
    "description": "ServiceRecordType.maintenance."
  },
  "serviceTypeInspection": "Inspection",
  "@serviceTypeInspection": {
    "description": "ServiceRecordType.inspection."
  },
  "serviceTypeSalaryPaid": "Salary paid",
  "@serviceTypeSalaryPaid": {
    "description": "ServiceRecordType.salaryPaid — the maid case."
  },
  "serviceTypeOther": "Something else",
  "@serviceTypeOther": {
    "description": "ServiceRecordType.other."
  },
  "labelProviderName": "Who did it",
  "@labelProviderName": {
    "description": "service_records.providerName."
  },
  "labelProviderPhone": "Their number",
  "@labelProviderPhone": {
    "description": "service_records.providerPhone."
  },
  "labelServiceDate": "When",
  "@labelServiceDate": {
    "description": "service_records.serviceDateKey."
  },
  "labelServiceCost": "Cost",
  "@labelServiceCost": {
    "description": "service_records.cost."
  },
  "labelNextDue": "Next one due",
  "@labelNextDue": {
    "description": "service_records.nextDueDateKey."
  },
  "alsoRecordAsExpense": "Also record it as an expense",
  "@alsoRecordAsExpense": {
    "description": "The alsoRecordAsExpense toggle."
  },
  "alsoRecordHelp": "Writes a withdrawal for the cost as well, so it shows in your ledger.",
  "@alsoRecordHelp": {
    "description": "Explains what the toggle writes."
  },
  "alsoRecordNeedsAccount": "Choose which account it comes from",
  "@alsoRecordNeedsAccount": {
    "description": "Rejection when the toggle is on with no account."
  },
  "alsoRecordNeedsCost": "Add a cost first",
  "@alsoRecordNeedsCost": {
    "description": "Rejection when the toggle is on with no cost."
  },
  "saveService": "Save",
  "@saveService": {
    "description": "Commits a service record."
  },
  "disposeTitle": "What happened to it?",
  "@disposeTitle": {
    "description": "Dispose sheet title."
  },
  "disposeBody": "It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.",
  "@disposeBody": {
    "description": "States anomaly A30 plainly: an asset is never deleted."
  },
  "disposeReasonSold": "Sold it",
  "@disposeReasonSold": {
    "description": "AssetDisposalReason.sold."
  },
  "disposeReasonExpired": "Wore out",
  "@disposeReasonExpired": {
    "description": "AssetDisposalReason.expired."
  },
  "disposeReasonDamaged": "Broke",
  "@disposeReasonDamaged": {
    "description": "AssetDisposalReason.damaged."
  },
  "disposeReasonGifted": "Gave it away",
  "@disposeReasonGifted": {
    "description": "AssetDisposalReason.gifted."
  },
  "disposeReasonLost": "Lost it",
  "@disposeReasonLost": {
    "description": "AssetDisposalReason.lost."
  },
  "disposeReasonReplaced": "Replaced it",
  "@disposeReasonReplaced": {
    "description": "AssetDisposalReason.replaced."
  },
  "disposeReasonOther": "Something else",
  "@disposeReasonOther": {
    "description": "AssetDisposalReason.other."
  },
  "labelDisposalAmount": "Got back",
  "@labelDisposalAmount": {
    "description": "assets.disposalAmount — what the disposal recovered."
  },
  "labelDisposalDate": "When",
  "@labelDisposalDate": {
    "description": "assets.disposedAtDateKey."
  },
  "disposeCommit": "Record it",
  "@disposeCommit": {
    "description": "Commits the disposal."
  },
  "disposeDone": "Recorded",
  "@disposeDone": {
    "description": "Snack after disposing."
  },
  "undisposeDone": "Back in your list",
  "@undisposeDone": {
    "description": "Snack after un-disposing."
  },
  "disposeNeedsReason": "Pick what happened",
  "@disposeNeedsReason": {
    "description": "Rejection when no reason is chosen."
  },
  "hintSearchAssets": "Search your things and people",
  "@hintSearchAssets": {
    "description": "Search hint on the asset list."
  },
  "errorWarrantyBackwards": "The warranty cannot end before it starts",
  "@errorWarrantyBackwards": {
    "description": "Field error when warrantyEndDateKey precedes warrantyStartDateKey."
  },
  "sectionMoney": "Money",
  "@sectionMoney": {
    "description": "Header above the cost and expense controls on the service editor."
  },
  "assetCreatedFromPurchase": "Saved. Now say what it is and how long it is covered.",
  "@assetCreatedFromPurchase": {
    "description": "Snack after a purchase line created an asset."
  },
  "destinationHelpNone": "Recorded as spending and nothing else.",
  "@destinationHelpNone": {
    "description": "Explains destination none."
  },
  "destinationHelpInventory": "Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.",
  "@destinationHelpInventory": {
    "description": "Explains destination inventory."
  },
  "destinationHelpAsset": "A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.",
  "@destinationHelpAsset": {
    "description": "Explains destination asset."
  },
  "destinationHelpRecurring": "Sets up a schedule so this comes back every month.",
  "@destinationHelpRecurring": {
    "description": "Explains destination recurring."
  },
  "assetSameNameNote": "You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.",
  "@assetSameNameNote": {
    "description": "Informational note when an asset name repeats. Never a block: five iPhones are five assets."
  },
  "@destinationNone": {
    "description": "No artefact. Recorded as spending and nothing else."
  },
  "@destinationInventory": {
    "description": "Creates stock. Names the Inventory module, matching navInventory."
  },
  "@destinationAsset": {
    "description": "Creates an asset. Names the Services module, matching navServices."
  },
  "@destinationRecurring": {
    "description": "Hands off to the template builder. Matches navRecurring."
  },
  "actionSetWarranty": "Set the warranty",
  "@actionSetWarranty": {
    "description": "Snack action opening the asset a purchase line created."
  },
  "labelPaymentMethodOptional": "How you paid (optional)",
  "@labelPaymentMethodOptional": {
    "description": "Optional payment method on the service editor. Travels to the expense, never onto the record."
  },
  "dashboardTitle": "Home",
  "@dashboardTitle": {
    "description": "Dashboard screen title."
  },
  "fundsAvailable": "Total available funds",
  "@fundsAvailable": {
    "description": "Label above the one headline figure on the dashboard."
  },
  "fundsUnconverted": "{count, plural, =1{1 balance not converted} other{{count} balances not converted}}",
  "@fundsUnconverted": {
    "description": "Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).",
    "placeholders": {
      "count": {}
    }
  },
  "fundsApproximate": "Rate is older than today",
  "@fundsApproximate": {
    "description": "Chip when the conversion used the most recent rate on or before today."
  },
  "fundsWhyExcluded": "Balances Alaya has no rate for are left out rather than guessed at.",
  "@fundsWhyExcluded": {
    "description": "Explains why the headline may be lower than the sum of every account."
  },
  "rangeLast30": "Last 30 days",
  "@rangeLast30": {
    "description": "Range label. Always stated, never implied (anomaly A33)."
  },
  "rangeMoneyIn": "In",
  "@rangeMoneyIn": {
    "description": "Deposits over the labelled range."
  },
  "rangeMoneyOut": "Out",
  "@rangeMoneyOut": {
    "description": "Withdrawals over the labelled range."
  },
  "rangeNothingYet": "Nothing yet",
  "@rangeNothingYet": {
    "description": "Shown in place of a figure when a range holds no transactions."
  },
  "rangeExcluded": "{count, plural, =1{1 left out} other{{count} left out}}",
  "@rangeExcluded": {
    "description": "Chip when transactions in a foreign currency could not be converted into the range total.",
    "placeholders": {
      "count": {}
    }
  },
  "insightUpcoming": "Coming up",
  "@insightUpcoming": {
    "description": "The calendar side of the switchable insight card."
  },
  "insightSpending": "Where it went",
  "@insightSpending": {
    "description": "The analytics side of the switchable insight card."
  },
  "insightSwitchLabel": "Show",
  "@insightSwitchLabel": {
    "description": "Semantics label for the insight card switch."
  },
  "insightNothingUpcoming": "Nothing needs attention in the next fortnight.",
  "@insightNothingUpcoming": {
    "description": "Empty state for the upcoming side."
  },
  "insightAnalyticsPending": "Spending breakdowns arrive with the analytics module.",
  "@insightAnalyticsPending": {
    "description": "Honest empty state: AnalyticsService has no data adapter until Phase 7B (ARCH_4 §5.1 item 15)."
  },
  "insightBillDue": "Bill due",
  "@insightBillDue": {
    "description": "Upcoming row for a recurring occurrence."
  },
  "insightServiceDue": "Service due",
  "@insightServiceDue": {
    "description": "Upcoming row for an asset needing service."
  },
  "insightWarrantyEnding": "Warranty ending",
  "@insightWarrantyEnding": {
    "description": "Upcoming row for an expiring warranty."
  },
  "insightBatchExpiring": "Expiring",
  "@insightBatchExpiring": {
    "description": "Upcoming row for a batch past or near its expiry."
  },
  "moduleGridTitle": "Where to next",
  "@moduleGridTitle": {
    "description": "Header above the navigation tiles."
  },
  "moduleExpenses": "{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}",
  "@moduleExpenses": {
    "description": "Live number on the Expenses tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleInventory": "{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}",
  "@moduleInventory": {
    "description": "Live number on the Inventory tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleShopping": "{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}",
  "@moduleShopping": {
    "description": "Live number on the Shopping tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleRecurring": "{count, plural, =0{all settled} =1{1 due} other{{count} due}}",
  "@moduleRecurring": {
    "description": "Live number on the Recurring tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleServices": "{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}",
  "@moduleServices": {
    "description": "Live number on the Services tile.",
    "placeholders": {
      "count": {}
    }
  },
  "fabAddIncome": "Money in",
  "@fabAddIncome": {
    "description": "FAB action opening the editor as a deposit."
  },
  "fabAddItem": "New item",
  "@fabAddItem": {
    "description": "FAB action opening the item editor."
  },
  "loadingDashboard": "Adding it up",
  "@loadingDashboard": {
    "description": "Skeleton label for the dashboard."
  },
  "fabOpenLabel": "Add something",
  "@fabOpenLabel": {
    "description": "Semantics label for the closed expandable FAB."
  },
  "fabCloseLabel": "Close",
  "@fabCloseLabel": {
    "description": "Semantics label for the open expandable FAB."
  },
  "eventTypeTransaction": "Transaction",
  "eventTypeRecurringDue": "Recurring bill",
  "eventTypeBatchExpiry": "Expiring",
  "eventTypeWarrantyEnd": "Warranty ending",
  "eventTypeServiceDue": "Service due",
  "eventTypeShoppingTarget": "Shopping target",
  "calendarSeverityWarning": "Needs attention",
  "calendarSeverityDanger": "Past its date",
  "calendarLoadingDay": "Loading this day…",
  "calendarDayErrorTitle": "Could not load this day",
  "calendarDayEmptyTitle": "Nothing on this day",
  "calendarDayEmptyBody": "No transactions, bills, expiries or services fall here.",
  "calendarRetry": "Try again",
  "calendarLoadingMonth": "Loading this month…",
  "calendarErrorTitle": "Could not load the calendar",
  "calendarPreviousMonth": "Previous month",
  "calendarNextMonth": "Next month",
  "calendarOnDay": "On this day",
  "calendarRangeOn": "Select a range",
  "calendarRangeOff": "Stop selecting a range",
  "calendarRangePickEnd": "From {start} — tap another day to finish.",
  "calendarInRange": "{count, plural, =1{1 day} other{{count} days}}",
  "calendarRangeEmptyTitle": "Nothing in these days",
  "calendarRangeEmptyBody": "No transactions, bills, expiries or services fall inside the range.",
  "@calendarRangePickEnd": {
    "description": "Prompt after the range start is chosen.",
    "placeholders": {
      "start": {
        "type": "String"
      }
    }
  },
  "@calendarInRange": {
    "description": "How many days the chosen range spans.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "calendarBackToToday": "Back to this month",
  "calendarTotalOut": "Spent",
  "calendarTotalIn": "Received",
  "dashboardOpenCalendar": "Open calendar",
  "dashboardCalendarSemantics": "{month} at a glance. Opens the calendar.",
  "@dashboardCalendarSemantics": {
    "description": "Screen-reader label for the dashboard month card where days are too narrow to tap.",
    "placeholders": {
      "month": {
        "type": "String"
      }
    }
  },
  "navBackToDashboard": "Back to dashboard"
}
```

### `lib/app/router/routes.dart`

```dart
/// Every route path in the app, in one place.
///
/// Hand-written: `go_router_builder` cannot resolve alongside `drift_dev` (ARCH_1 §7.1). A literal
/// path anywhere else is a route that drifts silently when this file changes.
abstract final class Routes {
  /// Where the app opens.
  static const String initial = dashboard;

  // ── top level, inside the drawer shell ──

  /// The dashboard.
  static const String dashboard = '/';

  /// The transaction ledger.
  static const String expenses = '/expenses';

  /// The inventory catalogue.
  static const String inventory = '/inventory';

  /// The shopping lists.
  static const String shopping = '/shopping';

  /// The recurring templates.
  static const String recurring = '/recurring';

  /// The assets and service records.
  static const String services = '/services';

  /// The calendar.
  static const String calendar = '/calendar';

  /// The insights.
  static const String insights = '/insights';

  /// The settings.
  static const String settings = '/settings';

  // ── outside the shell: full-screen editors and the lock ──

  /// The PIN gate.
  static const String lock = '/lock';

  /// The palette workbench.
  static const String themeLab = '/settings/theme-lab';

  /// A new transaction.
  static const String transactionNew = '/expenses/new';

  /// The line items of a new transaction.
  static const String transactionLinesNew = '/expenses/new/lines';

  /// A new item.
  static const String itemNew = '/inventory/new';

  /// A new recurring template.
  static const String recurringNew = '/recurring/new';

  /// A new asset.
  static const String assetNew = '/services/new';

  // ── parameterised ──

  /// Path pattern for one transaction.
  static const String transactionDetailPattern = '/expenses/:transactionId';

  /// Path pattern for editing one transaction.
  static const String transactionEditPattern = '/expenses/:transactionId/edit';

  /// Path pattern for the line items of one transaction.
  static const String transactionLinesPattern = '/expenses/:transactionId/lines';

  /// Path pattern for one item.
  static const String itemDetailPattern = '/inventory/:itemId';

  /// Path pattern for editing one item.
  static const String itemEditPattern = '/inventory/:itemId/edit';

  /// Path pattern for adding a batch to one item.
  static const String batchNewPattern = '/inventory/:itemId/batch/new';

  /// Path pattern for editing one batch.
  static const String batchEditPattern = '/inventory/:itemId/batch/:batchId';

  /// Path pattern for one batch's movement history.
  static const String batchHistoryPattern = '/inventory/:itemId/batch/:batchId/history';

  /// Path pattern for one shopping list.
  static const String shoppingListPattern = '/shopping/:listId';

  /// Path pattern for turning a shopping list's ticked entries into a purchase.
  static const String shoppingConvertPattern = '/shopping/:listId/convert';

  /// Path pattern for editing one recurring template.
  static const String recurringEditPattern = '/recurring/:templateId/edit';

  /// Path pattern for one template's occurrence history.
  static const String recurringHistoryPattern = '/recurring/:templateId/history';

  /// Path pattern for one recurring template.
  static const String recurringDetailPattern = '/recurring/:templateId';

  /// Path pattern for editing one asset.
  static const String assetEditPattern = '/services/:assetId/edit';

  /// Path pattern for a new service record against one asset.
  static const String serviceNewPattern = '/services/:assetId/service/new';

  /// Path pattern for editing one service record.
  static const String serviceEditPattern = '/services/:assetId/service/:recordId';

  /// Path pattern for one asset.
  static const String assetDetailPattern = '/services/:assetId';

  /// Path pattern for one calendar day.
  static const String calendarDayPattern = '/calendar/:dateKey';

  // ── param names, so a builder reading them cannot misspell one ──

  /// The transaction id parameter.
  static const String pTransactionId = 'transactionId';

  /// The item id parameter.
  static const String pItemId = 'itemId';

  /// The batch id parameter.
  static const String pBatchId = 'batchId';

  /// The shopping list id parameter.
  static const String pListId = 'listId';

  /// The recurring template id parameter.
  static const String pTemplateId = 'templateId';

  /// The asset id parameter.
  static const String pAssetId = 'assetId';

  /// The service record id parameter.
  static const String pRecordId = 'recordId';

  /// The calendar date parameter.
  static const String pDateKey = 'dateKey';

  // ── builders ──

  /// The location for transaction [id].
  static String transactionDetail(String id) => '$expenses/$id';

  /// The location for editing transaction [id].
  static String transactionEdit(String id) => '$expenses/$id/edit';

  /// The location for the line items of transaction [id], or of a new one when null.
  static String transactionLines(String? id) =>
      id == null ? transactionLinesNew : '$expenses/$id/lines';

  /// The location for item [id].
  static String itemDetail(String id) => '$inventory/$id';

  /// The location for editing item [id].
  static String itemEdit(String id) => '$inventory/$id/edit';

  /// The location for adding a batch to item [itemId].
  static String batchNew(String itemId) => '$inventory/$itemId/batch/new';

  /// The location for editing batch [batchId] of item [itemId].
  static String batchEdit(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId';

  /// The location for batch [batchId]'s movement history.
  static String batchHistory(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId/history';

  /// The location for shopping list [id].
  static String shoppingList(String id) => '$shopping/$id';

  /// The location for converting shopping list [id] into a purchase.
  static String shoppingConvert(String id) => '$shopping/$id/convert';

  /// The location for recurring template [id].
  static String recurringDetail(String id) => '$recurring/$id';

  /// The location for editing recurring template [id], or for a new one when null.
  static String recurringEdit(String? id) =>
      id == null ? recurringNew : '$recurring/$id/edit';

  /// The location for template [id]'s occurrence history.
  static String recurringHistory(String id) => '$recurring/$id/history';

  /// The location for asset [id].
  static String assetDetail(String id) => '$services/$id';

  /// The location for editing asset [id], or for a new one when null.
  static String assetEdit(String? id) => id == null ? assetNew : '$services/$id/edit';

  /// The location for a new service record against asset [assetId].
  static String serviceNew(String assetId) => '$services/$assetId/service/new';

  /// The location for editing service record [recordId] of asset [assetId].
  static String serviceEdit(String assetId, String recordId) =>
      '$services/$assetId/service/$recordId';

  /// The location for the calendar on [dateKey].
  static String calendarDay(int dateKey) => '$calendar/$dateKey';

  /// The nine drawer destinations, in drawer order.
  ///
  /// Named for the drawer rather than the shell because `AlayaDrawer` reads it by this name — a route
  /// cannot exist in the router and be missing from the drawer without this list disagreeing.
  static const List<String> drawerDestinations = [
    dashboard,
    expenses,
    inventory,
    shopping,
    recurring,
    services,
    calendar,
    insights,
    settings,
  ];
}
```

### `lib/app/router/app_router.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/placeholder_screen.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/theme_lab_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The nine drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
abstract final class AppRouter {
  /// Builds the router.
  static GoRouter build({
    LockGate? isLocked,
    String initialLocation = Routes.initial,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final locked = isLocked ?? () => false;
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: false,
      redirect: (context, state) {
        final atLock = state.matchedLocation == Routes.lock;
        if (locked() && !atLock) return Routes.lock;
        if (!locked() && atLock) return Routes.dashboard;
        return null;
      },
      routes: [
        GoRoute(
          path: Routes.lock,
          builder: (context, state) =>
              const PlaceholderScreen(owningPhase: 'Phase 8A'),
        ),
        ShellRoute(
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed to a
          // pathless `ShellRoute`'s builder reports `/` for every screen inside it.
          builder: (context, state, child) => _ShellScaffold(child: child),
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: Routes.expenses,
              builder: (context, state) => const TransactionListScreen(),
            ),
            GoRoute(
              path: Routes.inventory,
              builder: (context, state) => const InventoryListScreen(),
            ),
            GoRoute(
              path: Routes.shopping,
              builder: (context, state) => const ShoppingListScreen(),
            ),
            GoRoute(
              path: Routes.recurring,
              builder: (context, state) => const TemplateListScreen(),
            ),
            GoRoute(
              path: Routes.services,
              builder: (context, state) => const AssetListScreen(),
            ),
            GoRoute(
              path: Routes.calendar,
              builder: (context, state) => const CalendarScreen(),
              routes: [
                // A sub-route rather than a sibling detail route: a day is a view of the month, so it
                // keeps the drawer shell and the month stays behind it (Law U27).
                GoRoute(
                  path: ':${Routes.pDateKey}',
                  builder: (context, state) => CalendarScreen(
                    initialDay: _dateKeyParam(
                      state.pathParameters[Routes.pDateKey],
                    ),
                  ),
                ),
              ],
            ),
            _destination(Routes.insights, 'Phase 7B'),
            _destination(Routes.settings, 'Phase 8A'),
          ],
        ),
        GoRoute(
          path: Routes.transactionNew,
          builder: (context, state) => const TransactionEditorScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesNew,
          builder: (context, state) => const LineItemsScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesPattern,
          builder: (context, state) => LineItemsScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionEditPattern,
          builder: (context, state) => TransactionEditorScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionDetailPattern,
          builder: (context, state) => TransactionDetailScreen(
            transactionId: state.pathParameters[Routes.pTransactionId]!,
          ),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchHistoryPattern,
          builder: (context, state) => BatchHistoryScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchEditPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId],
          ),
        ),
        GoRoute(
          path: Routes.itemEditPattern,
          builder: (context, state) => ItemEditorScreen(
            itemId: state.pathParameters[Routes.pItemId],
          ),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) => ItemDetailScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) => ShoppingListScreen(
            listId: state.pathParameters[Routes.pListId],
          ),
        ),
        GoRoute(
          path: Routes.recurringNew,
          builder: (context, state) => const TemplateBuilderScreen(),
        ),
        GoRoute(
          path: Routes.recurringHistoryPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.recurringEditPattern,
          builder: (context, state) => TemplateBuilderScreen(
            templateId: state.pathParameters[Routes.pTemplateId],
          ),
        ),
        GoRoute(
          path: Routes.recurringDetailPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.assetNew,
          builder: (context, state) => const AssetEditorScreen(),
        ),
        GoRoute(
          path: Routes.serviceNewPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.serviceEditPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
            recordId: state.pathParameters[Routes.pRecordId],
          ),
        ),
        GoRoute(
          path: Routes.assetEditPattern,
          builder: (context, state) => AssetEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId],
          ),
        ),
        GoRoute(
          path: Routes.assetDetailPattern,
          builder: (context, state) => AssetDetailScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.themeLab,
          builder: (context, state) => _DetailScaffold(
            title: AlayaStrings.of(context).navThemeLab,
            child: const ThemeLabScreen(),
          ),
        ),
      ],
    );
  }

  /// A top-level drawer destination, rendered inside the shell.
  static GoRoute _destination(String path, String owningPhase) => GoRoute(
    path: path,
    builder: (context, state) => PlaceholderScreen(owningPhase: owningPhase),
  );

  /// A detail route, rendered outside the shell so it gets a back arrow rather than a hamburger.
  static GoRoute _detail(String pattern, String owningPhase) => GoRoute(
    path: pattern,
    builder: (context, state) => _DetailScaffold(
      title: AlayaDrawer.titleFor(context, state.uri.path),
      child: PlaceholderScreen(owningPhase: owningPhase),
    ),
  );
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell that
    // owns a drawer can never show a back arrow no matter how it was reached. That is fine for a drawer
    // destination switched into as a peer, and wrong for one pushed as a drill-down — and both happen
    // here: the drawer `go`es, the dashboard's module grid `push`es.
    //
    // So the slot is stated rather than implied. Pushed: a back arrow that pops the shell's own navigator
    // (`context.pop`, not `Navigator.maybePop`, which from above the shell navigator would target the root
    // one and do nothing). Switched into: null, which lets the hamburger be implied as before.
    //
    // The drawer stays attached either way, so the edge swipe still opens it on a pushed screen.
    final strings = AlayaStrings.of(context);

    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so the
    // `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's — and a
    // pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside the shell
    // therefore looked like the dashboard: `atDashboard` was permanently true so the home action never
    // rendered, `AlayaDrawer` highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location no
    // matter which builder asks.
    final here = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;

    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear. The drawer's hamburger was the only leading widget users ever saw, and from a module
    // the sole way home was the system back gesture.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see: every
    // shell screen except the dashboard carries a home action. It pops when there is something to pop and
    // navigates otherwise, so arriving by the module grid's `push` and by the drawer's `go` both end up
    // in the same place — and the hamburger keeps its slot, because the drawer is still how you move
    // between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        title: Text(AlayaDrawer.titleFor(context, here)),
        // **Unconditional, deliberately.** This was `if (!atDashboard)` and never appeared, and rather
        // than reason about why a condition is false I would rather the button exist and be seen. It
        // shows on the dashboard too, where it is merely redundant — a redundant button is a far smaller
        // fault than a missing one, and its presence there is also the proof that this file is live.
        //
        // Once it is confirmed visible, `if (!atDashboard)` can come back.
        actions: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            tooltip: strings.navBackToDashboard,
            icon: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
          ),
        ],
      ),
      body: child,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

/// Parses a `:dateKey` path parameter, or null when it is absent or not a date key.
///
/// A malformed deep link opens the calendar on today rather than throwing — the route is reachable
/// from outside the app.
DateKey? _dateKeyParam(String? raw) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return null;

  final year = value ~/ 10000;
  final month = (value ~/ 100) % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Round-trip through `fromYmd`, which normalises overflow through `DateTime.utc`: 20260230 comes
  // back as 20260302 and fails this check, where a digit-range test alone would accept it.
  final probe = DateKey.fromYmd(year, month, day);
  return probe.value == value ? probe : null;
}
```

### `lib/shared/widgets/frequency_preview.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/shared/widgets/date_text.dart';

/// One date a schedule will land on, and whether the anchor had to shorten to reach it.
class PreviewedDate {
  /// Creates a previewed date.
  const PreviewedDate({required this.dateKey, this.clamped = false});

  /// When it lands.
  final DateKey dateKey;

  /// Whether the anchor day exceeded this month and was pulled back to its last day.
  final bool clamped;
}

/// Shows where a schedule actually lands (ARCH_5 §8 — the one shared addition Phase 6D makes).
///
/// **This is the only way a user can tell a clamp is doing what they meant.** A bill anchored on the
/// 31st shows Jan 31, Feb 28, Mar 31 — and the February row says it was shortened. Without that, a
/// user who typed 31 and saw 28 would reasonably conclude the app lost their input, and the
/// alternative designs are worse: refusing days above 28 makes the 31st unexpressible, and silently
/// storing 28 walks the anchor backwards forever (anomaly A13).
///
/// The dates are computed by the caller from `RecurringEngine.nextDue`, not here. This widget renders;
/// duplicating the arithmetic would give the preview and the materialiser two answers.
class FrequencyPreview extends StatelessWidget {
  /// Creates the preview.
  const FrequencyPreview({required this.dates, super.key});

  /// The next few dates, soonest first. Empty renders a prompt rather than nothing.
  final List<PreviewedDate> dates;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Container(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      decoration: BoxDecoration(
        color: semantic.surfaceSunken,
        borderRadius: AlayaRadii.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat, size: AlayaIconSize.sm, color: semantic.muted),
              const SizedBox(width: AlayaSpacing.xxs),
              Expanded(
                child: Text(
                  strings.previewTitle,
                  style: AlayaTypography.label.copyWith(color: semantic.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.xs),
          if (dates.isEmpty)
            Text(
              strings.previewEmpty,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            )
          else
            for (final date in dates)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
                // A `Wrap`: the date and the clamp note both grow with text scale, and a `Row` would
                // starve one of them at 320dp (Law U21).
                child: Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DateText(date.dateKey, style: DateTextStyle.full),
                    if (date.clamped)
                      Text(
                        strings.previewClamped,
                        style: AlayaTypography.caption.copyWith(color: semantic.warning),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
```
### `lib/features/recurring/state/template_builder_state.dart`

```dart
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// Why a template save was refused, when it was refused for a reason worth naming.
enum TemplateSaveIssue {
  /// The name was blank.
  nameMissing,

  /// The default amount was missing or not positive.
  amountMissing,

  /// A monthly or yearly template with no day to anchor to.
  anchorMissing,

  /// The write failed for a reason the repository named.
  rejected,
}

/// Everything the template builder is holding (ARCH_5 §3 archetype B).
class TemplateBuilderState {
  /// Creates the builder's state.
  const TemplateBuilderState({
    required this.currencyCode,
    required this.startDateKey,
    this.id,
    this.name = '',
    this.kind = RecurringKind.bill,
    this.direction = RecurringDirection.outflow,
    this.amount,
    this.intervalUnit = RecurringIntervalUnit.month,
    this.intervalCount = 1,
    this.anchorDayOfMonth,
    this.endDateKey,
    this.payeeId,
    this.accountId,
    this.tagId,
    this.remindDaysBefore = 3,
    this.autoRemind = true,
    this.isPaused = false,
    this.note,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The template being edited, or null for a new one.
  final String? id;

  /// What to call it.
  final String name;

  /// Bill, subscription, rent or salary.
  final RecurringKind kind;

  /// Whether money leaves or arrives.
  ///
  /// Drives the whole module's wording: an inflow salary is income, never a negative bill.
  final RecurringDirection direction;

  /// The currency amounts are entered in.
  final String currencyCode;

  /// What it usually costs. A default the pay sheet pre-fills, never a fixed figure.
  final Money? amount;

  /// Days, weeks, months or years.
  final RecurringIntervalUnit intervalUnit;

  /// How many of them.
  final int intervalCount;

  /// The day of the month it anchors to.
  ///
  /// Stored once and clamped at every render, never advanced (anomaly A13). Required for a monthly or
  /// yearly template, which is what stops a February settlement dragging every later occurrence back
  /// to the 28th permanently.
  final int? anchorDayOfMonth;

  /// When it starts.
  final DateKey startDateKey;

  /// When it stops, if it does.
  final DateKey? endDateKey;

  /// Who it is paid to, or received from.
  final String? payeeId;

  /// Which account the pay sheet should default to.
  final String? accountId;

  /// The tag every generated transaction carries.
  final String? tagId;

  /// How many days of warning Phase 8B should give.
  final int remindDaysBefore;

  /// Whether to remind at all.
  final bool autoRemind;

  /// Whether it is currently paused.
  final bool isPaused;

  /// Free note.
  final String? note;

  /// Whether a save is in flight.
  final bool submitting;

  /// Why the last save was refused, or null if it was not.
  final TemplateSaveIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Whether this is editing an existing template.
  bool get isEditing => id != null;

  /// Whether the interval is anchored to a day of the month.
  bool get needsDayAnchor =>
      intervalUnit == RecurringIntervalUnit.month ||
      intervalUnit == RecurringIntervalUnit.year;

  /// Whether the state is complete enough to preview and to save.
  bool get isComplete =>
      name.trim().isNotEmpty &&
      (amount?.isPositive ?? false) &&
      intervalCount >= 1 &&
      (!needsDayAnchor || anchorDayOfMonth != null);

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ///
  /// `issue` and `rejection` are preserved unless [clearIssue] is passed, because a bare assignment
  /// lets any later `copyWith` erase the reason before the screen reads it (ARCH_4 R31).
  TemplateBuilderState copyWith({
    String? id,
    String? name,
    RecurringKind? kind,
    RecurringDirection? direction,
    Money? amount,
    RecurringIntervalUnit? intervalUnit,
    int? intervalCount,
    int? anchorDayOfMonth,
    bool clearAnchor = false,
    DateKey? startDateKey,
    DateKey? endDateKey,
    bool clearEndDate = false,
    String? payeeId,
    String? accountId,
    String? tagId,
    int? remindDaysBefore,
    bool? autoRemind,
    bool? isPaused,
    String? note,
    bool? submitting,
    TemplateSaveIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
  }) =>
      TemplateBuilderState(
        id: id ?? this.id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        direction: direction ?? this.direction,
        currencyCode: currencyCode,
        amount: amount ?? this.amount,
        intervalUnit: intervalUnit ?? this.intervalUnit,
        intervalCount: intervalCount ?? this.intervalCount,
        anchorDayOfMonth: clearAnchor ? null : (anchorDayOfMonth ?? this.anchorDayOfMonth),
        startDateKey: startDateKey ?? this.startDateKey,
        endDateKey: clearEndDate ? null : (endDateKey ?? this.endDateKey),
        payeeId: payeeId ?? this.payeeId,
        accountId: accountId ?? this.accountId,
        tagId: tagId ?? this.tagId,
        remindDaysBefore: remindDaysBefore ?? this.remindDaysBefore,
        autoRemind: autoRemind ?? this.autoRemind,
        isPaused: isPaused ?? this.isPaused,
        note: note ?? this.note,
        submitting: submitting ?? this.submitting,
        issue: clearIssue ? null : (issue ?? this.issue),
        rejection: clearIssue ? null : (rejection ?? this.rejection),
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? true,
      );

  /// Builds the entity this state describes.
  ///
  /// `nextDueDateKey` starts at `startDateKey` for a new template: materialisation walks forward from
  /// there, so the first occurrence is the start date itself rather than one interval after it.
  RecurringTemplate toTemplate({
    required String newId,
    required String normalizedName,
    required DateKey nextDue,
  }) =>
      RecurringTemplate(
        id: id ?? newId,
        name: name.trim(),
        normalizedName: normalizedName,
        kind: kind,
        direction: direction,
        defaultAmount: amount ?? Money.zero(currencyCode),
        intervalUnit: intervalUnit,
        intervalCount: intervalCount,
        startDateKey: startDateKey,
        nextDueDateKey: nextDue,
        isPaused: isPaused,
        autoRemind: autoRemind,
        remindDaysBefore: remindDaysBefore,
        payeeId: payeeId,
        defaultAccountId: accountId,
        tagId: tagId,
        anchorDayOfMonth: anchorDayOfMonth,
        endDateKey: endDateKey,
        note: note,
      );

  /// Loads an existing template into a builder state.
  static TemplateBuilderState fromTemplate(RecurringTemplate template) => TemplateBuilderState(
        id: template.id,
        name: template.name,
        kind: template.kind,
        direction: template.direction,
        currencyCode: template.defaultAmount.currencyCode,
        amount: template.defaultAmount,
        intervalUnit: template.intervalUnit,
        intervalCount: template.intervalCount,
        anchorDayOfMonth: template.anchorDayOfMonth,
        startDateKey: template.startDateKey,
        endDateKey: template.endDateKey,
        payeeId: template.payeeId,
        accountId: template.defaultAccountId,
        tagId: template.tagId,
        remindDaysBefore: template.remindDaysBefore,
        autoRemind: template.autoRemind,
        isPaused: template.isPaused,
        note: template.note,
      );
}
```
### `lib/features/recurring/state/pay_state.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// Why a payment was refused, when it was refused for a reason worth naming.
enum PayIssue {
  /// No amount, or a non-positive one.
  amountMissing,

  /// No account chosen, and the template had no default.
  accountMissing,

  /// The write failed for a reason the repository named.
  rejected,
}

/// What the pay sheet is holding (ARCH_5 §3 archetype A).
///
/// **The default and the actual are two different figures and both are kept.** A bill quoted at
/// ₹1,200 that arrives at ₹1,247 is the normal case, not an error — the sheet pre-fills the default so
/// the common path is one tap, and stores what was actually paid so the history can show the gap.
class PayState {
  /// Creates the sheet's state.
  const PayState({
    required this.occurrenceId,
    required this.defaultAmount,
    required this.paidOn,
    this.amount,
    this.accountId,
    this.paymentMethodId,
    this.note,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// Which occurrence is being settled.
  final String occurrenceId;

  /// What the template says it usually is.
  final Money defaultAmount;

  /// What is actually being paid, pre-filled from [defaultAmount].
  final Money? amount;

  /// When.
  final DateKey paidOn;

  /// Which account it came from, or goes into.
  final String? accountId;

  /// How it was paid.
  final String? paymentMethodId;

  /// Free note.
  final String? note;

  /// Whether a commit is in flight.
  final bool submitting;

  /// Why the last commit was refused, or null if it was not.
  final PayIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything was touched, for the dismiss guard (Law U10).
  final bool dirty;

  /// Whether the actual figure differs from the usual one, which is what the history highlights.
  bool get differsFromDefault {
    final actual = amount;
    return actual != null && actual != defaultAmount;
  }

  /// Returns a copy with the supplied changes.
  ///
  /// `issue` and `rejection` survive an unrelated `copyWith` — a bare assignment lets the
  /// `submitting: false` in a `finally` erase the reason before the sheet reads it (ARCH_4 R31).
  PayState copyWith({
    Money? amount,
    DateKey? paidOn,
    String? accountId,
    String? paymentMethodId,
    String? note,
    bool? submitting,
    PayIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
  }) =>
      PayState(
        occurrenceId: occurrenceId,
        defaultAmount: defaultAmount,
        amount: amount ?? this.amount,
        paidOn: paidOn ?? this.paidOn,
        accountId: accountId ?? this.accountId,
        paymentMethodId: paymentMethodId ?? this.paymentMethodId,
        note: note ?? this.note,
        submitting: submitting ?? this.submitting,
        issue: clearIssue ? null : (issue ?? this.issue),
        rejection: clearIssue ? null : (rejection ?? this.rejection),
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? this.dirty,
      );
}
```

### `lib/features/recurring/providers/template_list_providers.dart`

```dart
/// View-model state for the recurring template list (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// A template with the soonest outstanding occurrence against it, if any.
class TemplateRow {
  /// Creates a row.
  const TemplateRow({required this.template, this.next});

  /// The template.
  final RecurringTemplate template;

  /// Its soonest outstanding occurrence, or null when nothing is materialised yet.
  final RecurringOccurrence? next;
}

/// One direction's worth of templates.
class TemplateGroup {
  /// Creates a group.
  const TemplateGroup({required this.direction, required this.rows});

  /// Whether these are outflows or inflows.
  final RecurringDirection direction;

  /// The rows under it.
  final List<TemplateRow> rows;
}

/// Materialises occurrences up to today, once per list mount.
///
/// **Lazy, and never automatic beyond this.** Occurrences are created up to today so the list can show
/// what is due; not one of them is paid, and no transaction exists until a user taps (anomaly A14). An
/// app unopened for three months produces three due rows and zero transactions.
final materialiseProvider = FutureProvider<int>((ref) async {
  final result = await ref
      .watch(recurringRepositoryProvider)
      .materialiseUpTo(ref.watch(clockProvider).today());
  return result.valueOrNull ?? 0;
});

/// Every template.
final templatesProvider = StreamProvider<List<RecurringTemplate>>(
  (ref) => ref.watch(recurringRepositoryProvider).watchAllTemplates(),
);

/// Outstanding occurrences for one template, soonest first.
final occurrencesProvider =
    StreamProvider.autoDispose.family<List<RecurringOccurrence>, String>(
  (ref, templateId) => ref.watch(recurringRepositoryProvider).watchOccurrences(templateId),
);

/// Templates grouped by direction, each with its soonest outstanding occurrence.
///
/// Grouped by direction rather than sorted by date because a salary and a rent bill are not two
/// entries on one list — the §7.2 row this closes is precisely that an inflow must read as income
/// rather than as a negative bill.
final templateGroupsProvider = Provider<AsyncValue<List<TemplateGroup>>>((ref) {
  // Depended on so the list cannot render before today's rows exist; its own value is not needed.
  ref.watch(materialiseProvider);
  final templates = ref.watch(templatesProvider);
  if (templates.hasError) {
    return AsyncValue.error(templates.error!, templates.stackTrace!);
  }
  final all = templates.valueOrNull;
  if (all == null) return const AsyncValue.loading();

  List<TemplateRow> rowsFor(RecurringDirection direction) => [
        for (final template in all)
          if (template.direction == direction)
            TemplateRow(
              template: template,
              next: _soonestOutstanding(
                ref.watch(occurrencesProvider(template.id)).valueOrNull,
              ),
            ),
      ]..sort(
          (a, b) => a.template.nextDueDateKey.compareTo(b.template.nextDueDateKey),
        );

  final outflow = rowsFor(RecurringDirection.outflow);
  final inflow = rowsFor(RecurringDirection.inflow);
  return AsyncValue.data([
    if (outflow.isNotEmpty)
      TemplateGroup(direction: RecurringDirection.outflow, rows: outflow),
    if (inflow.isNotEmpty)
      TemplateGroup(direction: RecurringDirection.inflow, rows: inflow),
  ]);
});

RecurringOccurrence? _soonestOutstanding(List<RecurringOccurrence>? occurrences) {
  if (occurrences == null) return null;
  RecurringOccurrence? soonest;
  for (final occurrence in occurrences) {
    if (!occurrence.isOutstanding) continue;
    if (soonest == null || occurrence.dueDateKey.isBefore(soonest.dueDateKey)) {
      soonest = occurrence;
    }
  }
  return soonest;
}

/// How many templates have an occurrence past its due date, for the header count.
///
/// Derived from the clock through `RecurringEngine.isOverdue`, never a stored flag (ARCH_2 §12.2): a
/// flag would be wrong the moment midnight passed with the app closed.
final overdueCountProvider = Provider<int>((ref) {
  final groups = ref.watch(templateGroupsProvider).valueOrNull ?? const [];
  final engine = ref.watch(recurringEngineProvider);
  final today = ref.watch(clockProvider).today();
  var count = 0;
  for (final group in groups) {
    for (final row in group.rows) {
      final next = row.next;
      if (next == null) continue;
      if (engine.isOverdue(occurrence: next, today: today)) count++;
    }
  }
  return count;
});

/// Writes the template list performs.
final templateActionsProvider = Provider<TemplateActions>(TemplateActions.new);

/// Pauses, resumes and deletes templates.
class TemplateActions {
  /// Creates the actions.
  TemplateActions(this._ref);

  final Ref _ref;

  /// Pauses or resumes a template, returning the failure's own message or null on success.
  Future<String?> setPaused({required String id, required bool isPaused}) async {
    final result = await _ref
        .read(recurringRepositoryProvider)
        .setTemplatePaused(id: id, isPaused: isPaused);
    return result.failureOrNull?.message;
  }

  /// Deletes a template.
  ///
  /// Its occurrences go with it; the transactions any of them created stay, because a payment that
  /// happened happened (Law L6).
  Future<String?> delete(String id) async {
    final result = await _ref.read(recurringRepositoryProvider).deleteTemplate(id);
    return result.failureOrNull?.message;
  }
}
```
### `lib/features/recurring/providers/template_builder_providers.dart`

```dart
/// View-model state for the recurring template builder (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/providers/template_draft_provider.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';

/// Accounts the pay sheet may default to.
final builderAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The home currency, so an amount is never denominated in a guess.
final builderCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR',
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final builderDecimalDigitsProvider = FutureProvider.autoDispose<int>((ref) async {
  final code = await ref.watch(builderCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The builder for one template, or for a new one when the argument is null.
final templateBuilderProvider = NotifierProvider.autoDispose
    .family<TemplateBuilderNotifier, AsyncValue<TemplateBuilderState>, String?>(
  TemplateBuilderNotifier.new,
);

/// The next three dates the current frequency would land on.
///
/// **Walked through `RecurringEngine.nextDue`, the same method materialisation uses.** A second copy
/// of the clamp here would let the preview and the written occurrences disagree, which is the one
/// thing this preview exists to prevent (anomaly A13).
final previewProvider =
    Provider.autoDispose.family<List<PreviewedDate>, String?>((ref, editorId) {
  final state = ref.watch(templateBuilderProvider(editorId)).valueOrNull;
  if (state == null || !state.isComplete) return const [];
  final engine = ref.watch(recurringEngineProvider);
  final template = state.toTemplate(
    newId: 'preview',
    normalizedName: 'preview',
    nextDue: state.startDateKey,
  );

  final dates = <PreviewedDate>[];
  var cursor = state.startDateKey;
  final end = state.endDateKey;
  final anchor = state.anchorDayOfMonth;
  while (dates.length < 3) {
    if (end != null && cursor.isAfter(end)) break;
    dates.add(
      PreviewedDate(
        dateKey: cursor,
        // A clamp is visible exactly when the anchor could not be reached this month. Only a monthly
        // or yearly interval anchors to a day, so a weekly template never reports one.
        clamped: anchor != null && state.needsDayAnchor && cursor.day != anchor,
      ),
    );
    cursor = engine.nextDue(from: cursor, template: template);
  }
  return dates;
});

/// Loads, edits and saves one recurring template.
class TemplateBuilderNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<TemplateBuilderState>, String?> {
  @override
  AsyncValue<TemplateBuilderState> build(String? arg) {
    // A new template needs nothing fetched beyond the currency, so it does not flash a skeleton for a
    // form it could have shown. Assigning state from a synchronous path inside `build` is what
    // Riverpod refuses, so the load is always awaited.
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String? id) async {
    try {
      final code =
          await ref.read(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR';
      if (id == null) {
        final today = ref.read(clockProvider).today();
        // A draft another module prepared, if one is waiting. `take()` clears it, so it is applied
        // exactly once and a stale one cannot ambush the next blank builder.
        final draft = ref.read(templateDraftProvider.notifier).take();
        state = AsyncValue.data(
          TemplateBuilderState(
            currencyCode: code,
            startDateKey: today,
            anchorDayOfMonth: today.day,
            name: draft?.name ?? '',
            amount: draft?.amount,
          ),
        );
        return;
      }
      final template = await ref.read(recurringRepositoryProvider).templateById(id);
      if (template == null) {
        state = AsyncValue.error(
          StateError('Recurring template $id not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(TemplateBuilderState.fromTemplate(template));
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(TemplateBuilderState Function(TemplateBuilderState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets the name.
  void setName(String name) => _edit((s) => s.copyWith(name: name, clearIssue: true));

  /// Sets bill, subscription, rent or salary.
  ///
  /// Salary implies an inflow, and setting it also flips the direction — a salary rendered as a
  /// negative bill is the §7.2 row this module exists to close, and making the user set both is how
  /// that mistake gets made.
  void setKind(RecurringKind kind) => _edit(
        (s) => s.copyWith(
          kind: kind,
          direction: kind == RecurringKind.salary
              ? RecurringDirection.inflow
              : s.direction,
        ),
      );

  /// Sets whether money leaves or arrives.
  void setDirection(RecurringDirection direction) =>
      _edit((s) => s.copyWith(direction: direction));

  /// Sets the usual amount.
  void setAmount(Money? amount) =>
      _edit((s) => s.copyWith(amount: amount, clearIssue: true));

  /// Sets the interval unit, and drops an anchor the new unit cannot use.
  void setIntervalUnit(RecurringIntervalUnit unit) => _edit((s) {
        final anchored = unit == RecurringIntervalUnit.month ||
            unit == RecurringIntervalUnit.year;
        return s.copyWith(
          intervalUnit: unit,
          anchorDayOfMonth: anchored ? (s.anchorDayOfMonth ?? s.startDateKey.day) : null,
          clearAnchor: !anchored,
          clearIssue: true,
        );
      });

  /// Sets how many units make up one interval.
  void setIntervalCount(int count) =>
      _edit((s) => s.copyWith(intervalCount: count < 1 ? 1 : count));

  /// Sets the day of the month the schedule anchors to.
  void setAnchorDay(int? day) => _edit(
        (s) => day == null
            ? s.copyWith(clearAnchor: true)
            : s.copyWith(anchorDayOfMonth: day, clearIssue: true),
      );

  /// Sets when it starts, carrying the day anchor with it unless the user has chosen one.
  ///
  /// **The anchor followed nothing before, and that was a due-date bug.** The builder seeds the anchor
  /// from today; moving the start date to the 15th left it on today's day, so the first occurrence
  /// landed on the 15th and every one after it on some unrelated day. The anchor only stops following
  /// once `setAnchorDay` is called, which is the user saying they meant a different day.
  void setStartDate(DateKey date) => _edit((s) {
        final follows = s.anchorDayOfMonth == null ||
            s.anchorDayOfMonth == s.startDateKey.day;
        return s.copyWith(
          startDateKey: date,
          anchorDayOfMonth: follows && s.needsDayAnchor ? date.day : s.anchorDayOfMonth,
        );
      });

  /// Sets when it stops, or clears the end date.
  void setEndDate(DateKey? date) => _edit(
        (s) => date == null ? s.copyWith(clearEndDate: true) : s.copyWith(endDateKey: date),
      );

  /// Sets which account the pay sheet defaults to.
  void setAccount(String? accountId) => _edit((s) => s.copyWith(accountId: accountId));

  /// Sets how many days of warning to give.
  void setRemindDaysBefore(int days) =>
      _edit((s) => s.copyWith(remindDaysBefore: days < 0 ? 0 : days));

  /// Turns reminders on or off.
  void toggleRemind() => _edit((s) => s.copyWith(autoRemind: !s.autoRemind));

  /// Sets the free note.
  void setNote(String note) => _edit((s) => s.copyWith(note: note));

  /// Saves the template, returning its id on success and null on rejection or failure.
  ///
  /// Every refusal is named before the repository sees it, and a rejection carries the repository's own
  /// message — the builder has three ways to be incomplete and "something went wrong" distinguishes
  /// none of them (Law U9).
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.name.trim().isEmpty) {
      _edit(
        (s) => s.copyWith(
          issue: TemplateSaveIssue.nameMissing,
          shakeTrigger: s.shakeTrigger + 1,
        ),
      );
      return null;
    }
    if (!(current.amount?.isPositive ?? false)) {
      _edit(
        (s) => s.copyWith(
          issue: TemplateSaveIssue.amountMissing,
          shakeTrigger: s.shakeTrigger + 1,
        ),
      );
      return null;
    }
    if (current.needsDayAnchor && current.anchorDayOfMonth == null) {
      _edit((s) => s.copyWith(issue: TemplateSaveIssue.anchorMissing));
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearIssue: true));
    try {
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final saved = await ref.read(recurringRepositoryProvider).saveTemplate(
            current.toTemplate(
              newId: id,
              normalizedName:
                  ref.read(normalizerProvider).normalize(current.name.trim()),
              // A new template's first occurrence is its start date, not one interval after it.
              // Editing leaves the cursor alone: materialisation owns it, and resetting it would
              // resurrect occurrences already paid.
              nextDue: current.isEditing
                  ? (await ref
                          .read(recurringRepositoryProvider)
                          .templateById(id))
                      ?.nextDueDateKey ??
                      current.startDateKey
                  : current.startDateKey,
            ),
          );
      final failure = saved.failureOrNull;
      if (failure != null) {
        _edit(
          (s) => s.copyWith(
            issue: TemplateSaveIssue.rejected,
            rejection: failure.message,
          ),
        );
        return null;
      }
      // Materialisation runs once per list mount, so a template created afterwards would show no
      // occurrence until the next launch. Invalidating it here is what makes the first due row appear
      // immediately rather than looking like nothing happened.
      ref.invalidate(materialiseProvider);
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref.read(loggerProvider).log(
        'Recurring template save failed',
        level: LogLevel.error,
        tag: 'recurring.builder',
        error: error,
        stackTrace: stack,
      );
      _edit(
        (s) => s.copyWith(
          issue: TemplateSaveIssue.rejected,
          rejection: error.toString(),
        ),
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }
}
```
### `lib/features/recurring/providers/pay_providers.dart`

```dart
/// View-model state for the pay sheet and occurrence history (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/state/pay_state.dart';

/// Which occurrence a pay sheet is settling, and what the template says it usually costs.
typedef PayArgs = ({String occurrenceId, int defaultMinor, String currencyCode, String? accountId});

/// Accounts the payment may come from.
final payAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  // `watchSelectable`, not a list of everything: an archived account is not somewhere a payment can
  // come from, and offering it is how a closed account acquires new transactions.
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final payDecimalDigitsProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, code) async =>
      (await ref.watch(currencyRepositoryProvider).byCode(code))?.decimalDigits ?? 2,
);

/// The pay sheet for one occurrence.
final payProvider =
    NotifierProvider.autoDispose.family<PayNotifier, PayState, PayArgs>(PayNotifier.new);

/// Holds the pending payment and commits it.
///
/// **State is synchronous.** Everything the sheet needs — the occurrence, the default, the template's
/// account — arrives in the family argument from the row that opened it, so the amount field accepts a
/// keystroke on the first frame rather than after a spinner (ARCH_5 §5.2).
class PayNotifier extends AutoDisposeFamilyNotifier<PayState, PayArgs> {
  @override
  PayState build(PayArgs arg) {
    final defaultAmount = Money(arg.defaultMinor, arg.currencyCode);
    return PayState(
      occurrenceId: arg.occurrenceId,
      defaultAmount: defaultAmount,
      // Pre-filled, so the common case — it cost what it usually costs — is one tap.
      amount: defaultAmount,
      paidOn: ref.read(clockProvider).today(),
      accountId: arg.accountId,
    );
  }

  /// Sets what is actually being paid.
  void setAmount(Money? amount) =>
      state = state.copyWith(amount: amount, clearIssue: true, dirty: true);

  /// Sets which account it came from.
  void setAccount(String? accountId) =>
      state = state.copyWith(accountId: accountId, clearIssue: true, dirty: true);

  /// Sets when it was paid.
  void setPaidOn(DateKey date) => state = state.copyWith(paidOn: date, dirty: true);

  /// Sets the free note.
  void setNote(String note) => state = state.copyWith(note: note, dirty: true);

  /// Commits the payment, returning the id of the transaction it created.
  ///
  /// `payOccurrence` writes the transaction and settles the occurrence together; nothing here does it
  /// by hand. Returns null on rejection, with the reason on the state.
  Future<String?> commit() async {
    final amount = state.amount;
    if (amount == null || !amount.isPositive) {
      state = state.copyWith(
        issue: PayIssue.amountMissing,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return null;
    }
    final accountId = state.accountId;
    if (accountId == null) {
      state = state.copyWith(issue: PayIssue.accountMissing);
      return null;
    }

    state = state.copyWith(submitting: true, clearIssue: true);
    try {
      final result = await ref.read(recurringRepositoryProvider).payOccurrence(
            occurrenceId: state.occurrenceId,
            amount: amount,
            paidOn: state.paidOn,
            accountId: accountId,
            paymentMethodId: state.paymentMethodId,
          );
      final failure = result.failureOrNull;
      if (failure != null) {
        state = state.copyWith(issue: PayIssue.rejected, rejection: failure.message);
        return null;
      }
      return result.valueOrNull?.id;
    } on Object catch (error, stack) {
      ref.read(loggerProvider).log(
        'Recurring payment failed',
        level: LogLevel.error,
        tag: 'recurring.pay',
        error: error,
        stackTrace: stack,
      );
      state = state.copyWith(issue: PayIssue.rejected, rejection: error.toString());
      return null;
    } finally {
      state = state.copyWith(submitting: false);
    }
  }
}

/// Writes an occurrence row performs.
final occurrenceActionsProvider = Provider<OccurrenceActions>(OccurrenceActions.new);

/// Skips and un-pays occurrences.
class OccurrenceActions {
  /// Creates the actions.
  OccurrenceActions(this._ref);

  final Ref _ref;

  /// Marks an occurrence deliberately skipped, so it stops being outstanding without inventing money.
  Future<String?> skip({required String occurrenceId, String? note}) async {
    final result = await _ref
        .read(recurringRepositoryProvider)
        .skipOccurrence(occurrenceId: occurrenceId, note: note);
    return result.failureOrNull?.message;
  }

  /// Undoes a payment: the occurrence returns to due, then the transaction it created is deleted.
  ///
  /// **That order is deliberate.** Neither half can be inside the other's transaction, so one of two
  /// partial states survives a failure between them: an occurrence due while its transaction still
  /// exists shows a visible duplicate the user can fix, whereas a transaction deleted while the
  /// occurrence still reads paid hides an obligation with nothing on screen to reveal it. Order for the
  /// visible failure (ARCH_4 R21).
  Future<String?> undoPayment({
    required String occurrenceId,
    required String transactionId,
  }) async {
    final unsettled =
        await _ref.read(recurringRepositoryProvider).unsettleOccurrence(occurrenceId);
    final unsettleFailure = unsettled.failureOrNull;
    if (unsettleFailure != null) return unsettleFailure.message;

    final deleted =
        await _ref.read(transactionRepositoryProvider).delete(id: transactionId);
    return deleted.failureOrNull?.message;
  }
}
```
### `lib/features/recurring/providers/occurrence_history_providers.dart`

```dart
/// View-model state for one template's occurrence history (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// The template the history belongs to.
final historyTemplateProvider =
    FutureProvider.autoDispose.family<RecurringTemplate?, String>(
  (ref, templateId) => ref.watch(recurringRepositoryProvider).templateById(templateId),
);
```

### `lib/features/recurring/presentation/widgets/template_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One recurring template: what it is, what it costs, and when it next lands.
///
/// **Overdue is derived, never stored.** `RecurringOccurrence.isOverdue(today)` is asked on every
/// build, because a stored flag is wrong the moment midnight passes with the app closed
/// (ARCH_2 §12.2).
///
/// **An inflow is not a negative outflow.** The amount is rendered unsigned with the direction carried
/// by wording and colour, so a salary reads as income rather than as a bill for minus twelve thousand
/// — the §7.2 row this row exists to close.
class TemplateRowTile extends StatelessWidget {
  /// Creates the row.
  const TemplateRowTile({
    required this.template,
    required this.next,
    required this.today,
    required this.decimalDigits,
    required this.onTap,
    this.onPay,
    this.onTogglePause,
    super.key,
  });

  /// The template.
  final RecurringTemplate template;

  /// Its soonest outstanding occurrence, or null when nothing is materialised.
  final RecurringOccurrence? next;

  /// Today, for the overdue derivation.
  final DateKey today;

  /// The currency's precision.
  final int decimalDigits;

  /// Opens the occurrence history.
  final VoidCallback onTap;

  /// Opens the pay sheet for [next].
  final VoidCallback? onPay;

  /// Pauses or resumes the template.
  final VoidCallback? onTogglePause;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final occurrence = next;
    final overdue = occurrence != null && occurrence.isOverdue(today);
    final dueToday = occurrence != null && occurrence.dueDateKey == today;

    // Collected before the tree so the tier can be omitted entirely when there is nothing unusual to
    // say, rather than rendering an empty row of padding.
    final chips = <Widget>[
      if (overdue)
        StatusChip(label: strings.recurringOverdue, tone: StatusTone.danger)
      else if (dueToday)
        StatusChip(label: strings.recurringDueToday, tone: StatusTone.warning),
      if (occurrence == null && !template.isPaused)
        StatusChip(label: strings.recurringNotYetDue),
      if (template.isPaused) StatusChip(label: strings.recurringPaused),
    ];

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    template.direction == RecurringDirection.inflow
                        ? Icons.south_west
                        : Icons.north_east,
                    size: AlayaIconSize.lg,
                    color: template.isPaused
                        ? semantic.muted
                        : template.direction == RecurringDirection.inflow
                            ? semantic.success
                            : semantic.muted,
                  ),
                  const SizedBox(width: AlayaSpacing.sm),
                  Expanded(
                    child: Text(
                      template.name,
                      style: AlayaTypography.body.copyWith(
                        color: template.isPaused
                            ? semantic.muted
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AlayaSpacing.xxs),
              // **Three tiers, not one line.** Everything below the name used to sit in a single
              // `Wrap`, so the amount, the due date, three possible chips and two buttons reflowed
              // into each other and nothing read as more important than anything else. Split by
              // role: the figure, then when it lands, then what is unusual about it, then what you
              // can do. Each tier wraps internally, so 320dp at a doubled scale still reflows
              // rather than overflowing (Law U21).
              Padding(
                padding: const EdgeInsets.only(left: AlayaIconSize.lg + AlayaSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The figure, at full size. It is the thing a glance is looking for.
                    AmountText(
                      template.defaultAmount,
                      showSign: false,
                      decimalDigits: decimalDigits,
                      muted: template.isPaused,
                    ),
                    const SizedBox(height: AlayaSpacing.xxs),
                    // When it lands. Shown whether or not an occurrence exists yet: materialisation
                    // only reaches today, so a bill paid this month has nothing outstanding until
                    // next month, and an empty space where the Record button was reads as a broken
                    // screen rather than as "nothing to do".
                    Wrap(
                      spacing: AlayaSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          strings.recurringNextDue,
                          style: AlayaTypography.caption.copyWith(color: semantic.muted),
                        ),
                        DateText(
                          occurrence?.dueDateKey ?? template.nextDueDateKey,
                          style: DateTextStyle.medium,
                          muted: true,
                        ),
                      ],
                    ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xxs,
                        children: chips,
                      ),
                    ],
                    if (onPay != null || onTogglePause != null) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      // Actions last and on their own line, so a destructive-feeling Pause is never
                      // adjacent to the figure it would suspend.
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (onPay != null)
                            FilledButton.tonal(
                              onPressed: onPay,
                              child: Text(strings.payCommit),
                            ),
                          if (onTogglePause != null)
                            TextButton(
                              onPressed: onTogglePause,
                              child: Text(
                                template.isPaused
                                    ? strings.actionResume
                                    : strings.actionPause,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```
### `lib/features/recurring/presentation/screens/template_list_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/presentation/widgets/template_row.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Everything that repeats (ARCH_5 §3 archetype D).
///
/// **Nothing on this screen pays anything by itself.** Mounting it materialises occurrences up to
/// today so the list can show what is due; every one of them is created `due`, and money appears only
/// when the user taps Record (anomaly A14).
class TemplateListScreen extends ConsumerWidget {
  /// Creates the screen.
  const TemplateListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(templateGroupsProvider);
    final overdue = ref.watch(overdueCountProvider);

    return Scaffold(
      body: groups.when(
        loading: () => AlayaListSkeleton(label: strings.loadingRecurring),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () {
            ref.invalidate(materialiseProvider);
            ref.invalidate(templatesProvider);
          },
        ),
        data: (sections) => sections.isEmpty
            ? EmptyState(
                title: strings.emptyTitleNoTemplates,
                body: strings.emptyBodyNoTemplates,
                icon: Icons.event_repeat_outlined,
                actionLabel: strings.addTemplate,
                onAction: () => context.push(Routes.recurringNew),
              )
            : Column(
                children: [
                  if (overdue > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AlayaSpacing.screenEdge,
                        AlayaSpacing.sm,
                        AlayaSpacing.screenEdge,
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusChip(
                          label: strings.recurringOverdue,
                          tone: StatusTone.danger,
                          trailing: Text(
                            '$overdue',
                            style: AlayaTypography.overline
                                .copyWith(color: context.semantic.onStatus),
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: _Sections(sections: sections)),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.recurringNew),
        tooltip: strings.addTemplate,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({required this.sections});

  final List<TemplateGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;
    final actions = ref.read(templateActionsProvider);

    Future<void> guard(Future<String?> Function() run) async {
      final error = await run();
      if (!context.mounted || error == null) return;
      showFailureSnack(context, message: error);
    }

    return CustomScrollView(
      slivers: [
        for (final section in sections)
          SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.md,
                    AlayaSpacing.screenEdge,
                    AlayaSpacing.xs,
                  ),
                  child: Text(
                    section.direction == RecurringDirection.inflow
                        ? strings.recurringInflow
                        : strings.recurringOutflow,
                    style: AlayaTypography.sectionHeader.copyWith(color: semantic.muted),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: section.rows.length,
                itemBuilder: (context, index) {
                  final row = section.rows[index];
                  final next = row.next;
                  return TemplateRowTile(
                    template: row.template,
                    next: next,
                    today: today,
                    decimalDigits: digits,
                    onTap: () =>
                        context.push(Routes.recurringHistory(row.template.id)),
                    onPay: next == null || row.template.isPaused
                        ? null
                        : () => PaySheet.show(
                              context,
                              occurrenceId: next.id,
                              template: row.template,
                            ),
                    onTogglePause: () => guard(
                      () => actions.setPaused(
                        id: row.template.id,
                        isPaused: !row.template.isPaused,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
      ],
    );
  }
}
```
### `lib/features/recurring/presentation/screens/template_builder_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Builds a recurring template (ARCH_5 §3 archetype B), outside the drawer shell (U18).
///
/// **The preview is the point of the screen.** `anchorDayOfMonth` is stored once and clamped at every
/// render, so a bill anchored on the 31st lands Jan 31 → Feb 28 → Mar 31 (anomaly A13). Nothing about
/// typing 31 tells the user that; seeing February shortened and March return does. It updates on every
/// change to the frequency, which is why it sits directly under the fields that drive it rather than at
/// the bottom of the form.
class TemplateBuilderScreen extends ConsumerWidget {
  /// Edits [templateId], or creates a new template when it is null.
  const TemplateBuilderScreen({this.templateId, super.key});

  /// The template being edited, or null for a new one.
  final String? templateId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(templateBuilderProvider(templateId).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      // The reason, not a stand-in for it. The builder has three ways to be incomplete and one way to
      // be rejected, and a single generic message distinguishes none of them (Law U9).
      final state = ref.read(templateBuilderProvider(templateId)).valueOrNull;
      showFailureSnack(
        context,
        message: state?.rejection ?? _issueMessage(strings, state?.issue),
      );
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  static String _issueMessage(AlayaStrings strings, TemplateSaveIssue? issue) =>
      switch (issue) {
        TemplateSaveIssue.nameMissing => strings.errorFieldRequired,
        TemplateSaveIssue.amountMissing => strings.errorAmountInvalid,
        TemplateSaveIssue.anchorMissing => strings.anchorDayHelp,
        TemplateSaveIssue.rejected || null => strings.errorBodyGeneric,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(templateBuilderProvider(templateId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(templateId == null ? strings.editorTitleNew : strings.editorTitleEdit),
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingRecurring, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveTemplate,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: templateId, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final TemplateBuilderState state;

  static String _kindLabel(AlayaStrings strings, RecurringKind kind) => switch (kind) {
        RecurringKind.bill => strings.kindBill,
        RecurringKind.subscription => strings.kindSubscription,
        RecurringKind.rent => strings.kindRent,
        RecurringKind.salary => strings.kindSalary,
        RecurringKind.serviceFee => strings.kindServiceFee,
        RecurringKind.other => strings.kindOther,
      };

  static String _unitLabel(AlayaStrings strings, RecurringIntervalUnit unit, int count) =>
      switch (unit) {
        RecurringIntervalUnit.day => strings.unitDay(count),
        RecurringIntervalUnit.week => strings.unitWeek(count),
        RecurringIntervalUnit.month => strings.unitMonth(count),
        RecurringIntervalUnit.year => strings.unitYear(count),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(templateBuilderProvider(editorId).notifier);
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts = ref.watch(builderAccountsProvider).valueOrNull ?? const <Account>[];
    final dates = ref.watch(previewProvider(editorId));
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) => DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    // The dropdown's value comes from the list being rendered, never from state: the accounts arrive
    // from a stream, and a value matching none of the items throws (ARCH_4 R33).
    Account? selectedAccount;
    for (final account in accounts) {
      if (account.id == state.accountId) selectedAccount = account;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.builderSectionWhat,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.labelTemplateName,
              errorText: state.issue == TemplateSaveIssue.nameMissing
                  ? strings.errorFieldRequired
                  : null,
            ),
            onChanged: notifier.setName,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<RecurringKind>(
          key: ValueKey(state.kind),
          initialValue: state.kind,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelRecurringKind),
          items: [
            for (final kind in RecurringKind.values)
              DropdownMenuItem(value: kind, child: Text(_kindLabel(strings, kind))),
          ],
          onChanged: (value) => value == null ? null : notifier.setKind(value),
        ),
        const SizedBox(height: AlayaSpacing.md),
        SegmentedButton<RecurringDirection>(
          segments: [
            ButtonSegment(
              value: RecurringDirection.outflow,
              label: Text(strings.directionOutflow),
            ),
            ButtonSegment(
              value: RecurringDirection.inflow,
              label: Text(strings.directionInflow),
            ),
          ],
          selected: {state.direction},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => notifier.setDirection(selection.first),
        ),
        SectionHeader(
          label: strings.builderSectionWhen,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        // `Wrap`, not `Row`: the count field, the unit dropdown and their label all grow with text
        // scale, and at 320dp a Row starves whichever comes first (Law U21).
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              strings.labelEvery,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            // Not `isDense`: it takes the field to 46px, under the 48dp tap-target floor (Law U16).
            // A `ConstrainedBox` keeps the field narrow without shrinking what a finger has to hit.
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AlayaSpacing.xxxl * 2,
                maxWidth: AlayaSpacing.xxxl * 2,
                minHeight: AlayaSpacing.minTapTarget,
              ),
              child: TextFormField(
                initialValue: '${state.intervalCount}',
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                onChanged: (raw) =>
                    notifier.setIntervalCount(int.tryParse(raw.trim()) ?? 1),
              ),
            ),
            DropdownButton<RecurringIntervalUnit>(
              value: state.intervalUnit,
              items: [
                for (final unit in RecurringIntervalUnit.values)
                  DropdownMenuItem(
                    value: unit,
                    child: Text(_unitLabel(strings, unit, state.intervalCount)),
                  ),
              ],
              onChanged: (value) =>
                  value == null ? null : notifier.setIntervalUnit(value),
            ),
          ],
        ),
        if (state.needsDayAnchor) ...[
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.anchorDayOfMonth?.toString(),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.labelAnchorDay,
              helperText: strings.anchorDayHelp,
              helperMaxLines: 4,
              errorText: state.issue == TemplateSaveIssue.anchorMissing
                  ? strings.errorFieldRequired
                  : null,
            ),
            onChanged: (raw) => notifier.setAnchorDay(int.tryParse(raw.trim())),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.startDateKey,
          formatted: format,
          label: strings.labelStartDate,
          hint: strings.hintSelectDate,
          onChanged: notifier.setStartDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.endDateKey,
          formatted: format,
          label: strings.labelEndDate,
          hint: strings.hintSelectDate,
          onChanged: notifier.setEndDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        FrequencyPreview(dates: dates),
        SectionHeader(
          label: strings.builderSectionDefaults,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        AmountField(
          currencyCode: state.currencyCode,
          decimalDigits: digits,
          label: strings.labelDefaultAmount,
          initialValue: state.amount,
          errorText: state.issue == TemplateSaveIssue.amountMissing
              ? strings.errorAmountInvalid
              : null,
          onChanged: notifier.setAmount,
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (accounts.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(selectedAccount?.id),
            initialValue: selectedAccount?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelAccount),
            items: [
              for (final account in accounts)
                DropdownMenuItem(value: account.id, child: Text(account.name)),
            ],
            onChanged: notifier.setAccount,
          ),
        const SizedBox(height: AlayaSpacing.md),
        SwitchListTile(
          value: state.autoRemind,
          contentPadding: EdgeInsets.zero,
          title: Text(strings.labelRemindBefore),
          secondary: Icon(
            state.autoRemind ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            size: AlayaIconSize.md,
            color: semantic.muted,
          ),
          onChanged: (_) => notifier.toggleRemind(),
        ),
        if (state.autoRemind)
          TextFormField(
            initialValue: '${state.remindDaysBefore}',
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: strings.labelRemindBefore),
            onChanged: (raw) =>
                notifier.setRemindDaysBefore(int.tryParse(raw.trim()) ?? 0),
          ),
        SectionHeader(
          label: strings.labelNote,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        TextFormField(
          initialValue: state.note,
          maxLines: 3,
          decoration: InputDecoration(hintText: strings.hintNote),
          onChanged: notifier.setNote,
        ),
        if (state.issue == TemplateSaveIssue.rejected && state.rejection != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          AlayaCard(
            padding: const EdgeInsets.all(AlayaSpacing.sm),
            child: Text(
              state.rejection!,
              style: AlayaTypography.body.copyWith(color: semantic.danger),
            ),
          ),
        ],
      ],
    );
  }
}
```
### `lib/features/recurring/presentation/sheets/pay_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/recurring/state/pay_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Records what was actually paid (ARCH_5 §3 archetype A).
///
/// **The default is pre-filled and the actual is editable, and both are kept.** A bill quoted at ₹1,200
/// arriving at ₹1,247 is the ordinary case: pre-filling means the common path is one tap, and storing
/// what was really paid is what lets the history show the gap rather than pretending it did not happen.
///
/// **This is the only place money is created for a recurring template.** Materialisation produces `due`
/// rows and nothing else (anomaly A14); the transaction exists because someone tapped here.
class PaySheet extends ConsumerWidget {
  /// Creates the sheet.
  const PaySheet({required this.occurrenceId, required this.template, super.key});

  /// Which occurrence is being settled.
  final String occurrenceId;

  /// The template it belongs to, for the default amount, account and wording.
  final RecurringTemplate template;

  /// Opens the sheet.
  static Future<void> show(
    BuildContext context, {
    required String occurrenceId,
    required RecurringTemplate template,
  }) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => PaySheet(occurrenceId: occurrenceId, template: template),
      );

  PayArgs get _args => (
        occurrenceId: occurrenceId,
        defaultMinor: template.defaultAmount.minor,
        currencyCode: template.defaultAmount.currencyCode,
        accountId: template.defaultAccountId,
      );

  Future<void> _commit(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final created = await ref.read(payProvider(_args).notifier).commit();
    if (!context.mounted) return;
    if (created == null) {
      final state = ref.read(payProvider(_args));
      showFailureSnack(
        context,
        message: state.rejection ??
            switch (state.issue) {
              PayIssue.amountMissing => strings.errorAmountInvalid,
              PayIssue.accountMissing => strings.payNeedsAccount,
              PayIssue.rejected || null => strings.errorBodyGeneric,
            },
      );
      return;
    }
    Navigator.of(context).pop();
    if (!context.mounted) return;
    // Undo is offered, and the confirmation behind it says exactly what gets reversed and in which
    // order (ARCH_5 §5.4) — paying creates a transaction, so undoing it must remove one.
    showUndoSnack(
      context,
      message: strings.payRecorded,
      undoLabel: strings.actionUndo,
      onUndo: () async {
        final error = await ref.read(occurrenceActionsProvider).undoPayment(
              occurrenceId: occurrenceId,
              transactionId: created,
            );
        if (!context.mounted) return;
        error == null
            ? showResultSnack(context, message: strings.payUndone)
            : showFailureSnack(context, message: error);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final state = ref.watch(payProvider(_args));
    final notifier = ref.read(payProvider(_args).notifier);
    final currency = template.defaultAmount.currencyCode;
    final digits = ref.watch(payDecimalDigitsProvider(currency)).valueOrNull ?? 2;
    final accounts = ref.watch(payAccountsProvider).valueOrNull ?? const <Account>[];
    final inflow = template.direction == RecurringDirection.inflow;
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) => DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    Account? selectedAccount;
    for (final account in accounts) {
      if (account.id == state.accountId) selectedAccount = account;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          inflow ? strings.payTitleInflow : strings.payTitle,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Text(
          template.name,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            label: inflow ? strings.labelActualAmountInflow : strings.labelActualAmount,
            initialValue: state.amount,
            autofocus: true,
            errorText: state.issue == PayIssue.amountMissing
                ? strings.errorAmountInvalid
                : null,
            onChanged: notifier.setAmount,
          ),
        ),
        if (state.differsFromDefault) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          // Shown only when they differ. Repeating the default under an unchanged figure is noise;
          // showing it beside a changed one is the confirmation that the change was deliberate.
          Wrap(
            spacing: AlayaSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                strings.payUsualWas,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              AmountText(
                state.defaultAmount,
                size: AmountSize.small,
                showSign: false,
                decimalDigits: digits,
                muted: true,
              ),
            ],
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.paidOn,
          formatted: format,
          label: strings.labelPaidOn,
          hint: strings.hintSelectDate,
          onChanged: notifier.setPaidOn,
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (accounts.isNotEmpty)
          DropdownButtonFormField<String>(
            key: ValueKey(selectedAccount?.id),
            initialValue: selectedAccount?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: strings.labelAccount,
              errorText: state.issue == PayIssue.accountMissing
                  ? strings.payNeedsAccount
                  : null,
            ),
            items: [
              for (final account in accounts)
                DropdownMenuItem(value: account.id, child: Text(account.name)),
            ],
            onChanged: notifier.setAccount,
          ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.note,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: strings.labelNote,
            hintText: strings.hintNote,
          ),
          onChanged: notifier.setNote,
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting ? null : () => _commit(context, ref),
          child: Text(strings.payCommit),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }
}
```
### `lib/features/recurring/presentation/screens/occurrence_history_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/occurrence_history_providers.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// One template's occurrences (ARCH_5 §3 archetype C), outside the drawer shell (U18).
///
/// **Shows the actual against the usual, but only where they differ.** `paidAmount` is what really
/// left the account and `defaultAmount` is what the template expects; a bill that came in high is the
/// §7.2 row this screen closes, and repeating the default under every unchanged row would bury it.
class OccurrenceHistoryScreen extends ConsumerWidget {
  /// Shows the occurrences of [templateId].
  const OccurrenceHistoryScreen({required this.templateId, super.key});

  /// Which template's history to show.
  final String templateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final template = ref.watch(historyTemplateProvider(templateId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.historyRecurringTitle),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.recurringEdit(templateId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: template.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingRecurring, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(historyTemplateProvider(templateId)),
        ),
        data: (value) => value == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(template: value),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.template});

  final RecurringTemplate template;

  Future<void> _undo(
    BuildContext context,
    WidgetRef ref,
    RecurringOccurrence occurrence,
  ) async {
    final strings = AlayaStrings.of(context);
    final transactionId = occurrence.paidTransactionId;
    if (transactionId == null) return;
    // Consequential, and the body names both halves and their order (ARCH_5 §5.4): the obligation
    // returns to due, then the transaction it created is deleted along with anything that transaction
    // produced.
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.payUndoTitle,
      body: strings.payUndoBody,
      confirmLabel: strings.actionUndo,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final error = await ref.read(occurrenceActionsProvider).undoPayment(
          occurrenceId: occurrence.id,
          transactionId: transactionId,
        );
    if (!context.mounted) return;
    error == null
        ? showResultSnack(context, message: strings.payUndone)
        : showFailureSnack(context, message: error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(occurrencesProvider(template.id));
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;

    return async.when(
      loading: () => AlayaListSkeleton(label: strings.loadingRecurring),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(occurrencesProvider(template.id)),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return EmptyState(
            title: strings.emptyTitleNoOccurrences,
            body: strings.emptyBodyNoOccurrences,
            icon: Icons.event_repeat_outlined,
          );
        }
        final ordered = [...rows]
          ..sort((a, b) => b.dueDateKey.compareTo(a.dueDateKey));
        return CustomScrollView(
          slivers: [
            AlayaTimeline(
              itemCount: ordered.length,
              itemBuilder: (context, index) {
                final occurrence = ordered[index];
                final paid = occurrence.paidAmount;
                final overdue = occurrence.isOverdue(today);
                final differs = paid != null && paid != template.defaultAmount;

                return AlayaTimelineEntry(
                  title: switch (occurrence.status) {
                    RecurringOccurrenceStatus.paid => strings.statusPaid,
                    RecurringOccurrenceStatus.skipped => strings.occurrenceSkipped,
                    RecurringOccurrenceStatus.dismissed => strings.statusDismissed,
                    RecurringOccurrenceStatus.due =>
                      overdue ? strings.recurringOverdue : strings.statusDue,
                  },
                  trailing: AmountText(
                    paid ?? template.defaultAmount,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: digits,
                    muted: !occurrence.isPaid,
                  ),
                  subtitle: DateText(
                    occurrence.dueDateKey,
                    style: DateTextStyle.medium,
                    muted: true,
                  ),
                  meta: differs ? strings.historyDefaultVsActual : occurrence.note,
                  icon: switch (occurrence.status) {
                    RecurringOccurrenceStatus.paid => Icons.check_circle_outline,
                    RecurringOccurrenceStatus.skipped => Icons.redo,
                    RecurringOccurrenceStatus.dismissed => Icons.block,
                    RecurringOccurrenceStatus.due => Icons.schedule,
                  },
                  tone: switch (occurrence.status) {
                    RecurringOccurrenceStatus.paid =>
                      template.direction == RecurringDirection.inflow
                          ? TimelineTone.incoming
                          : TimelineTone.outgoing,
                    RecurringOccurrenceStatus.skipped ||
                    RecurringOccurrenceStatus.dismissed =>
                      TimelineTone.superseded,
                    RecurringOccurrenceStatus.due =>
                      overdue ? TimelineTone.outgoing : TimelineTone.neutral,
                  },
                  badge: differs ? strings.historyDefaultVsActual : null,
                  onTap: occurrence.isPaid
                      ? () => _undo(context, ref, occurrence)
                      : occurrence.isOutstanding
                          ? () => PaySheet.show(
                                context,
                                occurrenceId: occurrence.id,
                                template: template,
                              )
                          : null,
                );
              },
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
                child: Text(
                  strings.emptyBodyNoOccurrences,
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
```
### `test/support/recurring_harness.dart`

```dart
/// Shared scaffolding for the Recurring module's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so overdue derivation is the same on every machine.
final Clock kRecurringClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kRecurringClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// An account the pay sheet can draw from.
const Account kAccount = Account(
  id: 'acc-1',
  name: 'Everyday',
  normalizedName: 'everyday',
  kind: AccountKind.bank,
  currencyCode: 'INR',
  openingBalance: Money(0, 'INR'),
  openingBalanceDateKey: kToday,
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// A monthly bill anchored on the 31st — the clamp case anomaly A13 is about.
RecurringTemplate billTemplate({
  String id = 'tpl-1',
  String name = 'Rent',
  int amountMinor = 120000,
  RecurringDirection direction = RecurringDirection.outflow,
  RecurringKind kind = RecurringKind.rent,
  RecurringIntervalUnit unit = RecurringIntervalUnit.month,
  int intervalCount = 1,
  int? anchorDayOfMonth = 31,
  bool isPaused = false,
  DateKey nextDue = const DateKey(20260831),
  DateKey? endDateKey,
}) =>
    RecurringTemplate(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      kind: kind,
      direction: direction,
      defaultAmount: Money(amountMinor, 'INR'),
      intervalUnit: unit,
      intervalCount: intervalCount,
      startDateKey: const DateKey(20260131),
      nextDueDateKey: nextDue,
      isPaused: isPaused,
      autoRemind: true,
      remindDaysBefore: 3,
      defaultAccountId: kAccount.id,
      anchorDayOfMonth: anchorDayOfMonth,
      endDateKey: endDateKey,
    );

/// A salary, so an inflow can be asserted to read as income.
RecurringTemplate salaryTemplate({String id = 'tpl-2'}) => billTemplate(
      id: id,
      name: 'Salary',
      amountMinor: 8500000,
      direction: RecurringDirection.inflow,
      kind: RecurringKind.salary,
      anchorDayOfMonth: 1,
      nextDue: const DateKey(20260901),
    );

/// An occurrence in any state.
RecurringOccurrence occurrence({
  String id = 'occ-1',
  String templateId = 'tpl-1',
  DateKey dueDateKey = const DateKey(20260831),
  RecurringOccurrenceStatus status = RecurringOccurrenceStatus.due,
  int? paidMinor,
  String? paidTransactionId,
}) =>
    RecurringOccurrence(
      id: id,
      templateId: templateId,
      dueDateKey: dueDateKey,
      status: status,
      paidAmount: paidMinor == null ? null : Money(paidMinor, 'INR'),
      paidTransactionId: paidTransactionId,
      paidDateKey: paidMinor == null ? null : dueDateKey,
    );

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpRecurring(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/features/recurring/template_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/recurring/presentation/widgets/template_row.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/recurring_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<TemplateGroup>> groups) => [
        clockProvider.overrideWithValue(kRecurringClock),
        templateGroupsProvider.overrideWith((ref) => groups),
        overdueCountProvider.overrideWith((ref) => 0),
        builderDecimalDigitsProvider.overrideWith((ref) async => 2),
      ];

  final outflow = AsyncValue.data([
    TemplateGroup(
      direction: RecurringDirection.outflow,
      rows: [TemplateRow(template: billTemplate(), next: occurrence())],
    ),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the first template', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing recurring yet'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('populated groups outflow under its own header', (tester) async {
    await pumpRecurring(tester, const TemplateListScreen(), overrides: overrides(outflow));
    await tester.pumpAndSettle();
    expect(find.byType(TemplateRowTile), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Going out'), findsOneWidget);
  });

  testWidgets('an inflow reads as income, not a negative bill', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.inflow,
            rows: [
              TemplateRow(
                template: salaryTemplate(),
                next: occurrence(id: 'occ-2', templateId: 'tpl-2'),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    // Its own group, and the amount unsigned. A salary shown as minus eighty-five thousand under a
    // list of bills is the §7.2 row this module exists to close.
    expect(find.text('Coming in'), findsOneWidget);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.textContaining('-'), findsNothing);
  });

  testWidgets('overdue is derived from the clock, not a stored flag', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.outflow,
            rows: [
              TemplateRow(
                template: billTemplate(),
                // Due in July, clock fixed to 1 August. Nothing on the entity says "overdue".
                next: occurrence(dueDateKey: const DateKey(20260715)),
              ),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsWidgets);
  });

  testWidgets('a paused template says so and offers no pay button', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.outflow,
            rows: [
              TemplateRow(template: billTemplate(isPaused: true), next: occurrence()),
            ],
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    // Nothing is paid while paused: an occurrence may exist, but the obligation is suspended.
    expect(find.widgetWithText(FilledButton, 'Record it'), findsNothing);
  });


  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateListScreen(),
      overrides: overrides(
        AsyncValue.data([
          TemplateGroup(
            direction: RecurringDirection.outflow,
            rows: [
              TemplateRow(
                template: billTemplate(),
                next: occurrence(dueDateKey: const DateKey(20260715)),
              ),
            ],
          ),
        ]),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRecurring(tester, const TemplateListScreen(), overrides: overrides(outflow));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```
### `test/features/recurring/template_builder_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';

import '../../support/recurring_harness.dart';

/// Four states, plus the reason this screen exists: the preview is the only way a user can see a clamp.
void main() {
  TemplateBuilderState state({
    String name = 'Rent',
    int? amountMinor = 120000,
    RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    int? anchorDayOfMonth = 31,
    DateKey start = const DateKey(20260131),
    DateKey? end,
    TemplateSaveIssue? issue,
    String? rejection,
  }) =>
      TemplateBuilderState(
        currencyCode: 'INR',
        startDateKey: start,
        name: name,
        amount: amountMinor == null ? null : Money(amountMinor, 'INR'),
        intervalUnit: unit,
        anchorDayOfMonth: anchorDayOfMonth,
        endDateKey: end,
        issue: issue,
        rejection: rejection,
      );

  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`.
  List<Override> overrides(AsyncValue<TemplateBuilderState> value) => [
        templateBuilderProvider.overrideWith(() => _StubBuilder(value)),
        builderDecimalDigitsProvider.overrideWith((ref) async => 2),
        builderAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
        recurringEngineProvider.overrideWithValue(const RecurringEngine()),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new template opens on the form, which is its empty state', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state(name: '', amountMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
  });

  testWidgets('the preview shows the anchor clamping and returning', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    // Anchored on the 31st from 31 January: Jan 31 → Feb 28 → Mar 31. February is shortened and March
    // returns to the 31st — the anchor never walks backwards (anomaly A13), and this is the only place
    // a user can see that happening.
    expect(find.byType(FrequencyPreview), findsOneWidget);
    expect(find.text('Shortened to fit the month'), findsOneWidget);
  });

  testWidgets('a weekly template never reports a clamp', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(unit: RecurringIntervalUnit.week, anchorDayOfMonth: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Only a monthly or yearly interval anchors to a day, so there is nothing to clamp.
    expect(find.text('Shortened to fit the month'), findsNothing);
    expect(find.text('On day of the month'), findsNothing);
  });

  testWidgets('an incomplete template previews nothing rather than a guess', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state(name: '', amountMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set a start date to see when this lands.'), findsOneWidget);
  });

  testWidgets('an end date truncates the preview instead of promising three', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state(end: const DateKey(20260215)))),
    );
    await tester.pumpAndSettle();
    // Ends mid-February, so only 31 January survives. Showing three would describe a schedule that
    // will not happen.
    expect(find.byType(FrequencyPreview), findsOneWidget);
    expect(find.text('Shortened to fit the month'), findsNothing);
  });

  testWidgets('a rejection is shown in the repository own words', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            issue: TemplateSaveIssue.rejected,
            rejection: 'A monthly template needs a day of the month to anchor to.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('needs a day of the month'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state())),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRecurring(
      tester,
      const TemplateBuilderScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the clamp itself', () {
    const engine = RecurringEngine();

    test('an anchor of 31 lands on the last day of a short month and then returns', () {
      final template = billTemplate(nextDue: const DateKey(20260131));
      final feb = engine.nextDue(from: const DateKey(20260131), template: template);
      final mar = engine.nextDue(from: feb, template: template);
      expect(feb, const DateKey(20260228));
      // The point of storing the anchor rather than advancing it: March returns to the 31st instead of
      // inheriting February's 28 forever.
      expect(mar, const DateKey(20260331));
    });

    test('a February anchor survives a leap year', () {
      expect(engine.clampDayOfMonth(31, 2028, 2), 29);
      expect(engine.clampDayOfMonth(31, 2026, 2), 28);
      expect(engine.clampDayOfMonth(15, 2026, 2), 15);
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubBuilder extends TemplateBuilderNotifier {
  _StubBuilder(this._value);

  final AsyncValue<TemplateBuilderState> _value;

  @override
  AsyncValue<TemplateBuilderState> build(String? arg) => _value;
}
```
### `test/features/recurring/pay_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/features/recurring/state/pay_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/recurring_harness.dart';

/// The capture path: the default is pre-filled, the actual is editable, and both are kept.
void main() {
  /// A fixed-length override list.
  ///
  /// The length must not vary between scopes — a conditional entry is what produced *"Tried to change
  /// the number of overrides"*. `seed` defaults to the state the notifier would build anyway.
  List<Override> overrides({PayState? seed}) => [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
        payProvider.overrideWith(
          () => _StubPay(
            seed ??
                PayState(
                  occurrenceId: 'occ-1',
                  defaultAmount: const Money(120000, 'INR'),
                  amount: const Money(120000, 'INR'),
                  paidOn: kToday,
                  accountId: kAccount.id,
                ),
          ),
        ),
      ];

  Widget host() => Scaffold(
        body: AlayaBottomSheet(
          child: PaySheet(occurrenceId: 'occ-1', template: billTemplate()),
        ),
      );

  testWidgets('opens with the usual amount already filled in', (tester) async {
    await pumpRecurring(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // The common case is that it cost what it usually costs, so that path is one tap.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('Amount actually paid'), findsOneWidget);
  });

  testWidgets('an inflow asks what was received, not what was paid', (tester) async {
    await pumpRecurring(
      tester,
      Scaffold(
        body: AlayaBottomSheet(
          child: PaySheet(occurrenceId: 'occ-2', template: salaryTemplate()),
        ),
      ),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Record this receipt'), findsOneWidget);
    expect(find.text('Amount actually received'), findsOneWidget);
  });

  // **Two tests, not two pumps.** A second `pumpWidget` in one `testWidgets` reuses the same
  // `ProviderScope`, so a differing override count throws *"Tried to change the number of
  // overrides"* — and even with a matching count the scope updates rather than replaces, so the new
  // override silently never installs and the test passes for the wrong reason (ARCH_4 P5).
  testWidgets('the usual figure is hidden while the actual matches it', (tester) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          amount: const Money(120000, 'INR'),
          paidOn: kToday,
          accountId: kAccount.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Repeating the default under an unchanged figure is noise.
    expect(find.text('Usually'), findsNothing);
  });

  testWidgets('the usual figure appears once the actual differs', (tester) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          amount: const Money(124700, 'INR'),
          paidOn: kToday,
          accountId: kAccount.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Beside a changed one it confirms the change was deliberate.
    expect(find.text('Usually'), findsOneWidget);
  });

  testWidgets('a missing amount shakes rather than writing zero', (tester) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          paidOn: kToday,
          accountId: kAccount.id,
          issue: PayIssue.amountMissing,
          shakeTrigger: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShakeOnError), findsOneWidget);
    expect(find.text('Enter an amount'), findsOneWidget);
  });

  testWidgets('a missing account is named, not reported generically', (tester) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: overrides(
        seed: PayState(
          occurrenceId: 'occ-1',
          defaultAmount: const Money(120000, 'INR'),
          amount: const Money(120000, 'INR'),
          paidOn: kToday,
          issue: PayIssue.accountMissing,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose which account it came from'), findsOneWidget);
  });

  testWidgets('loading accounts still lets the amount be typed', (tester) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith((ref) => pendingStream<List<Account>>()),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pump();
    // A capture sheet takes its first keystroke on its first frame (§5.2): the account list is still
    // arriving and the amount field is already there, pre-filled.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('no accounts at all omits the picker rather than blocking', (tester) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed account stream does not take the sheet down', (tester) async {
    await pumpRecurring(
      tester,
      host(),
      overrides: [
        clockProvider.overrideWithValue(kRecurringClock),
        payAccountsProvider
            .overrideWith((ref) => Stream<List<Account>>.error(StateError('boom'))),
        payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
      ],
    );
    await tester.pumpAndSettle();
    // The template carries a default account, so a failed lookup costs the picker, not the payment.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Record it'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(tester, host(), overrides: overrides(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRecurring(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('state', () {
    test('differsFromDefault is false until the figure changes', () {
      const base = PayState(
        occurrenceId: 'occ-1',
        defaultAmount: Money(120000, 'INR'),
        amount: Money(120000, 'INR'),
        paidOn: kToday,
      );
      expect(base.differsFromDefault, isFalse);
      expect(
        base.copyWith(amount: const Money(124700, 'INR')).differsFromDefault,
        isTrue,
      );
    });

    test('an issue survives an unrelated copyWith', () {
      const base = PayState(
        occurrenceId: 'occ-1',
        defaultAmount: Money(120000, 'INR'),
        paidOn: kToday,
        issue: PayIssue.accountMissing,
      );
      // ARCH_4 R31: a bare assignment let `submitting: false` in a `finally` erase the reason
      // microseconds before the sheet read it. It must survive, and clear only when asked.
      expect(base.copyWith(submitting: false).issue, PayIssue.accountMissing);
      expect(base.copyWith(clearIssue: true).issue, isNull);
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubPay extends PayNotifier {
  _StubPay(this._value);

  final PayState _value;

  @override
  PayState build(PayArgs arg) => _value;
}
```

### `test/features/recurring/occurrence_history_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/providers/occurrence_history_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/recurring_harness.dart';

/// Four states, plus the §7.2 row: the actual against the usual, where they differ.
void main() {
  const templateId = 'tpl-1';

  List<Override> overrides({
    RecurringTemplate? template,
    List<RecurringOccurrence>? occurrences,
    bool pending = false,
    bool fail = false,
  }) =>
      [
        clockProvider.overrideWithValue(kRecurringClock),
        builderDecimalDigitsProvider.overrideWith((ref) async => 2),
        historyTemplateProvider(templateId)
            .overrideWith((ref) async => template ?? billTemplate()),
        if (pending)
          occurrencesProvider(templateId)
              .overrideWith((ref) => pendingStream<List<RecurringOccurrence>>())
        else if (fail)
          occurrencesProvider(templateId).overrideWith(
            (ref) => Stream<List<RecurringOccurrence>>.error(StateError('boom')),
          )
        else
          occurrencesProvider(templateId)
              .overrideWith((ref) => Stream.value(occurrences ?? const [])),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(pending: true),
    );
    await tester.pump();
    expect(find.byType(AlayaListSkeleton), findsWidgets);
  });

  testWidgets('empty states plainly that nothing is ever paid for you', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    // Anomaly A14 said out loud: materialisation creates due rows, never payments.
    expect(find.textContaining('Nothing is ever paid for you'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('populated renders a timeline of occurrences', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            paidMinor: 120000,
            paidTransactionId: 't1',
          ),
          occurrence(id: 'o2', dueDateKey: const DateKey(20260731)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaTimeline), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
  });

  testWidgets('a payment that differed from the usual amount is marked', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            // Template default is 1,200.00; this one came in at 1,247.00.
            paidMinor: 124700,
            paidTransactionId: 't1',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Differed from the usual amount'), findsWidgets);
  });

  testWidgets('a payment at the usual amount is not marked', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            paidMinor: 120000,
            paidTransactionId: 't1',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Differed from the usual amount'), findsNothing);
  });

  testWidgets('a skipped occurrence reads as skipped, not as paid', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.skipped,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Skipped'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [
          occurrence(
            id: 'o1',
            dueDateKey: const DateKey(20260630),
            status: RecurringOccurrenceStatus.paid,
            paidMinor: 124700,
            paidTransactionId: 't1',
          ),
          occurrence(id: 'o2', dueDateKey: const DateKey(20260715)),
        ],
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRecurring(
      tester,
      const OccurrenceHistoryScreen(templateId: templateId),
      overrides: overrides(
        occurrences: [occurrence(id: 'o2', dueDateKey: const DateKey(20260731))],
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```
### `test/shared/layout_overflow_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';
// Prefixed: `kToday` and `kNarrowPhone` are declared by every harness in this project, and this is
// the only file that imports two of them.
import '../support/calendar_harness.dart' as cal;

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AlayaTheme.light(AlayaPresets.activePreset),
          // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
          // delegate installed. The Phase 5 groups pass literal strings, so this file went without
          // one until real screens arrived — and then failed as a null-check rather than as a
          // missing translation, which is why it read like five separate defects.
          localizationsDelegates: const [
            AlayaStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AlayaStrings.supportedLocales,
          // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
          // view, so an outer one is discarded before anything under test can read it — and a test
          // that believes it has simulated a keyboard when it has not is worse than no test.
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
              textScaler: TextScaler.linear(textScale),
            ),
            child: inner!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [SizedBox(width: 200, height: 400)],
      );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (tester) async {
      await tester.pumpWidget(
        host(AlayaBottomSheet(child: tallContent()), bottomInset: keyboardInset),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (tester) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
          primaryLabel: 'Save expense',
          onPrimary: () {},
          secondaryLabel: 'Cancel',
          onSecondary: () {},
          isDirty: true,
          isSubmitting: submitting,
          discardTitle: 'Discard your changes?',
          discardBody: 'What you have typed will not be saved.',
          discardConfirmLabel: 'Discard',
          discardCancelLabel: 'Keep editing',
          child: const Column(
            children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
          ),
        );

    testWidgets('body scrolls and the footer stays above the keyboard', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset, textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (tester) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider
          .overrideWith((ref) => Stream.value(<String, Account>{kAccount.id: kAccount})),
      lineEditorItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('QuickAddSheet', (tester) => pumpSheet(tester, const QuickAddSheet()));

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) => pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider('item-1').overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider('list-1').overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith((ref) => Stream.value(const <String, Item>{})),
      allListsProvider.overrideWith((ref) => Stream.value(const <ShoppingList>[])),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name: 'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(title: 'A payee with a name long enough to wrap at a doubled scale', amountMinor: 98765432),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the month grid at a tripled scale, which is past what U15 asks for',
        (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 3, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (tester) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
          Center(
            child: SizedBox(width: squeezed.width, height: squeezed.height, child: child),
          ),
        );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(inSqueezedBox(const LoadingState(label: 'Loading')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(title: 'No matches', body: 'Try a shorter search.'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description: 'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}
```

### `lib/features/recurring/providers/due_bills_providers.dart`

```dart
/// The recurring bills a payment can settle (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';

/// Outflow templates with an occurrence outstanding today, soonest first.
///
/// **`watchDue()` was built in Phase 3A and used nowhere until now.** It already excludes paused and
/// ended templates and picks each one's soonest outstanding occurrence, which is exactly the read the
/// bill form needs — reimplementing that filter over `watchAllTemplates` would have been a second
/// definition of "due" to keep in step.
final dueBillsProvider = StreamProvider.autoDispose<List<RecurringDue>>(
  (ref) => ref.watch(recurringRepositoryProvider).watchDue().map(
        (all) => [
          for (final due in all)
            if (due.template.direction == RecurringDirection.outflow &&
                due.occurrence != null)
              due,
        ]..sort(
            (a, b) => a.occurrence!.dueDateKey.compareTo(b.occurrence!.dueDateKey),
          ),
      ),
);
```


### `lib/features/recurring/providers/template_draft_provider.dart`

```dart
/// The one-shot channel a module uses to hand the template builder a starting point.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/money/money.dart';

/// A template another module has prepared for the user to finish.
class TemplateDraft {
  /// Creates a draft.
  const TemplateDraft({required this.name, this.amount});

  /// What to call it — a transaction line's description, usually.
  final String name;

  /// What it cost this time, offered as the usual amount.
  final Money? amount;
}

/// A draft waiting to be picked up by the next new-template builder.
///
/// **Set immediately before pushing the builder, consumed by its first load, then cleared.** A line
/// marked "Make it recurring" carries a name and an amount but no interval and no anchor — a receipt
/// cannot know how often something repeats, and inventing monthly-on-the-1st would create an
/// obligation nobody agreed to. So the line hands over what it knows and the user supplies the rest.
///
/// `take()` makes the one-shot explicit rather than leaving a stale draft to ambush the next blank
/// builder — the same reason `transactionDraftProvider` works this way.
final templateDraftProvider =
    NotifierProvider<TemplateDraftNotifier, TemplateDraft?>(TemplateDraftNotifier.new);

/// Holds at most one pending draft.
class TemplateDraftNotifier extends Notifier<TemplateDraft?> {
  @override
  TemplateDraft? build() => null;

  /// Offers a draft to the next builder that opens.
  void offer(TemplateDraft draft) => state = draft;

  /// Returns the pending draft and clears it, so it is never applied twice.
  TemplateDraft? take() {
    final draft = state;
    state = null;
    return draft;
  }
}
```


### `lib/features/recurring/providers/bill_account_providers.dart`

```dart
/// Resolving which account a bill payment comes from, without asking (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/account.dart';

/// Accounts a payment may come from.
final billAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The app-wide default account, if the user has set one.
final defaultAccountIdProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readDefaultAccountId(),
);

/// The account a bill payment should use when the user has not chosen one.
///
/// **Three fallbacks, in order, none of which asks:** the template's own `defaultAccountId`, then the
/// app-wide default from settings, then the only selectable account if there is exactly one. Recording
/// a bill should be one tap, and every one of these is information the user has already given.
///
/// It stops at null rather than guessing between two accounts. A withdrawal attributed to the wrong
/// account is worse than one that asked, because nothing on screen would ever reveal it — whereas the
/// question is answered once and remembered on the template.
final resolvedBillAccountProvider =
    Provider.autoDispose.family<String?, String?>((ref, templateDefault) {
  if (templateDefault != null) return templateDefault;
  final appDefault = ref.watch(defaultAccountIdProvider).valueOrNull;
  if (appDefault != null) return appDefault;
  final accounts = ref.watch(billAccountsProvider).valueOrNull ?? const <Account>[];
  return accounts.length == 1 ? accounts.single.id : null;
});
```


### `test/features/recurring/due_dates_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/services/recurring_engine.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';

/// The due-date arithmetic, and the builder rules that feed it.
///
/// These are the cases a user notices and cannot debug: a bill that walks backwards through February,
/// an anchor that stops matching the start date, a first occurrence that never appears.
void main() {
  const engine = RecurringEngine();

  RecurringTemplate template({
    RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    int intervalCount = 1,
    int? anchorDayOfMonth = 31,
    DateKey start = const DateKey(20260131),
    DateKey? nextDue,
    DateKey? end,
  }) =>
      RecurringTemplate(
        id: 'tpl-1',
        name: 'Rent',
        normalizedName: 'rent',
        kind: RecurringKind.rent,
        direction: RecurringDirection.outflow,
        defaultAmount: const Money(120000, 'INR'),
        intervalUnit: unit,
        intervalCount: intervalCount,
        startDateKey: start,
        nextDueDateKey: nextDue ?? start,
        isPaused: false,
        autoRemind: true,
        remindDaysBefore: 3,
        anchorDayOfMonth: anchorDayOfMonth,
        endDateKey: end,
      );

  group('the anchor clamp', () {
    test('a 31st anchor shortens for February and returns in March', () {
      final t = template();
      final feb = engine.nextDue(from: const DateKey(20260131), template: t);
      final mar = engine.nextDue(from: feb, template: t);
      final apr = engine.nextDue(from: mar, template: t);
      expect(feb, const DateKey(20260228));
      // The whole point of storing the anchor rather than advancing it (anomaly A13): March returns to
      // the 31st instead of inheriting February's 28 for the rest of the template's life.
      expect(mar, const DateKey(20260331));
      expect(apr, const DateKey(20260430));
    });

    test('it never walks backwards across a whole year', () {
      final t = template();
      var cursor = const DateKey(20260131);
      final days = <int>[];
      for (var i = 0; i < 12; i++) {
        cursor = engine.nextDue(from: cursor, template: t);
        days.add(cursor.day);
      }
      // Every long month is back on the 31st. A carried-forward clamp would show 28 from February on.
      expect(days.where((d) => d == 31).length, greaterThanOrEqualTo(5));
      expect(days.contains(28), isTrue);
    });

    test('February is 29 in a leap year and 28 otherwise', () {
      expect(engine.clampDayOfMonth(31, 2028, 2), 29);
      expect(engine.clampDayOfMonth(31, 2026, 2), 28);
      expect(engine.clampDayOfMonth(30, 2026, 4), 30);
      expect(engine.clampDayOfMonth(15, 2026, 2), 15);
    });

    test('a day and week interval never clamps', () {
      final weekly = template(unit: RecurringIntervalUnit.week, anchorDayOfMonth: null);
      expect(
        engine.nextDue(from: const DateKey(20260129), template: weekly),
        const DateKey(20260205),
      );
      final daily = template(unit: RecurringIntervalUnit.day, intervalCount: 3, anchorDayOfMonth: null);
      expect(
        engine.nextDue(from: const DateKey(20260227), template: daily),
        const DateKey(20260302),
      );
    });

    test('a yearly interval keeps its month and clamps its day', () {
      final yearly = template(unit: RecurringIntervalUnit.year, anchorDayOfMonth: 29, start: const DateKey(20280229));
      // 29 February 2028 exists; 2029 does not have one.
      expect(
        engine.nextDue(from: const DateKey(20280229), template: yearly),
        const DateKey(20290228),
      );
    });
  });

  group('the builder', () {
    TemplateBuilderState state({
      DateKey start = const DateKey(20260301),
      int? anchor,
      RecurringIntervalUnit unit = RecurringIntervalUnit.month,
    }) =>
        TemplateBuilderState(
          currencyCode: 'INR',
          startDateKey: start,
          name: 'Rent',
          amount: const Money(120000, 'INR'),
          intervalUnit: unit,
          anchorDayOfMonth: anchor ?? start.day,
        );

    test('the anchor follows the start date while it still matches it', () {
      // The bug this pins: the builder seeds the anchor from today, so moving the start date left the
      // anchor on an unrelated day and the second occurrence landed nowhere near the first.
      final before = state(start: const DateKey(20260301));
      expect(before.anchorDayOfMonth, 1);
      final follows = before.anchorDayOfMonth == before.startDateKey.day;
      expect(follows, isTrue);
    });

    test('an anchor the user chose is not overwritten by a start-date change', () {
      final chosen = state(start: const DateKey(20260301), anchor: 15);
      final follows = chosen.anchorDayOfMonth == chosen.startDateKey.day;
      // 15 is not 1, so the anchor was deliberate and must survive.
      expect(follows, isFalse);
    });

    test('a monthly template is incomplete without a day anchor', () {
      const bare = TemplateBuilderState(
        currencyCode: 'INR',
        startDateKey: DateKey(20260301),
        name: 'Rent',
        amount: Money(120000, 'INR'),
      );
      expect(bare.needsDayAnchor, isTrue);
      expect(bare.isComplete, isFalse);
      expect(bare.copyWith(anchorDayOfMonth: 1).isComplete, isTrue);
    });

    test('a weekly template needs no anchor to be complete', () {
      const weekly = TemplateBuilderState(
        currencyCode: 'INR',
        startDateKey: DateKey(20260301),
        name: 'Gym',
        amount: Money(50000, 'INR'),
        intervalUnit: RecurringIntervalUnit.week,
      );
      expect(weekly.needsDayAnchor, isFalse);
      expect(weekly.isComplete, isTrue);
    });

    test('a new template is first due on its start date, not one interval later', () {
      final t = state(start: const DateKey(20260315), anchor: 15).toTemplate(
        newId: 'tpl-9',
        normalizedName: 'rent',
        nextDue: const DateKey(20260315),
      );
      // Materialisation walks from `nextDueDateKey` inclusive, so seeding it with the start date is
      // what makes the first occurrence appear on the day the user chose.
      expect(t.nextDueDateKey, t.startDateKey);
    });
  });

  group('an end date', () {
    test('stops the schedule rather than being ignored', () {
      final t = template(end: const DateKey(20260315));
      final feb = engine.nextDue(from: const DateKey(20260131), template: t);
      final mar = engine.nextDue(from: feb, template: t);
      expect(feb.isAfter(t.endDateKey!), isFalse);
      // March 31 is past the 15 March end, so a materialiser walking this must stop before it.
      expect(mar.isAfter(t.endDateKey!), isTrue);
    });
  });
}
```


---

## COVERAGE — ARCH_5 §7 rows closed by Phase 6D

### §7.1 By table

| Row | Create | Read | Edit | Retire |
|---|---|---|---|---|
| `recurring_templates` | template builder | list grouped by direction · occurrence history header | template builder | `setTemplatePaused` for suspend; `deleteTemplate` for retire, which leaves every transaction its payments created (Law L6) |
| `recurring_occurrences` | **lazy materialisation only** — `materialiseUpTo(clock.today())` on list mount, every row `due` and never paid (anomaly A14) | occurrence history timeline | pay sheet · skip | undo, which returns the occurrence to due *then* deletes the transaction |

### §7.2 Columns most likely to be stranded

| Column | Where a user sees it |
|---|---|
| `anchorDayOfMonth` | A field in the builder, and — the point of the phase — **the live three-date preview**, which shows Jan 31 → Feb 28 → Mar 31 with February marked "Shortened to fit the month". Stored once and clamped at render, never advanced (anomaly A13) |
| `anchorMonth` / `anchorWeekday` | **Deferred, see §7.3.** The interval units this phase exposes never read them |
| `direction = inflow` | Its own "Coming in" group, an inward arrow, a success-toned glyph and an unsigned amount. Choosing Salary sets it, so an inflow cannot be created by accident as a negative bill |
| `paidAmountMinor` | The pay sheet's editable actual, pre-filled from the default; the history badges any occurrence where the two differ, and says nothing where they agree |
| `nextDueDateKey` | "Next" plus a `DateText` on every row |
| `isPaused` | A `Paused` chip, a Resume action, and no pay button while suspended |
| `remindDaysBefore` / `autoRemind` | Builder fields; consumed by Phase 8B |

### §7.3 Deferred — with the contract each waits on

| Item | Why | Owner |
|---|---|---|
| `anchorMonth`, `anchorWeekday` | On the entity and validated by `RecurringRepositoryImpl`, but no interval unit this phase offers consults them: `RecurringEngine.nextDue` anchors monthly and yearly intervals to `anchorDayOfMonth` alone. Exposing a weekday picker that changes nothing would be worse than omitting it. Needs an engine change first, not a UI one. | **4C addendum, then 6D follow-up** |
| `watchDue()` / `RecurringDue` | Built in 3A, unused. It is the cross-template "what is due soon" read, which belongs to 6F's dashboard rather than to a per-template list. | **6F** |
| `watchTemplatesForAsset` | The asset ↔ recurring link. 6E owns assets and should own the surface that shows a service contract against its machine. | **6E** |
| `linkedAssetId` | Same — set from the asset side, so the builder does not offer a picker for something 6E will own. | **6E** |
| `paymentMethodId` on the pay sheet | Carried on the state and passed to `payOccurrence`, but no picker: `PaymentMethodRepository` is read by 6A's editor and wiring a second picker here before 8A settles default-payment-method behaviour would fork it. | **8A** |
