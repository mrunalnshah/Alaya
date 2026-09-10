# PHASE 6E — The Service Manager module UI

`AssetRepository`, `ServiceRecordRepository` and `RecurringRepository.watchTemplatesForAsset` already
carry everything this phase needs — `dispose`, `undispose`, `lifetimeCostByCurrency`, and a
`save(record, {alsoRecordAsExpense, accountId})` that owns the cross-aggregate write. Nothing is
reimplemented here.

`app_en.arb`, `routes.dart` and `app_router.dart` supersede their earlier versions; every other file is
new.

This phase adds one package, for the call action on `assets.primaryContactPhone`. There is no
`launchUrl` anywhere in the tree today.

```
flutter pub add url_launcher
```

```
flutter gen-l10n
flutter analyze
flutter test
```

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

### `lib/features/service/state/asset_editor_state.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';

/// Why an asset save was refused, when it was refused for a reason worth naming.
enum AssetSaveIssue {
  /// The name was blank.
  nameMissing,

  /// The warranty ends before it starts.
  warrantyBackwards,

  /// The write failed for a reason the repository named.
  rejected,
}

/// Everything the asset editor is holding (ARCH_5 §3 archetype B).
///
/// **`type = serviceProvider` is a first-class case, not an afterthought.** A house maid is an asset
/// with a linked recurring template and a `service_records` row per payment — the same three tables a
/// television uses. Every field below is optional except the name precisely so a person can be
/// recorded without inventing a serial number for them.
class AssetEditorState {
  /// Creates the editor's state.
  const AssetEditorState({
    required this.currencyCode,
    this.id,
    this.name = '',
    this.type = AssetType.appliance,
    this.status = AssetStatus.active,
    this.brand,
    this.modelNo,
    this.serialNo,
    this.purchaseDateKey,
    this.purchasePrice,
    this.warrantyStartDateKey,
    this.warrantyEndDateKey,
    this.warrantyProvider,
    this.serviceIntervalDays,
    this.nextServiceDueDateKey,
    this.contactName,
    this.contactPhone,
    this.location,
    this.notes,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
    this.nextServiceChosen = false,
  });

  /// The asset being edited, or null for a new one.
  final String? id;

  /// What it is. The one required field (U11).
  final String name;

  /// Which kind, which decides the wording everywhere else in the module.
  final AssetType type;

  /// Active, being repaired, or disposed. Disposal goes through the sheet, never this field.
  final AssetStatus status;

  /// The currency prices are entered in.
  final String currencyCode;

  /// Who made it.
  final String? brand;

  /// Which model.
  final String? modelNo;

  /// Its serial number.
  final String? serialNo;

  /// When it was bought.
  final DateKey? purchaseDateKey;

  /// What it cost. Kept forever, including after disposal (anomaly A30).
  final Money? purchasePrice;

  /// When the warranty starts.
  final DateKey? warrantyStartDateKey;

  /// When the warranty ends.
  final DateKey? warrantyEndDateKey;

  /// Who honours the warranty.
  final String? warrantyProvider;

  /// How many days between services.
  final int? serviceIntervalDays;

  /// When the next service is due.
  final DateKey? nextServiceDueDateKey;

  /// Who to call about it.
  final String? contactName;

  /// The number to call.
  final String? contactPhone;

  /// Where it is kept.
  final String? location;

  /// Free notes.
  final String? notes;

  /// Whether a save is in flight.
  final bool submitting;

  /// Why the last save was refused, or null if it was not.
  final AssetSaveIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Whether the user picked the next service date themselves.
  ///
  /// **Typing "30" fires twice: once with 3, once with 30.** The due date was seeded with `?? `, so the
  /// first keystroke set it to three days out and every keystroke after that found it non-null and left
  /// it alone. It has to be recomputed on every change to the interval — and this flag is what stops
  /// that recomputation trampling a date the user chose deliberately.
  final bool nextServiceChosen;

  /// Whether this is editing an existing asset.
  bool get isEditing => id != null;

  /// Whether this asset is a person rather than a thing.
  ///
  /// Drives the wording, not the storage: the fields a television needs are simply left empty.
  bool get isPerson => type == AssetType.serviceProvider;

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ///
  /// `issue` and `rejection` survive an unrelated `copyWith` — a bare assignment lets the
  /// `submitting: false` in a `finally` erase the reason before the screen reads it (ARCH_4 R31).
  AssetEditorState copyWith({
    String? id,
    String? name,
    AssetType? type,
    AssetStatus? status,
    String? brand,
    String? modelNo,
    String? serialNo,
    DateKey? purchaseDateKey,
    Money? purchasePrice,
    bool clearPurchasePrice = false,
    DateKey? warrantyStartDateKey,
    DateKey? warrantyEndDateKey,
    bool clearWarrantyEnd = false,
    String? warrantyProvider,
    int? serviceIntervalDays,
    bool clearInterval = false,
    DateKey? nextServiceDueDateKey,
    bool clearNextService = false,
    String? contactName,
    String? contactPhone,
    String? location,
    String? notes,
    bool? submitting,
    AssetSaveIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
    bool? nextServiceChosen,
  }) =>
      AssetEditorState(
        currencyCode: currencyCode,
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        status: status ?? this.status,
        brand: brand ?? this.brand,
        modelNo: modelNo ?? this.modelNo,
        serialNo: serialNo ?? this.serialNo,
        purchaseDateKey: purchaseDateKey ?? this.purchaseDateKey,
        purchasePrice:
            clearPurchasePrice ? null : (purchasePrice ?? this.purchasePrice),
        warrantyStartDateKey: warrantyStartDateKey ?? this.warrantyStartDateKey,
        warrantyEndDateKey:
            clearWarrantyEnd ? null : (warrantyEndDateKey ?? this.warrantyEndDateKey),
        warrantyProvider: warrantyProvider ?? this.warrantyProvider,
        serviceIntervalDays:
            clearInterval ? null : (serviceIntervalDays ?? this.serviceIntervalDays),
        nextServiceDueDateKey: clearNextService
            ? null
            : (nextServiceDueDateKey ?? this.nextServiceDueDateKey),
        contactName: contactName ?? this.contactName,
        contactPhone: contactPhone ?? this.contactPhone,
        location: location ?? this.location,
        notes: notes ?? this.notes,
        submitting: submitting ?? this.submitting,
        issue: clearIssue ? null : (issue ?? this.issue),
        rejection: clearIssue ? null : (rejection ?? this.rejection),
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? true,
        nextServiceChosen: nextServiceChosen ?? this.nextServiceChosen,
      );

  /// Builds the entity this state describes.
  ///
  /// Disposal fields are never written here. An asset is disposed of through
  /// `AssetRepository.dispose`, which records the reason alongside the status change — saving the
  /// editor must not be able to quietly retire something (anomaly A30).
  Asset toAsset({required String newId, required String normalizedName, Asset? existing}) => Asset(
        id: id ?? newId,
        name: name.trim(),
        normalizedName: normalizedName,
        type: type,
        status: status,
        brand: brand,
        modelNo: modelNo,
        serialNo: serialNo,
        purchaseDateKey: purchaseDateKey,
        purchasePrice: purchasePrice,
        sourceTransactionLineId: existing?.sourceTransactionLineId,
        warrantyStartDateKey: warrantyStartDateKey,
        warrantyEndDateKey: warrantyEndDateKey,
        warrantyProvider: warrantyProvider,
        warrantyNote: existing?.warrantyNote,
        serviceIntervalDays: serviceIntervalDays,
        nextServiceDueDateKey: nextServiceDueDateKey,
        primaryContactName: contactName,
        primaryContactPhone: contactPhone,
        location: location,
        linkedRecurringTemplateId: existing?.linkedRecurringTemplateId,
        disposedAtDateKey: existing?.disposedAtDateKey,
        disposalReason: existing?.disposalReason,
        disposalNote: existing?.disposalNote,
        disposalAmount: existing?.disposalAmount,
        notes: notes,
      );

  /// Loads an existing asset into an editor state.
  static AssetEditorState fromAsset(Asset asset, String currencyCode) => AssetEditorState(
        currencyCode: asset.purchasePrice?.currencyCode ?? currencyCode,
        id: asset.id,
        name: asset.name,
        type: asset.type,
        status: asset.status,
        brand: asset.brand,
        modelNo: asset.modelNo,
        serialNo: asset.serialNo,
        purchaseDateKey: asset.purchaseDateKey,
        purchasePrice: asset.purchasePrice,
        warrantyStartDateKey: asset.warrantyStartDateKey,
        warrantyEndDateKey: asset.warrantyEndDateKey,
        warrantyProvider: asset.warrantyProvider,
        serviceIntervalDays: asset.serviceIntervalDays,
        nextServiceDueDateKey: asset.nextServiceDueDateKey,
        // A saved date is one the user already lives with; recomputing it from the interval on the first
        // edit would silently move a service they may have booked.
        nextServiceChosen: asset.nextServiceDueDateKey != null,
        contactName: asset.primaryContactName,
        contactPhone: asset.primaryContactPhone,
        location: asset.location,
        notes: asset.notes,
      );
}
```

### `lib/features/service/state/service_editor_state.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// Why a service record was refused, when it was refused for a reason worth naming.
enum ServiceSaveIssue {
  /// The expense toggle is on with no cost to record.
  costMissingForExpense,

  /// The expense toggle is on with no account to record it against.
  accountMissingForExpense,

  /// The write failed for a reason the repository named.
  rejected,
}

/// Everything the service editor is holding (ARCH_5 §3 archetype B).
///
/// **`type = salaryPaid` is what makes a person work in this table.** A maid's monthly payment is a
/// service record like any other — same asset, same cost column, same optional expense — so the
/// salary history on the detail screen is simply this table filtered by type. There is no second
/// system to keep in step.
class ServiceEditorState {
  /// Creates the editor's state.
  const ServiceEditorState({
    required this.assetId,
    required this.currencyCode,
    required this.serviceDateKey,
    this.id,
    this.type = ServiceRecordType.service,
    this.providerName,
    this.providerPhone,
    this.cost,
    this.nextDueDateKey,
    this.notes,
    this.alsoRecordAsExpense = false,
    this.accountId,
    this.paymentMethodId,
    this.submitting = false,
    this.issue,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// The record being edited, or null for a new one.
  final String? id;

  /// Which asset it belongs to.
  final String assetId;

  /// The currency costs are entered in.
  final String currencyCode;

  /// What happened.
  final ServiceRecordType type;

  /// When.
  final DateKey serviceDateKey;

  /// Who did it, or who was paid.
  final String? providerName;

  /// Their number, so the detail screen can offer a call.
  final String? providerPhone;

  /// What it cost.
  final Money? cost;

  /// When the next one is due, which also advances the asset's own due date.
  final DateKey? nextDueDateKey;

  /// Free notes.
  final String? notes;

  /// Whether the repository should also write a withdrawal for [cost].
  ///
  /// **The repository owns that write, not this editor.** `ServiceRecordRepository.save` takes the flag
  /// and does both, which is the only way the two stay consistent — the sequence is not atomic across
  /// aggregates, so it is ordered and idempotent instead (ARCH_4 R21).
  final bool alsoRecordAsExpense;

  /// Which account the expense comes from, required only when the toggle is on.
  final String? accountId;

  /// How it was paid, if the user cares to say.
  ///
  /// Always optional. It travels to the expense and never onto the record: how a service was settled is
  /// a property of the payment, not of the work.
  final String? paymentMethodId;

  /// Whether a save is in flight.
  final bool submitting;

  /// Why the last save was refused, or null if it was not.
  final ServiceSaveIssue? issue;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the offending field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Whether this is editing an existing record.
  bool get isEditing => id != null;

  /// Whether this record is a salary payment rather than work done on a thing.
  bool get isSalary => type == ServiceRecordType.salaryPaid;

  /// Whether the expense toggle has everything it needs.
  bool get expenseIsSatisfiable =>
      !alsoRecordAsExpense || ((cost?.isPositive ?? false) && accountId != null);

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  ServiceEditorState copyWith({
    String? id,
    ServiceRecordType? type,
    DateKey? serviceDateKey,
    String? providerName,
    String? providerPhone,
    Money? cost,
    bool clearCost = false,
    DateKey? nextDueDateKey,
    bool clearNextDue = false,
    String? notes,
    bool? alsoRecordAsExpense,
    String? accountId,
    String? paymentMethodId,
    bool? submitting,
    ServiceSaveIssue? issue,
    String? rejection,
    bool clearIssue = false,
    int? shakeTrigger,
    bool? dirty,
  }) =>
      ServiceEditorState(
        assetId: assetId,
        currencyCode: currencyCode,
        id: id ?? this.id,
        type: type ?? this.type,
        serviceDateKey: serviceDateKey ?? this.serviceDateKey,
        providerName: providerName ?? this.providerName,
        providerPhone: providerPhone ?? this.providerPhone,
        cost: clearCost ? null : (cost ?? this.cost),
        nextDueDateKey: clearNextDue ? null : (nextDueDateKey ?? this.nextDueDateKey),
        notes: notes ?? this.notes,
        alsoRecordAsExpense: alsoRecordAsExpense ?? this.alsoRecordAsExpense,
        accountId: accountId ?? this.accountId,
        paymentMethodId: paymentMethodId ?? this.paymentMethodId,
        submitting: submitting ?? this.submitting,
        issue: clearIssue ? null : (issue ?? this.issue),
        rejection: clearIssue ? null : (rejection ?? this.rejection),
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? true,
      );

  /// Builds the entity this state describes.
  ServiceRecord toRecord({required String newId, ServiceRecord? existing}) => ServiceRecord(
        id: id ?? newId,
        assetId: assetId,
        serviceDateKey: serviceDateKey,
        type: type,
        providerName: providerName,
        providerPhone: providerPhone,
        cost: cost,
        // Preserved rather than rewritten: the repository owns this link, and an editor that cleared it
        // would orphan a transaction that genuinely happened (Law L6).
        linkedTransactionId: existing?.linkedTransactionId,
        nextDueDateKey: nextDueDateKey,
        notes: notes,
      );

  /// Loads an existing record into an editor state.
  static ServiceEditorState fromRecord(ServiceRecord record, String currencyCode) =>
      ServiceEditorState(
        assetId: record.assetId,
        currencyCode: record.cost?.currencyCode ?? currencyCode,
        id: record.id,
        type: record.type,
        serviceDateKey: record.serviceDateKey,
        providerName: record.providerName,
        providerPhone: record.providerPhone,
        cost: record.cost,
        nextDueDateKey: record.nextDueDateKey,
        notes: record.notes,
        // An existing record already wrote its expense or did not. Re-offering the toggle on edit would
        // let one service produce two withdrawals — the same shape as ARCH_4 R35.
        alsoRecordAsExpense: false,
      );
}
```

### `lib/features/service/state/dispose_state.dart`

```dart
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';

/// What the dispose sheet is holding (ARCH_5 §3 archetype A).
///
/// **Disposal is a status change plus a reason, never a delete.** The ₹45,000 spent on a television
/// stays in every total after it goes to the tip, because the money left the house whether or not the
/// object is still in it (anomaly A30, ARCH_3 §4.1). That is why there is a reason picker here and no
/// delete anywhere in the module.
class DisposeState {
  /// Creates the sheet's state.
  const DisposeState({
    required this.assetId,
    required this.currencyCode,
    required this.dateKey,
    this.reason,
    this.amount,
    this.note,
    this.submitting = false,
    this.reasonMissing = false,
    this.rejection,
    this.shakeTrigger = 0,
    this.dirty = false,
  });

  /// Which asset is being retired.
  final String assetId;

  /// The currency a recovered amount is entered in.
  final String currencyCode;

  /// Why. The one required field (U11).
  final AssetDisposalReason? reason;

  /// When it happened.
  final DateKey dateKey;

  /// What the disposal recovered, if anything.
  ///
  /// Optional because most disposals recover nothing — a broken kettle is thrown away, not sold — and
  /// requiring a zero would make the common case extra typing.
  final Money? amount;

  /// Anything worth saying about it.
  final String? note;

  /// Whether a commit is in flight.
  final bool submitting;

  /// Whether commit was pressed with no reason chosen.
  final bool reasonMissing;

  /// The repository's own message when it rejected the write.
  final String? rejection;

  /// Incremented to shake the reason picker.
  final int shakeTrigger;

  /// Whether anything optional was touched, for the dismiss guard (Law U10).
  final bool dirty;

  /// Returns a copy with the supplied changes.
  DisposeState copyWith({
    AssetDisposalReason? reason,
    DateKey? dateKey,
    Money? amount,
    bool clearAmount = false,
    String? note,
    bool? submitting,
    bool? reasonMissing,
    String? rejection,
    bool clearRejection = false,
    int? shakeTrigger,
    bool? dirty,
  }) =>
      DisposeState(
        assetId: assetId,
        currencyCode: currencyCode,
        reason: reason ?? this.reason,
        dateKey: dateKey ?? this.dateKey,
        amount: clearAmount ? null : (amount ?? this.amount),
        note: note ?? this.note,
        submitting: submitting ?? this.submitting,
        reasonMissing: reasonMissing ?? this.reasonMissing,
        rejection: clearRejection ? null : (rejection ?? this.rejection),
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? this.dirty,
      );
}
```

### `lib/features/service/providers/asset_list_providers.dart`

```dart
/// View-model state for the asset list (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/asset.dart';

/// What the asset list is currently showing.
class AssetFilter {
  /// Creates a filter.
  const AssetFilter({this.includeDisposed = false, this.types = const <AssetType>{}, this.query = ''});

  /// Whether disposed assets are shown alongside the rest.
  ///
  /// **Off by default, never unavailable.** An asset is never deleted (anomaly A30), so without this
  /// switch every television ever thrown away would crowd the list of things you actually own — and
  /// without the list ever showing them, the money spent on them would look like it had vanished.
  final bool includeDisposed;

  /// Which kinds are shown; empty means all.
  final Set<AssetType> types;

  /// The search term, already trimmed.
  final String query;

  /// Whether anything narrows the full list.
  bool get isNarrowed => includeDisposed || types.isNotEmpty;

  /// Whether a search term is active, which changes which empty state is right.
  bool get isSearching => query.isNotEmpty;

  /// Returns a copy with the supplied changes.
  AssetFilter copyWith({bool? includeDisposed, Set<AssetType>? types, String? query}) =>
      AssetFilter(
        includeDisposed: includeDisposed ?? this.includeDisposed,
        types: types ?? this.types,
        query: query ?? this.query,
      );
}

/// One kind's worth of assets.
class AssetGroup {
  /// Creates a group.
  const AssetGroup({required this.type, required this.assets});

  /// Which kind this group collects.
  final AssetType type;

  /// The assets under it, sorted by name.
  final List<Asset> assets;
}

/// The list's current filter.
final assetFilterProvider =
    NotifierProvider<AssetFilterNotifier, AssetFilter>(AssetFilterNotifier.new);

/// Drives the search field and the filter chips.
class AssetFilterNotifier extends Notifier<AssetFilter> {
  @override
  AssetFilter build() => const AssetFilter();

  /// Sets the search term.
  void setQuery(String query) => state = state.copyWith(query: query.trim());

  /// Brings disposed assets into the list, or takes them out again.
  void toggleDisposed() => state = state.copyWith(includeDisposed: !state.includeDisposed);

  /// Adds or removes a kind.
  void toggleType(AssetType type) {
    final next = {...state.types};
    if (next.contains(type)) {
      next.remove(type);
    } else {
      next.add(type);
    }
    state = state.copyWith(types: next);
  }

  /// Clears everything back to the things you own.
  void clear() => state = AssetFilter(query: state.query);
}

/// The assets still in use.
final assetsInUseProvider = StreamProvider<List<Asset>>(
  (ref) => ref.watch(assetRepositoryProvider).watchInUse(),
);

/// The assets that have been disposed of.
///
/// Watched only when the filter asks for them, so an ordinary list does not carry the weight of every
/// object the household has ever retired.
final disposedAssetsProvider = StreamProvider<List<Asset>>(
  (ref) => ref.watch(assetRepositoryProvider).watchDisposed(),
);

/// The list, filtered, searched and grouped by kind.
final assetGroupsProvider = Provider<AsyncValue<List<AssetGroup>>>((ref) {
  final inUse = ref.watch(assetsInUseProvider);
  final filter = ref.watch(assetFilterProvider);
  if (inUse.hasError) return AsyncValue.error(inUse.error!, inUse.stackTrace!);
  final active = inUse.valueOrNull;
  if (active == null) return const AsyncValue.loading();

  var all = [...active];
  if (filter.includeDisposed) {
    final disposed = ref.watch(disposedAssetsProvider);
    if (disposed.hasError) {
      return AsyncValue.error(disposed.error!, disposed.stackTrace!);
    }
    final retired = disposed.valueOrNull;
    if (retired == null) return const AsyncValue.loading();
    all = [...all, ...retired];
  }

  final term = filter.query.toLowerCase();
  final visible = [
    for (final asset in all)
      if (_admits(asset, filter, term)) asset,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final buckets = <AssetType, List<Asset>>{};
  for (final asset in visible) {
    buckets.putIfAbsent(asset.type, () => <Asset>[]).add(asset);
  }
  return AsyncValue.data([
    for (final type in AssetType.values)
      if (buckets[type] != null) AssetGroup(type: type, assets: buckets[type]!),
  ]);
});

/// How many assets are overdue a service, for the header count.
///
/// Derived from the clock through `Asset.isServiceOverdue`, never a stored flag (ARCH_2 §12.2): a flag
/// would be wrong the moment midnight passed with the app closed.
final serviceDueCountProvider = Provider<int>((ref) {
  final active = ref.watch(assetsInUseProvider).valueOrNull ?? const <Asset>[];
  final today = ref.watch(clockProvider).today();
  return active.where((asset) => asset.isServiceOverdue(today)).length;
});

bool _admits(Asset asset, AssetFilter filter, String term) {
  if (filter.types.isNotEmpty && !filter.types.contains(asset.type)) return false;
  if (term.isEmpty) return true;
  return asset.normalizedName.contains(term) || asset.name.toLowerCase().contains(term);
}
```

### `lib/features/service/providers/asset_detail_providers.dart`

```dart
/// View-model state for one asset (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';

/// The asset, or null when it does not exist.
///
/// **Derived from the two list streams, not a one-shot `byId`.** A `FutureProvider` reads once and then
/// serves its cache, and the detail screen stays mounted beneath the editor — so it would keep showing
/// the pre-edit asset until the app restarted. Both streams re-emit on every write, and a disposed
/// asset must stay reachable by id even though it has left `watchInUse` (anomaly A30).
final assetByIdProvider = Provider.autoDispose.family<AsyncValue<Asset?>, String>((ref, id) {
  final inUse = ref.watch(assetsInUseProvider);
  final disposed = ref.watch(disposedAssetsProvider);
  if (inUse.hasError) return AsyncValue.error(inUse.error!, inUse.stackTrace!);
  if (disposed.hasError) {
    return AsyncValue.error(disposed.error!, disposed.stackTrace!);
  }
  final active = inUse.valueOrNull;
  final retired = disposed.valueOrNull;
  if (active == null || retired == null) return const AsyncValue.loading();
  for (final asset in [...active, ...retired]) {
    if (asset.id == id) return AsyncValue.data(asset);
  }
  return const AsyncValue.data(null);
});

/// Every service record against one asset, newest first.
final serviceRecordsProvider =
    StreamProvider.autoDispose.family<List<ServiceRecord>, String>(
  (ref, assetId) => ref.watch(serviceRecordRepositoryProvider).watchForAsset(assetId),
);

/// What has been spent servicing one asset, per currency.
///
/// A map rather than a single figure because a machine serviced abroad genuinely has two lifetime
/// totals, and summing them would invent an exchange rate the user never agreed to (Law L1).
final lifetimeServiceCostProvider =
    FutureProvider.autoDispose.family<Map<String, Money>, String>((ref, assetId) {
  // Watched so recording a service updates the figure rather than leaving it stale until a restart.
  ref.watch(serviceRecordsProvider(assetId));
  return ref.watch(serviceRecordRepositoryProvider).lifetimeCostByCurrency(assetId);
});

/// The recurring templates that pay this asset.
///
/// `watchTemplatesForAsset` was built in Phase 3A and deferred to this phase by 6D's coverage table:
/// it is what makes a maid's monthly salary visible from her own record rather than only from the
/// recurring list.
final assetTemplatesProvider =
    StreamProvider.autoDispose.family<List<RecurringTemplate>, String>(
  (ref, assetId) => ref.watch(recurringRepositoryProvider).watchTemplatesForAsset(assetId),
);

/// Writes the asset detail screen performs.
final assetActionsProvider = Provider<AssetActions>(AssetActions.new);

/// Changes an asset's status, and brings it back.
class AssetActions {
  /// Creates the actions.
  AssetActions(this._ref);

  final Ref _ref;

  /// Reverses a disposal, returning the failure's own message or null on success.
  ///
  /// The counterpart to disposal existing at all: a thing sold by mistake is put back, and nothing was
  /// destroyed in the meantime because disposal never deleted anything.
  Future<String?> undispose(String id) async {
    final result = await _ref.read(assetRepositoryProvider).undispose(id);
    return result.failureOrNull?.message;
  }

  /// Marks an asset as being repaired, or active again.
  Future<String?> setStatus({required String id, required AssetStatus status}) async {
    final result =
        await _ref.read(assetRepositoryProvider).setStatus(id: id, status: status);
    return result.failureOrNull?.message;
  }

  /// Deletes one service record.
  ///
  /// The record, not the asset. There is no path in this module that deletes an asset.
  Future<String?> deleteRecord(String recordId) async {
    final result = await _ref.read(serviceRecordRepositoryProvider).delete(recordId);
    return result.failureOrNull?.message;
  }
}
```
### `lib/features/service/providers/asset_editor_providers.dart`

```dart
/// View-model state for the asset editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/features/service/state/asset_editor_state.dart';

/// The home currency, so a price is never denominated in a guess.
final serviceCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR',
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final serviceDecimalDigitsProvider = FutureProvider.autoDispose<int>((ref) async {
  final code = await ref.watch(serviceCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// Whether another asset already carries this name.
///
/// **Derived from the list streams, and only ever a note.** `AssetRepositoryImpl.save` used to refuse a
/// repeated name, which made owning two of anything impossible — five iPhones are five assets, with five
/// warranties and five service histories. But a silent duplicate hides a genuine double entry, so the
/// editor says so and lets the user decide.
///
/// `AssetDao.byNormalizedName` exists and `AssetRepository` does not expose it; deriving from
/// `watchInUse` and `watchDisposed` needs no contract addition and no DAO reach-through (Law U19).
final assetNameClashProvider =
    Provider.autoDispose.family<bool, ({String? id, String name})>((ref, arg) {
  final trimmed = arg.name.trim();
  if (trimmed.isEmpty) return false;
  final normalized = ref.watch(normalizerProvider).normalize(trimmed);
  final inUse = ref.watch(assetsInUseProvider).valueOrNull ?? const <Asset>[];
  final disposed = ref.watch(disposedAssetsProvider).valueOrNull ?? const <Asset>[];
  for (final asset in [...inUse, ...disposed]) {
    if (asset.normalizedName == normalized && asset.id != arg.id) return true;
  }
  return false;
});

/// The editor for one asset, or for a new one when the argument is null.
final assetEditorProvider = NotifierProvider.autoDispose
    .family<AssetEditorNotifier, AsyncValue<AssetEditorState>, String?>(
  AssetEditorNotifier.new,
);

/// Loads, edits and saves one asset.
class AssetEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<AssetEditorState>, String?> {
  @override
  AsyncValue<AssetEditorState> build(String? arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String? id) async {
    try {
      final code =
          await ref.read(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR';
      if (id == null) {
        state = AsyncValue.data(AssetEditorState(currencyCode: code));
        return;
      }
      final asset = await ref.read(assetRepositoryProvider).byId(id);
      if (asset == null) {
        state = AsyncValue.error(StateError('Asset $id not found.'), StackTrace.current);
        return;
      }
      state = AsyncValue.data(AssetEditorState.fromAsset(asset, code));
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// Applies [change], clearing the last rejection unless told to keep it.
  ///
  /// A refused save is worth longer than a 2.5-second snack, so it is also a card in the form — but a card
  /// that survives the edit which fixes it is a stale error the user has to dismiss by hand. Every setter
  /// clears it; only `save` keeps it.
  void _edit(
    AssetEditorState Function(AssetEditorState) change, {
    bool keepIssue = false,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = change(current);
    state = AsyncValue.data(keepIssue ? next : next.copyWith(clearIssue: true));
  }

  /// Sets what it is.
  void setName(String name) => _edit((s) => s.copyWith(name: name, clearIssue: true));

  /// Sets which kind of thing — or person — this is.
  void setType(AssetType type) => _edit((s) => s.copyWith(type: type));

  /// Sets who made it.
  void setBrand(String value) => _edit((s) => s.copyWith(brand: value));

  /// Sets the model number.
  void setModelNo(String value) => _edit((s) => s.copyWith(modelNo: value));

  /// Sets the serial number.
  void setSerialNo(String value) => _edit((s) => s.copyWith(serialNo: value));

  /// Sets when it was bought.
  void setPurchaseDate(DateKey? date) =>
      _edit((s) => date == null ? s : s.copyWith(purchaseDateKey: date));

  /// Sets what it cost.
  void setPurchasePrice(Money? price) => _edit(
        (s) => price == null
            ? s.copyWith(clearPurchasePrice: true)
            : s.copyWith(purchasePrice: price),
      );

  /// Sets when the warranty starts.
  void setWarrantyStart(DateKey? date) =>
      _edit((s) => date == null ? s : s.copyWith(warrantyStartDateKey: date));

  /// Sets when the warranty ends.
  void setWarrantyEnd(DateKey? date) => _edit(
        (s) => date == null
            ? s.copyWith(clearWarrantyEnd: true)
            : s.copyWith(warrantyEndDateKey: date, clearIssue: true),
      );

  /// Sets who honours the warranty.
  void setWarrantyProvider(String value) => _edit((s) => s.copyWith(warrantyProvider: value));

  /// Sets how many days between services, and derives the first due date from it.
  ///
  /// **Recomputed on every change, not seeded once.** A text field fires per keystroke: "30" arrives as
  /// 3 and then as 30, and the old `??` meant the three-day answer stuck. The date is derived from the
  /// interval unless the user has picked one themselves, which `nextServiceChosen` records.
  ///
  /// Deriving rather than requiring both: an interval with no first date never produces a due chip, and
  /// asking for the same information twice is how one of the two ends up wrong.
  void setServiceIntervalDays(int? days) => _edit((s) {
        if (days == null || days < 1) {
          return s.copyWith(clearInterval: true, clearNextService: true);
        }
        final from = s.purchaseDateKey ?? ref.read(clockProvider).today();
        return s.copyWith(
          serviceIntervalDays: days,
          nextServiceDueDateKey:
              s.nextServiceChosen ? s.nextServiceDueDateKey : from.addDays(days),
        );
      });

  /// Sets when the next service is due, and stops the interval deriving it from then on.
  void setNextServiceDue(DateKey? date) => _edit(
        (s) => date == null
            ? s.copyWith(clearNextService: true, nextServiceChosen: false)
            : s.copyWith(nextServiceDueDateKey: date, nextServiceChosen: true),
      );

  /// Sets who to call about it.
  void setContactName(String value) => _edit((s) => s.copyWith(contactName: value));

  /// Sets the number to call.
  void setContactPhone(String value) => _edit((s) => s.copyWith(contactPhone: value));

  /// Sets where it is kept.
  void setLocation(String value) => _edit((s) => s.copyWith(location: value));

  /// Sets the free notes.
  void setNotes(String value) => _edit((s) => s.copyWith(notes: value));

  /// Saves the asset, returning its id on success and null on rejection or failure.
  ///
  /// Every refusal is named before the repository sees it, and a rejection carries the repository's own
  /// message — a blank name and a backwards warranty fail for different reasons and "something went
  /// wrong" distinguishes neither (Law U9).
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.name.trim().isEmpty) {
      _edit(
        (s) => s.copyWith(
          issue: AssetSaveIssue.nameMissing,
          shakeTrigger: s.shakeTrigger + 1,
        ),
        keepIssue: true,
      );
      return null;
    }
    final start = current.warrantyStartDateKey;
    final end = current.warrantyEndDateKey;
    if (start != null && end != null && end.isBefore(start)) {
      _edit((s) => s.copyWith(issue: AssetSaveIssue.warrantyBackwards), keepIssue: true);
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearIssue: true), keepIssue: true);
    try {
      final repository = ref.read(assetRepositoryProvider);
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      // The existing row is read so the fields this editor does not own — the disposal block, the
      // recurring link, the fan-out's source line — travel across untouched rather than being nulled by
      // a save that never asked about them.
      final existing = current.isEditing ? await repository.byId(id) : null;
      final saved = await repository.save(
        current.toAsset(
          newId: id,
          normalizedName: ref.read(normalizerProvider).normalize(current.name.trim()),
          existing: existing,
        ),
      );
      final failure = saved.failureOrNull;
      if (failure != null) {
        _edit(
          (s) => s.copyWith(issue: AssetSaveIssue.rejected, rejection: failure.message),
          keepIssue: true,
        );
        return null;
      }
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref.read(loggerProvider).log(
        'Asset save failed',
        level: LogLevel.error,
        tag: 'service.assetEditor',
        error: error,
        stackTrace: stack,
      );
      _edit(
        (s) => s.copyWith(issue: AssetSaveIssue.rejected, rejection: error.toString()),
        keepIssue: true,
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false), keepIssue: true);
    }
  }
}
```

### `lib/features/service/providers/service_editor_providers.dart`

```dart
/// View-model state for the service record editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/state/service_editor_state.dart';

/// Which record an editor is pointed at. A record, so the family argument has structural equality.
typedef ServiceEditorArgs = ({String assetId, String? recordId});

/// Payment methods the expense may record, when the user cares to say.
final servicePaymentMethodsProvider = StreamProvider.autoDispose<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// Accounts an expense may come from.
final serviceAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The app-wide default account, so the expense toggle rarely has to ask.
final serviceDefaultAccountProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readDefaultAccountId(),
);

/// The editor for one service record, or for a new one when `recordId` is null.
final serviceEditorProvider = NotifierProvider.autoDispose
    .family<ServiceEditorNotifier, AsyncValue<ServiceEditorState>, ServiceEditorArgs>(
  ServiceEditorNotifier.new,
);

/// Loads, edits and saves one service record.
class ServiceEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<ServiceEditorState>, ServiceEditorArgs> {
  @override
  AsyncValue<ServiceEditorState> build(ServiceEditorArgs arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(ServiceEditorArgs arg) async {
    try {
      final code =
          await ref.read(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR';
      final recordId = arg.recordId;
      if (recordId != null) {
        final record = await ref.read(serviceRecordRepositoryProvider).byId(recordId);
        if (record == null) {
          state = AsyncValue.error(
            StateError('Service record $recordId not found.'),
            StackTrace.current,
          );
          return;
        }
        state = AsyncValue.data(ServiceEditorState.fromRecord(record, code));
        return;
      }
      final asset = await ref.read(assetRepositoryProvider).byId(arg.assetId);
      if (asset == null) {
        state = AsyncValue.error(
          StateError('Asset ${arg.assetId} not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(
        ServiceEditorState(
          assetId: arg.assetId,
          currencyCode: code,
          serviceDateKey: ref.read(clockProvider).today(),
          // A person's record is a salary payment by default, and a thing's is a service. Making the
          // user correct the obvious is how the maid case ends up filed as "inspection".
          type: asset.isServiceProvider
              ? ServiceRecordType.salaryPaid
              : ServiceRecordType.service,
          providerName: asset.primaryContactName,
          providerPhone: asset.primaryContactPhone,
          // Seeded from the asset's own interval, so recording a service also proposes the next one.
          nextDueDateKey: asset.serviceIntervalDays == null
              ? null
              : ref.read(clockProvider).today().addDays(asset.serviceIntervalDays!),
          accountId: await _resolveAccount(),
          // **On by default for a new record.** A cost typed here is money that left the house, so the
          // ledger should show it without a second decision — and the account is already resolved, so
          // the common path is no extra taps at all. It stays visible and switchable, because a service
          // paid by someone else (a warranty repair, a landlord's plumber) is a real case.
          //
          // This is not anomaly A14. A14 forbids *materialisation* creating money on its own; here the
          // user typed a figure and pressed save, which is as explicit as an act gets.
          alsoRecordAsExpense: true,
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// The account an expense should come from when the user has not chosen one.
  ///
  /// **Two fallbacks, because one was not enough.** `readDefaultAccountId()` is null until somebody sets
  /// a default in Settings, and a null account makes `save` refuse the whole record — so a service with a
  /// cost silently could not be recorded at all. A sole selectable account is the obvious answer when
  /// there is only one, and it is information the user already gave (Law U23).
  Future<String?> _resolveAccount() async {
    final stored = await ref.read(settingsRepositoryProvider).readDefaultAccountId();
    if (stored != null) return stored;
    final accounts = await ref.read(accountRepositoryProvider).watchSelectable().first;
    return accounts.length == 1 ? accounts.single.id : null;
  }

  /// Applies [change], clearing the last rejection unless told to keep it.
  ///
  /// **A rejection is shown until the user acts, then it goes.** The message is rendered as a card in the
  /// form rather than only as a snack, because a snack lasts 2.5 seconds and a refused save is worth
  /// longer than that — but a card that survives the edit which fixes it is a stale error the user has to
  /// dismiss by hand. Every setter clears it; only `save` keeps it.
  void _edit(
    ServiceEditorState Function(ServiceEditorState) change, {
    bool keepIssue = false,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = change(current);
    state = AsyncValue.data(keepIssue ? next : next.copyWith(clearIssue: true));
  }

  /// Sets what happened.
  void setType(ServiceRecordType type) => _edit((s) => s.copyWith(type: type));

  /// Sets when.
  void setServiceDate(DateKey? date) =>
      _edit((s) => date == null ? s : s.copyWith(serviceDateKey: date));

  /// Sets who did it, or who was paid.
  void setProviderName(String value) => _edit((s) => s.copyWith(providerName: value));

  /// Sets their number.
  void setProviderPhone(String value) => _edit((s) => s.copyWith(providerPhone: value));

  /// Sets what it cost.
  void setCost(Money? cost) => _edit(
        (s) => cost == null
            ? s.copyWith(clearCost: true, clearIssue: true)
            : s.copyWith(cost: cost, clearIssue: true),
      );

  /// Sets when the next one is due.
  void setNextDue(DateKey? date) => _edit(
        (s) => date == null
            ? s.copyWith(clearNextDue: true)
            : s.copyWith(nextDueDateKey: date),
      );

  /// Sets the free notes.
  void setNotes(String value) => _edit((s) => s.copyWith(notes: value));

  /// Turns the expense toggle on or off.
  void toggleExpense() =>
      _edit((s) => s.copyWith(alsoRecordAsExpense: !s.alsoRecordAsExpense, clearIssue: true));

  /// Sets which account the expense comes from.
  void setAccount(String? accountId) =>
      _edit((s) => s.copyWith(accountId: accountId, clearIssue: true));

  /// Sets how it was paid. Never required.
  void setPaymentMethod(String? methodId) =>
      _edit((s) => s.copyWith(paymentMethodId: methodId));

  /// Saves the record, returning its id on success and null on rejection or failure.
  ///
  /// **The expense is written by the repository, in the same call.** `save(record,
  /// alsoRecordAsExpense: true, accountId: …)` writes the record and the withdrawal; nothing here does
  /// it by hand. The sequence is not atomic across aggregates, so it is ordered and idempotent instead
  /// (ARCH_4 R21) — and it is one write path, not two (Law U22).
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.alsoRecordAsExpense && !(current.cost?.isPositive ?? false)) {
      _edit(
        (s) => s.copyWith(
          issue: ServiceSaveIssue.costMissingForExpense,
          shakeTrigger: s.shakeTrigger + 1,
        ),
        keepIssue: true,
      );
      return null;
    }
    if (current.alsoRecordAsExpense && current.accountId == null) {
      _edit(
        (s) => s.copyWith(issue: ServiceSaveIssue.accountMissingForExpense),
        keepIssue: true,
      );
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearIssue: true), keepIssue: true);
    try {
      final repository = ref.read(serviceRecordRepositoryProvider);
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final existing = current.isEditing ? await repository.byId(id) : null;
      final saved = await repository.save(
        current.toRecord(newId: id, existing: existing),
        alsoRecordAsExpense: current.alsoRecordAsExpense,
        accountId: current.accountId,
        paymentMethodId: current.paymentMethodId,
      );
      final failure = saved.failureOrNull;
      if (failure != null) {
        _edit(
          (s) => s.copyWith(issue: ServiceSaveIssue.rejected, rejection: failure.message),
          keepIssue: true,
        );
        return null;
      }
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref.read(loggerProvider).log(
        'Service record save failed',
        level: LogLevel.error,
        tag: 'service.recordEditor',
        error: error,
        stackTrace: stack,
      );
      _edit(
        (s) => s.copyWith(issue: ServiceSaveIssue.rejected, rejection: error.toString()),
        keepIssue: true,
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false), keepIssue: true);
    }
  }
}
```

### `lib/features/service/providers/dispose_providers.dart`

```dart
/// View-model state for disposal (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/state/dispose_state.dart';

/// Which asset a dispose sheet is retiring, and the currency a recovery is entered in.
typedef DisposeArgs = ({String assetId, String currencyCode});

/// The dispose sheet for one asset.
final disposeProvider =
    NotifierProvider.autoDispose.family<DisposeNotifier, DisposeState, DisposeArgs>(
  DisposeNotifier.new,
);

/// Holds the pending disposal and commits it.
///
/// **State is synchronous.** Everything the sheet needs arrives in the family argument from the screen
/// that already loaded the asset, so the reason picker is usable on the first frame rather than after a
/// spinner (ARCH_5 §5.2).
class DisposeNotifier extends AutoDisposeFamilyNotifier<DisposeState, DisposeArgs> {
  @override
  DisposeState build(DisposeArgs arg) => DisposeState(
        assetId: arg.assetId,
        currencyCode: arg.currencyCode,
        dateKey: ref.read(clockProvider).today(),
      );

  /// Sets why it is being retired.
  void setReason(AssetDisposalReason reason) =>
      state = state.copyWith(reason: reason, reasonMissing: false, dirty: true);

  /// Sets when.
  void setDate(DateKey date) => state = state.copyWith(dateKey: date, dirty: true);

  /// Sets what the disposal recovered.
  void setAmount(Money? amount) => state = amount == null
      ? state.copyWith(clearAmount: true, dirty: true)
      : state.copyWith(amount: amount, dirty: true);

  /// Sets the note.
  void setNote(String note) => state = state.copyWith(note: note, dirty: true);

  /// Commits the disposal, returning the failure's own message or null on success.
  ///
  /// **`dispose` changes a status and records a reason. Nothing is deleted.** The purchase price stays
  /// on the row, so what the household spent on the thing still counts in every total after the thing
  /// itself has gone (anomaly A30, ARCH_3 §4.1).
  ///
  /// The amount is passed as minor units because that is what the contract takes; the currency is the
  /// asset's own, which is why the sheet is handed one rather than picking.
  Future<String?> commit() async {
    final reason = state.reason;
    if (reason == null) {
      state = state.copyWith(
        reasonMissing: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return 'reasonMissing';
    }

    state = state.copyWith(submitting: true, clearRejection: true);
    try {
      final result = await ref.read(assetRepositoryProvider).dispose(
            assetId: state.assetId,
            reason: reason,
            dateKey: state.dateKey,
            amountMinor: state.amount?.minor,
            note: state.note,
          );
      final failure = result.failureOrNull;
      if (failure != null) {
        state = state.copyWith(rejection: failure.message);
        return failure.message;
      }
      return null;
    } on Object catch (error, stack) {
      ref.read(loggerProvider).log(
        'Asset disposal failed',
        level: LogLevel.error,
        tag: 'service.dispose',
        error: error,
        stackTrace: stack,
      );
      state = state.copyWith(rejection: error.toString());
      return error.toString();
    } finally {
      state = state.copyWith(submitting: false);
    }
  }
}
```

### `lib/features/service/presentation/widgets/contact_action.dart`

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';

/// A name, a number, and a button that dials it.
///
/// **The only outbound action in the app, and it reports its own failure.** `launchUrl` returns false
/// when no handler exists for `tel:` — a tablet without a dialler, or a restricted profile — and a
/// button that silently does nothing is worse than one that says why (Law U9).
///
/// The number is rendered as plain selectable text beside the action so it stays useful when the call
/// cannot be placed at all.
class ContactAction extends StatelessWidget {
  /// Creates the block.
  const ContactAction({required this.phone, this.name, super.key});

  /// The number to dial.
  final String phone;

  /// Who answers, if known.
  final String? name;

  Future<void> _call(BuildContext context) async {
    final strings = AlayaStrings.of(context);
    // `Uri(scheme:, path:)` rather than a parsed string: a number containing spaces or a leading plus
    // is common and `Uri.parse('tel:+91 98…')` mangles it.
    final launched = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (launched || !context.mounted) return;
    showFailureSnack(context, message: strings.callFailed);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final who = name;

    // A `Wrap`: the name, the number and the button all grow with text scale, and a `Row` would starve
    // whichever came first at 320dp (Law U21).
    return Wrap(
      spacing: AlayaSpacing.xs,
      runSpacing: AlayaSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (who != null && who.isNotEmpty)
          Text(
            who,
            style: AlayaTypography.body
                .copyWith(color: Theme.of(context).colorScheme.onSurface),
          ),
        // **Plain text, not a selectable widget.** `SelectableText` carries a `longPress` semantics
        // action, so the accessibility sweep counts it as a tap target and fails it at 162x16 — it is
        // 16px tall and cannot be 48 without dwarfing the row. The number is already reachable through
        // the Call button beside it, and long-press-to-copy on a 16px strip was never a real
        // affordance (Law U16).
        Text(
          phone,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _call(context),
          icon: const Icon(Icons.call, size: AlayaIconSize.sm),
          label: Text(strings.actionCall),
        ),
      ],
    );
  }
}
```

### `lib/features/service/presentation/widgets/asset_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One asset: what it is, what it cost, and what needs attention.
///
/// **Warranty and service state are derived on every build, never stored.** `isUnderWarranty(today)`
/// and `isServiceOverdue(today)` are asked of the entity, because a stored flag is wrong the moment
/// midnight passes with the app closed (ARCH_2 §12.2).
///
/// Three tiers rather than one line: the figure, then the chips, then nothing else. A `Row` pairing the
/// name with the price would starve the name at a doubled text scale (Law U21).
class AssetRowTile extends StatelessWidget {
  /// Creates the row.
  const AssetRowTile({
    required this.asset,
    required this.today,
    required this.decimalDigits,
    required this.onTap,
    super.key,
  });

  /// The asset.
  final Asset asset;

  /// Today, for the warranty and service derivations.
  final DateKey today;

  /// The currency's precision.
  final int decimalDigits;

  /// Opens the detail screen.
  final VoidCallback onTap;

  /// How many days ahead counts as "soon" for a warranty or a service.
  static const int soonDays = 30;

  static IconData glyphFor(AssetType type) => switch (type) {
        AssetType.appliance => Icons.kitchen_outlined,
        AssetType.electronics => Icons.devices_outlined,
        AssetType.vehicle => Icons.directions_car_outlined,
        AssetType.furniture => Icons.chair_outlined,
        AssetType.property => Icons.home_outlined,
        // A person, not a thing — and the glyph says so before any label does.
        AssetType.serviceProvider => Icons.person_outline,
        AssetType.subscription => Icons.card_membership_outlined,
        AssetType.other => Icons.inventory_2_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final price = asset.purchasePrice;

    final chips = <Widget>[
      if (asset.isDisposed)
        StatusChip(label: strings.assetDisposedChip)
      else if (asset.status == AssetStatus.underRepair)
        StatusChip(label: strings.assetUnderRepair, tone: StatusTone.warning),
      if (!asset.isDisposed) ...[
        if (asset.isServiceOverdue(today))
          StatusChip(label: strings.assetServiceDue, tone: StatusTone.danger)
        else if (asset.nextServiceDueDateKey != null &&
            (asset.serviceDaysLeftFrom(today) ?? soonDays + 1) <= soonDays)
          StatusChip(label: strings.assetServiceSoon, tone: StatusTone.warning),
        if (asset.warrantyEndDateKey != null)
          if (!asset.isUnderWarranty(today))
            StatusChip(label: strings.assetWarrantyExpired)
          else if (asset.isWarrantyEndingWithin(today, soonDays))
            StatusChip(label: strings.assetWarrantyEnding, tone: StatusTone.warning)
          else
            StatusChip(label: strings.assetUnderWarranty, tone: StatusTone.success),
        if (asset.linkedRecurringTemplateId != null)
          StatusChip(label: strings.assetLinkedRecurring, tone: StatusTone.info),
      ],
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
                    glyphFor(asset.type),
                    size: AlayaIconSize.lg,
                    color: asset.isDisposed ? semantic.muted : semantic.muted,
                  ),
                  const SizedBox(width: AlayaSpacing.sm),
                  Expanded(
                    child: Text(
                      asset.name,
                      style: AlayaTypography.body.copyWith(
                        color: asset.isDisposed
                            ? semantic.muted
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: AlayaIconSize.lg + AlayaSpacing.sm,
                  top: AlayaSpacing.xxs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (price != null)
                      AmountText(
                        price,
                        size: AmountSize.small,
                        showSign: false,
                        decimalDigits: decimalDigits,
                        muted: asset.isDisposed,
                      ),
                    if (chips.isNotEmpty) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Wrap(
                        spacing: AlayaSpacing.xs,
                        runSpacing: AlayaSpacing.xxs,
                        children: chips,
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

### `lib/features/service/presentation/screens/asset_list_screen.dart`

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
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/service/presentation/widgets/asset_row.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Everything the household owns, and everyone it pays (ARCH_5 §3 archetype D).
///
/// **Disposed assets are behind a filter, never gone.** An asset is never deleted (anomaly A30), so the
/// switch is what keeps the list about things you still have while leaving the ones you spent money on
/// reachable in one tap.
class AssetListScreen extends ConsumerWidget {
  /// Creates the screen.
  const AssetListScreen({super.key});

  /// Resolves an [AssetType] to its ARB label, so no screen writes the words.
  static String typeLabel(AlayaStrings strings, AssetType type) => switch (type) {
        AssetType.appliance => strings.assetGroupAppliance,
        AssetType.electronics => strings.assetGroupElectronics,
        AssetType.vehicle => strings.assetGroupVehicle,
        AssetType.furniture => strings.assetGroupFurniture,
        AssetType.property => strings.assetGroupProperty,
        AssetType.serviceProvider => strings.assetGroupServiceProvider,
        AssetType.subscription => strings.assetGroupSubscription,
        AssetType.other => strings.assetGroupOther,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final groups = ref.watch(assetGroupsProvider);
    final filter = ref.watch(assetFilterProvider);

    return Scaffold(
      body: Column(
        children: [
          const _Toolbar(),
          const _ActiveFilters(),
          Expanded(
            child: groups.when(
              loading: () => AlayaListSkeleton(label: strings.loadingAssets),
              error: (error, stack) => ErrorState(
                title: strings.errorTitleGeneric,
                body: error.toString(),
                retryLabel: strings.actionRetry,
                onRetry: () {
                  ref.invalidate(assetsInUseProvider);
                  ref.invalidate(disposedAssetsProvider);
                },
              ),
              data: (sections) => sections.isEmpty
                  ? _Empty(isNarrowed: filter.isNarrowed || filter.isSearching)
                  : _Sections(sections: sections),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.assetNew),
        tooltip: strings.addAsset,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(assetFilterProvider.notifier);
    final filter = ref.watch(assetFilterProvider);
    final dueCount = ref.watch(serviceDueCountProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.sm,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AlayaSearchField(
            onChanged: notifier.setQuery,
            clearLabel: strings.actionClearSearch,
            hintText: strings.hintSearchAssets,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: Text(strings.filterShowDisposed),
                selected: filter.includeDisposed,
                onSelected: (_) => notifier.toggleDisposed(),
              ),
              if (dueCount > 0)
                StatusChip(
                  label: strings.assetServiceDue,
                  tone: StatusTone.danger,
                  trailing: Text(
                    '$dueCount',
                    style: AlayaTypography.overline.copyWith(color: semantic.onStatus),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final filter = ref.watch(assetFilterProvider);
    final notifier = ref.read(assetFilterProvider.notifier);
    if (!filter.isNarrowed) return const SizedBox.shrink();

    return FilterChipBar(
      clearAllLabel: strings.filterReset,
      onClearAll: notifier.clear,
      filters: [
        if (filter.includeDisposed)
          ActiveFilter(
            label: strings.filterShowDisposed,
            onRemove: notifier.toggleDisposed,
          ),
        for (final type in filter.types)
          ActiveFilter(
            label: AssetListScreen.typeLabel(strings, type),
            onRemove: () => notifier.toggleType(type),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isNarrowed});

  final bool isNarrowed;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    if (isNarrowed) {
      return EmptyState(
        title: strings.emptyTitleNoResults,
        body: strings.emptyBodyNoResults,
        icon: Icons.search_off_outlined,
      );
    }
    return EmptyState(
      title: strings.emptyTitleNoAssets,
      body: strings.emptyBodyNoAssets,
      icon: Icons.handyman_outlined,
      actionLabel: strings.addAsset,
      onAction: () => context.push(Routes.assetNew),
    );
  }
}

class _Sections extends ConsumerWidget {
  const _Sections({required this.sections});

  final List<AssetGroup> sections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;

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
                    AssetListScreen.typeLabel(strings, section.type),
                    style: AlayaTypography.sectionHeader.copyWith(color: semantic.muted),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: section.assets.length,
                itemBuilder: (context, index) {
                  final asset = section.assets[index];
                  return AssetRowTile(
                    asset: asset,
                    today: today,
                    decimalDigits: digits,
                    onTap: () => context.push(Routes.assetDetail(asset.id)),
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

### `lib/features/service/presentation/screens/asset_detail_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/asset_row.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_detail_providers.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One asset, everything spent on it, and everything that still needs doing (archetype E, outside the
/// shell per U18).
///
/// **A disposed asset opens here exactly as a live one does.** Nothing is deleted (anomaly A30), so the
/// purchase price, the warranty history and every service record survive disposal — which is the whole
/// point of recording a reason instead of a `DELETE`.
class AssetDetailScreen extends ConsumerWidget {
  /// Shows [assetId].
  const AssetDetailScreen({required this.assetId, super.key});

  /// Which asset to show.
  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(assetByIdProvider(assetId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.assetEdit(assetId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingAssets, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(assetsInUseProvider),
        ),
        data: (asset) => asset == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(asset: asset),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.asset});

  final Asset asset;

  Future<void> _dispose(BuildContext context, WidgetRef ref, String currencyCode) async {
    final strings = AlayaStrings.of(context);
    final error = await DisposeSheet.show(
      context,
      assetId: asset.id,
      currencyCode: currencyCode,
    );
    if (!context.mounted || error == null) return;
    error.isEmpty
        ? showResultSnack(context, message: strings.disposeDone)
        : showFailureSnack(context, message: error);
  }

  Future<void> _undispose(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final error = await ref.read(assetActionsProvider).undispose(asset.id);
    if (!context.mounted) return;
    error == null
        ? showResultSnack(context, message: strings.undisposeDone)
        : showFailureSnack(context, message: error);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final currency = ref.watch(serviceCurrencyProvider).valueOrNull ?? 'INR';
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) => DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());
    final person = asset.isServiceProvider;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: _Hero(asset: asset, today: today, decimalDigits: digits),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (asset.hasContactPhone) ...[
                  SectionHeader(label: strings.assetSectionContact),
                  ContactAction(
                    phone: asset.primaryContactPhone!,
                    name: asset.primaryContactName,
                  ),
                ],
                SectionHeader(label: strings.assetSectionIdentity),
                if (asset.brand != null)
                  KeyValueRow(label: strings.labelBrand, value: asset.brand),
                if (asset.modelNo != null)
                  KeyValueRow(label: strings.labelModelNo, value: asset.modelNo),
                if (asset.serialNo != null)
                  KeyValueRow(label: strings.labelSerialNo, value: asset.serialNo),
                if (asset.location != null)
                  KeyValueRow(label: strings.labelLocation, value: asset.location),
                if (asset.purchaseDateKey != null)
                  KeyValueRow(
                    label: strings.labelPurchased,
                    valueWidget:
                        DateText(asset.purchaseDateKey!, style: DateTextStyle.full),
                  ),
                if (asset.warrantyEndDateKey != null) ...[
                  SectionHeader(label: strings.assetSectionWarranty),
                  if (asset.warrantyStartDateKey != null)
                    KeyValueRow(
                      label: strings.labelWarrantyStart,
                      valueWidget: DateText(
                        asset.warrantyStartDateKey!,
                        style: DateTextStyle.full,
                      ),
                    ),
                  KeyValueRow(
                    label: strings.labelWarrantyEnd,
                    valueWidget:
                        DateText(asset.warrantyEndDateKey!, style: DateTextStyle.full),
                  ),
                  if (asset.warrantyProvider != null)
                    KeyValueRow(
                      label: strings.labelWarrantyProvider,
                      value: asset.warrantyProvider,
                    ),
                ],
                if (asset.serviceIntervalDays != null || asset.nextServiceDueDateKey != null) ...[
                  SectionHeader(label: strings.assetSectionService),
                  if (asset.serviceIntervalDays != null)
                    KeyValueRow(
                      label: strings.labelServiceInterval,
                      value: strings.unitDay(asset.serviceIntervalDays!),
                    ),
                  if (asset.nextServiceDueDateKey != null)
                    KeyValueRow(
                      label: strings.labelNextService,
                      valueWidget: DateText(
                        asset.nextServiceDueDateKey!,
                        style: DateTextStyle.full,
                      ),
                    ),
                ],
                const SizedBox(height: AlayaSpacing.md),
                _Lifetime(asset: asset, decimalDigits: digits),
                const SizedBox(height: AlayaSpacing.md),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  children: [
                    if (!asset.isDisposed)
                      FilledButton.tonalIcon(
                        onPressed: () => context.push(Routes.serviceNew(asset.id)),
                        icon: const Icon(Icons.add, size: AlayaIconSize.sm),
                        label: Text(
                          person ? strings.actionAddSalary : strings.actionAddService,
                        ),
                      ),
                    if (asset.isDisposed)
                      TextButton.icon(
                        onPressed: () => _undispose(context, ref),
                        icon: const Icon(Icons.undo, size: AlayaIconSize.sm),
                        label: Text(strings.actionUndispose),
                      )
                    else
                      TextButton.icon(
                        onPressed: () => _dispose(context, ref, currency),
                        icon: const Icon(Icons.archive_outlined, size: AlayaIconSize.sm),
                        label: Text(strings.actionDispose),
                      ),
                  ],
                ),
                SectionHeader(
                  label: person ? strings.assetSectionSalary : strings.assetSectionService,
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.xl,
                    bottom: AlayaSpacing.xs,
                  ),
                ),
              ],
            ),
          ),
        ),
        _History(asset: asset, decimalDigits: digits, format: format),
        const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.asset, required this.today, required this.decimalDigits});

  final Asset asset;
  final DateKey today;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final price = asset.purchasePrice;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AssetRowTile.glyphFor(asset.type),
                size: AlayaIconSize.xl,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.sm),
              Expanded(
                child: Text(
                  asset.name,
                  style: AlayaTypography.screenTitle
                      .copyWith(color: theme.colorScheme.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.sm),
          if (price != null)
            AmountText(price, showSign: false, decimalDigits: decimalDigits),
          const SizedBox(height: AlayaSpacing.xs),
          // Warranty and service state, derived on every build. A disposed asset says so first,
          // because everything else about it is history.
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xxs,
            children: [
              if (asset.isDisposed)
                StatusChip(label: strings.assetDisposedChip)
              else if (asset.status == AssetStatus.underRepair)
                StatusChip(label: strings.assetUnderRepair, tone: StatusTone.warning),
              if (!asset.isDisposed && asset.warrantyEndDateKey != null)
                if (!asset.isUnderWarranty(today))
                  StatusChip(label: strings.assetWarrantyExpired)
                else if (asset.isWarrantyEndingWithin(today, AssetRowTile.soonDays))
                  StatusChip(
                    label: strings.assetWarrantyEnding,
                    tone: StatusTone.warning,
                  )
                else
                  StatusChip(
                    label: strings.assetUnderWarranty,
                    tone: StatusTone.success,
                  ),
              if (!asset.isDisposed && asset.isServiceOverdue(today))
                StatusChip(label: strings.assetServiceDue, tone: StatusTone.danger),
              if (asset.linkedRecurringTemplateId != null)
                StatusChip(label: strings.assetLinkedRecurring, tone: StatusTone.info),
            ],
          ),
          if (asset.isDisposed && asset.disposedAtDateKey != null) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Wrap(
              spacing: AlayaSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  strings.labelDisposalDate,
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
                DateText(asset.disposedAtDateKey!, style: DateTextStyle.full, muted: true),
                if (asset.disposalAmount != null)
                  AmountText(
                    asset.disposalAmount!,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: decimalDigits,
                    muted: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Lifetime extends ConsumerWidget {
  const _Lifetime({required this.asset, required this.decimalDigits});

  final Asset asset;
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(lifetimeServiceCostProvider(asset.id));
    final totals = async.valueOrNull;
    if (totals == null || totals.isEmpty) return const SizedBox.shrink();

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            asset.isServiceProvider
                ? strings.assetLifetimeSalary
                : strings.assetLifetimeCost,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          // One figure per currency, never summed. Adding two currencies would invent an exchange rate
          // the user never agreed to (Law L1).
          Wrap(
            spacing: AlayaSpacing.sm,
            runSpacing: AlayaSpacing.xxs,
            children: [
              for (final total in totals.values)
                AmountText(total, showSign: false, decimalDigits: decimalDigits),
            ],
          ),
        ],
      ),
    );
  }
}

/// Resolves a [ServiceRecordType] to its ARB label.
///
/// Public and in one place because the timeline and the editor both name these, and two switches over
/// the same enum drift the moment a value is added (ARCH_4 R38).
class ServiceTypeLabels {
  const ServiceTypeLabels._();

  /// The label for [type].
  static String of(AlayaStrings strings, ServiceRecordType type) => switch (type) {
        ServiceRecordType.service => strings.serviceTypeService,
        ServiceRecordType.repair => strings.serviceTypeRepair,
        ServiceRecordType.maintenance => strings.serviceTypeMaintenance,
        ServiceRecordType.inspection => strings.serviceTypeInspection,
        ServiceRecordType.salaryPaid => strings.serviceTypeSalaryPaid,
        ServiceRecordType.other => strings.serviceTypeOther,
      };
}

class _History extends ConsumerWidget {
  const _History({
    required this.asset,
    required this.decimalDigits,
    required this.format,
  });

  final Asset asset;
  final int decimalDigits;
  final String Function(DateKey) format;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(serviceRecordsProvider(asset.id));

    return async.when(
      loading: () => SliverToBoxAdapter(
        child: AlayaListSkeleton(label: strings.loadingAssets),
      ),
      error: (error, stack) => SliverToBoxAdapter(
        child: ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(serviceRecordsProvider(asset.id)),
        ),
      ),
      data: (records) {
        if (records.isEmpty) {
          return SliverToBoxAdapter(
            child: EmptyState(
              title: strings.emptyTitleNoOccurrences,
              body: strings.emptyBodyNoServices,
              icon: Icons.build_outlined,
            ),
          );
        }
        final ordered = [...records]
          ..sort((a, b) => b.serviceDateKey.compareTo(a.serviceDateKey));
        return AlayaTimeline(
          itemCount: ordered.length,
          itemBuilder: (context, index) {
            final record = ordered[index];
            final cost = record.cost;
            return AlayaTimelineEntry(
              title: ServiceTypeLabels.of(strings, record.type),
              trailing: cost == null
                  ? const SizedBox.shrink()
                  : AmountText(
                      cost,
                      size: AmountSize.small,
                      showSign: false,
                      decimalDigits: decimalDigits,
                    ),
              subtitle: DateText(record.serviceDateKey, style: DateTextStyle.medium, muted: true),
              meta: record.providerName ?? record.notes,
              icon: record.type == ServiceRecordType.salaryPaid
                  ? Icons.payments_outlined
                  : Icons.build_outlined,
              tone: record.type == ServiceRecordType.repair
                  ? TimelineTone.outgoing
                  : TimelineTone.neutral,
              // **No badge.** With the expense toggle on by default, a service that reached the ledger
              // is the rule rather than the exception, and a chip on every row is noise. Marking the
              // inverse — the rare record that did *not* create a transaction — would carry real
              // information, but that is a different design and not one that was asked for.
              badge: null,
              onTap: () => context.push(Routes.serviceEdit(asset.id, record.id)),
            );
          },
        );
      },
    );
  }
}
```
### `lib/features/service/presentation/screens/asset_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/state/asset_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Records an asset — or a person (ARCH_5 §3 archetype B), outside the shell per U18.
///
/// **Only the name is required, and that is what makes `type = serviceProvider` work.** A house maid has
/// no serial number, no warranty and no purchase price; a television has no phone number worth calling.
/// Both live in one table because every field except the name is optional, so neither has to be
/// described in the other's vocabulary.
class AssetEditorScreen extends ConsumerWidget {
  /// Edits [assetId], or creates a new asset when it is null.
  const AssetEditorScreen({this.assetId, super.key});

  /// The asset being edited, or null for a new one.
  final String? assetId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(assetEditorProvider(assetId).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      final state = ref.read(assetEditorProvider(assetId)).valueOrNull;
      showFailureSnack(
        context,
        message: state?.rejection ??
            switch (state?.issue) {
              AssetSaveIssue.nameMissing => strings.errorFieldRequired,
              AssetSaveIssue.warrantyBackwards => strings.errorWarrantyBackwards,
              AssetSaveIssue.rejected || null => strings.errorBodyGeneric,
            },
      );
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(assetEditorProvider(assetId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(assetId == null ? strings.editorTitleNew : strings.editorTitleEdit),
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingAssets, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveAsset,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: assetId, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final AssetEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(assetEditorProvider(editorId).notifier);
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) => DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.assetSectionIdentity,
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextFormField(
            initialValue: state.name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.labelAssetName,
              errorText: state.issue == AssetSaveIssue.nameMissing
                  ? strings.errorFieldRequired
                  : null,
            ),
            onChanged: notifier.setName,
          ),
        ),
        // Informational, never a block. A repeated name is normal — but saying nothing would leave a
        // genuine slip, the same phone entered twice, invisible.
        if (ref.watch(assetNameClashProvider((id: state.id, name: state.name)))) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.assetSameNameNote,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<AssetType>(
          key: ValueKey(state.type),
          initialValue: state.type,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelAssetType),
          items: [
            for (final type in AssetType.values)
              DropdownMenuItem(
                value: type,
                child: Text(AssetListScreen.typeLabel(strings, type)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setType(value),
        ),
        if (state.isPerson) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.assetTypeHelpPerson,
            style: AlayaTypography.caption.copyWith(color: semantic.transfer),
          ),
        ],
        // A person has no brand, model or serial, so those fields are not offered at all rather than
        // offered and left blank — an empty "Model" on a human being is worse than its absence.
        if (!state.isPerson) ...[
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.brand,
            decoration: InputDecoration(labelText: strings.labelBrand),
            onChanged: notifier.setBrand,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.modelNo,
            decoration: InputDecoration(labelText: strings.labelModelNo),
            onChanged: notifier.setModelNo,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.serialNo,
            decoration: InputDecoration(labelText: strings.labelSerialNo),
            onChanged: notifier.setSerialNo,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.location,
            decoration: InputDecoration(labelText: strings.labelLocation),
            onChanged: notifier.setLocation,
          ),
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: state.purchaseDateKey,
            formatted: format,
            label: strings.labelPurchased,
            hint: strings.hintSelectDate,
            onChanged: notifier.setPurchaseDate,
          ),
          const SizedBox(height: AlayaSpacing.md),
          AmountField(
            currencyCode: state.currencyCode,
            decimalDigits: digits,
            label: strings.labelPurchasePrice,
            initialValue: state.purchasePrice,
            onChanged: notifier.setPurchasePrice,
          ),
          SectionHeader(
            label: strings.assetSectionWarranty,
            padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
          ),
          DatePickerField(
            value: state.warrantyStartDateKey,
            formatted: format,
            label: strings.labelWarrantyStart,
            hint: strings.hintSelectDate,
            onChanged: notifier.setWarrantyStart,
          ),
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: state.warrantyEndDateKey,
            formatted: format,
            label: strings.labelWarrantyEnd,
            hint: strings.hintSelectDate,
            errorText: state.issue == AssetSaveIssue.warrantyBackwards
                ? strings.errorWarrantyBackwards
                : null,
            onChanged: notifier.setWarrantyEnd,
          ),
          const SizedBox(height: AlayaSpacing.md),
          TextFormField(
            initialValue: state.warrantyProvider,
            decoration: InputDecoration(labelText: strings.labelWarrantyProvider),
            onChanged: notifier.setWarrantyProvider,
          ),
        ],
        SectionHeader(
          label: strings.assetSectionService,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        TextFormField(
          initialValue: state.serviceIntervalDays?.toString(),
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: strings.labelServiceInterval,
            helperText: strings.serviceIntervalHelp,
            helperMaxLines: 3,
          ),
          onChanged: (raw) =>
              notifier.setServiceIntervalDays(int.tryParse(raw.trim())),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.nextServiceDueDateKey,
          formatted: format,
          label: strings.labelNextService,
          hint: strings.hintSelectDate,
          onChanged: notifier.setNextServiceDue,
        ),
        SectionHeader(
          label: strings.assetSectionContact,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        TextFormField(
          initialValue: state.contactName,
          decoration: InputDecoration(labelText: strings.labelContactName),
          onChanged: notifier.setContactName,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.contactPhone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: strings.labelContactPhone),
          onChanged: notifier.setContactPhone,
        ),
        SectionHeader(
          label: strings.labelNote,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        TextFormField(
          initialValue: state.notes,
          maxLines: 3,
          decoration: InputDecoration(hintText: strings.hintNote),
          onChanged: notifier.setNotes,
        ),
        if (state.issue == AssetSaveIssue.rejected && state.rejection != null) ...[
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

### `lib/features/service/presentation/screens/service_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/service_editor_providers.dart';
import 'package:alaya/features/service/state/service_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Records what was done to a thing, or what was paid to a person (archetype B, outside the shell).
///
/// **`type = salaryPaid` is what puts a maid's wages in the same table as a boiler service.** The maid
/// case needs no new screen: her asset row, this editor and the "also record as an expense" toggle are
/// the three pieces, and the salary history on her detail screen is this table filtered by type.
class ServiceEditorScreen extends ConsumerWidget {
  /// Edits [recordId] against [assetId], or creates a new record when it is null.
  const ServiceEditorScreen({required this.assetId, this.recordId, super.key});

  /// Which asset the record belongs to.
  final String assetId;

  /// The record being edited, or null for a new one.
  final String? recordId;

  ServiceEditorArgs get _args => (assetId: assetId, recordId: recordId);

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(serviceEditorProvider(_args).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      final state = ref.read(serviceEditorProvider(_args)).valueOrNull;
      showFailureSnack(
        context,
        message: state?.rejection ??
            switch (state?.issue) {
              ServiceSaveIssue.costMissingForExpense => strings.alsoRecordNeedsCost,
              ServiceSaveIssue.accountMissingForExpense =>
                strings.alsoRecordNeedsAccount,
              ServiceSaveIssue.rejected || null => strings.errorBodyGeneric,
            },
      );
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(serviceEditorProvider(_args));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(recordId == null ? strings.editorTitleNew : strings.editorTitleEdit),
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingAssets, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleNotFound,
          body: strings.errorBodyNotFound,
        ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: strings.saveService,
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(args: _args, state: state),
        ),
      ),
    );
  }
}

class _Form extends ConsumerWidget {
  const _Form({required this.args, required this.state});

  final ServiceEditorArgs args;
  final ServiceEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(serviceEditorProvider(args).notifier);
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts = ref.watch(serviceAccountsProvider).valueOrNull ?? const <Account>[];
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) => DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    // The dropdown's value comes from the list being rendered, never from state: the accounts arrive
    // from a stream, and a value matching none of the items throws (ARCH_4 R33).
    Account? selectedAccount;
    for (final account in accounts) {
      if (account.id == state.accountId) selectedAccount = account;
    }
    final methods =
        ref.watch(servicePaymentMethodsProvider).valueOrNull ?? const <PaymentMethod>[];
    PaymentMethod? selectedMethod;
    for (final method in methods) {
      if (method.id == state.paymentMethodId) selectedMethod = method;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<ServiceRecordType>(
          key: ValueKey(state.type),
          initialValue: state.type,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelServiceType),
          items: [
            for (final type in ServiceRecordType.values)
              DropdownMenuItem(
                value: type,
                child: Text(ServiceTypeLabels.of(strings, type)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setType(value),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.serviceDateKey,
          formatted: format,
          label: strings.labelServiceDate,
          hint: strings.hintSelectDate,
          onChanged: notifier.setServiceDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.providerName,
          decoration: InputDecoration(labelText: strings.labelProviderName),
          onChanged: notifier.setProviderName,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextFormField(
          initialValue: state.providerPhone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(labelText: strings.labelProviderPhone),
          onChanged: notifier.setProviderPhone,
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: state.currencyCode,
            decimalDigits: digits,
            label: strings.labelServiceCost,
            initialValue: state.cost,
            errorText: state.issue == ServiceSaveIssue.costMissingForExpense
                ? strings.alsoRecordNeedsCost
                : null,
            onChanged: notifier.setCost,
          ),
        ),
        // Not offered for a salary: the next payment is the recurring template's business, and a second
        // due date here would be a second schedule to keep in step.
        if (!state.isSalary) ...[
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: state.nextDueDateKey,
            formatted: format,
            label: strings.labelNextDue,
            hint: strings.hintSelectDate,
            onChanged: notifier.setNextDue,
          ),
        ],
        SectionHeader(
          label: strings.sectionMoney,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        SwitchListTile(
          value: state.alsoRecordAsExpense,
          contentPadding: EdgeInsets.zero,
          title: Text(strings.alsoRecordAsExpense),
          subtitle: Text(
            strings.alsoRecordHelp,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          onChanged: (_) => notifier.toggleExpense(),
        ),
        if (state.alsoRecordAsExpense) ...[
          const SizedBox(height: AlayaSpacing.md),
          if (accounts.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey(selectedAccount?.id),
              initialValue: selectedAccount?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.labelAccount,
                errorText: state.issue == ServiceSaveIssue.accountMissingForExpense
                    ? strings.alsoRecordNeedsAccount
                    : null,
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(value: account.id, child: Text(account.name)),
              ],
              onChanged: notifier.setAccount,
            ),
          // Optional, and last: an account says where the money came from and the expense needs it; a
          // method says how, and plenty of people never record it. Offered only when methods exist, so
          // an empty picker never appears.
          if (methods.isNotEmpty) ...[
            const SizedBox(height: AlayaSpacing.md),
            DropdownButtonFormField<String>(
              key: ValueKey(selectedMethod?.id),
              initialValue: selectedMethod?.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: strings.labelPaymentMethodOptional),
              items: [
                for (final method in methods)
                  DropdownMenuItem(value: method.id, child: Text(method.name)),
              ],
              onChanged: notifier.setPaymentMethod,
            ),
          ],
        ],
        SectionHeader(
          label: strings.labelNote,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        TextFormField(
          initialValue: state.notes,
          maxLines: 3,
          decoration: InputDecoration(hintText: strings.hintNote),
          onChanged: notifier.setNotes,
        ),
        if (state.issue == ServiceSaveIssue.rejected && state.rejection != null) ...[
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

### `lib/features/service/presentation/sheets/dispose_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/dispose_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Retires an asset without destroying it (ARCH_5 §3 archetype A).
///
/// **There is no delete anywhere in this module, and this sheet is why.** Disposal sets a status and
/// records a reason; the purchase price, the warranty dates and every service record stay exactly where
/// they were. The ₹45,000 spent on a television still counts in every total after the television has
/// gone to the tip, because the money left the house whether or not the object did (anomaly A30,
/// ARCH_3 §4.1). The body text says so, because a user reaching for this button is entitled to know
/// what it will not do.
class DisposeSheet extends ConsumerWidget {
  /// Creates the sheet.
  const DisposeSheet({required this.assetId, required this.currencyCode, super.key});

  /// Which asset is being retired.
  final String assetId;

  /// The currency a recovered amount is entered in.
  final String currencyCode;

  /// Opens the sheet.
  ///
  /// Resolves to the empty string when the disposal committed, to a message when it failed, and to null
  /// when the user backed out — so a caller can tell "done" from "changed their mind".
  static Future<String?> show(
    BuildContext context, {
    required String assetId,
    required String currencyCode,
  }) =>
      AlayaBottomSheet.show<String>(
        context: context,
        builder: (context) =>
            DisposeSheet(assetId: assetId, currencyCode: currencyCode),
      );

  DisposeArgs get _args => (assetId: assetId, currencyCode: currencyCode);

  /// Resolves an [AssetDisposalReason] to its ARB label.
  static String reasonLabel(AlayaStrings strings, AssetDisposalReason reason) =>
      switch (reason) {
        AssetDisposalReason.sold => strings.disposeReasonSold,
        AssetDisposalReason.expired => strings.disposeReasonExpired,
        AssetDisposalReason.damaged => strings.disposeReasonDamaged,
        AssetDisposalReason.gifted => strings.disposeReasonGifted,
        AssetDisposalReason.lost => strings.disposeReasonLost,
        AssetDisposalReason.replaced => strings.disposeReasonReplaced,
        AssetDisposalReason.other => strings.disposeReasonOther,
      };

  Future<void> _commit(BuildContext context, WidgetRef ref) async {
    final error = await ref.read(disposeProvider(_args).notifier).commit();
    if (!context.mounted) return;
    // A missing reason is a field error the sheet already shows; it must not close over it.
    if (error == 'reasonMissing') return;
    Navigator.of(context).pop(error ?? '');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final state = ref.watch(disposeProvider(_args));
    final notifier = ref.read(disposeProvider(_args).notifier);
    final digits = ref.watch(serviceDecimalDigitsProvider).valueOrNull ?? 2;
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) => DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.disposeTitle,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.disposeBody,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // A `Wrap` of choice chips rather than a dropdown: seven reasons is few enough to read at once,
        // and every one of them reflows independently at a doubled text scale (Law U21).
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final reason in AssetDisposalReason.values)
                ChoiceChip(
                  label: Text(reasonLabel(strings, reason)),
                  selected: state.reason == reason,
                  onSelected: (_) => notifier.setReason(reason),
                ),
            ],
          ),
        ),
        if (state.reasonMissing) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.disposeNeedsReason,
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.dateKey,
          formatted: format,
          label: strings.labelDisposalDate,
          hint: strings.hintSelectDate,
          onChanged: (date) => date == null ? null : notifier.setDate(date),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // Optional, because most disposals recover nothing — a broken kettle is thrown away, not sold —
        // and requiring a zero would make the common case extra typing.
        AmountField(
          currencyCode: currencyCode,
          decimalDigits: digits,
          label: strings.labelDisposalAmount,
          initialValue: state.amount,
          onChanged: notifier.setAmount,
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
        if (state.rejection != null) ...[
          const SizedBox(height: AlayaSpacing.sm),
          Text(
            state.rejection!,
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting ? null : () => _commit(context, ref),
          child: Text(strings.disposeCommit),
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
### `test/support/service_harness.dart`

```dart
/// Shared scaffolding for the Service Manager module's widget tests.
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
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every warranty and service derivation is the same on every machine.
final Clock kServiceClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kServiceClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// An account a service expense can be drawn from.
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

/// A television — the ordinary case: a thing, with a price and a warranty.
Asset television({
  String id = 'asset-1',
  String name = 'Living room TV',
  AssetStatus status = AssetStatus.active,
  int? priceMinor = 4500000,
  DateKey? warrantyEnd = const DateKey(20270131),
  DateKey? nextService,
  int? serviceIntervalDays,
  String? contactPhone,
  String? linkedRecurringTemplateId,
  DateKey? disposedAt,
  AssetDisposalReason? disposalReason,
  int? disposalMinor,
}) =>
    Asset(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      type: AssetType.electronics,
      status: status,
      brand: 'LG',
      modelNo: 'OLED55C3',
      purchaseDateKey: const DateKey(20260131),
      purchasePrice: priceMinor == null ? null : Money(priceMinor, 'INR'),
      warrantyStartDateKey: const DateKey(20260131),
      warrantyEndDateKey: warrantyEnd,
      warrantyProvider: 'LG India',
      serviceIntervalDays: serviceIntervalDays,
      nextServiceDueDateKey: nextService,
      primaryContactName: contactPhone == null ? null : 'LG Service',
      primaryContactPhone: contactPhone,
      location: 'Living room',
      linkedRecurringTemplateId: linkedRecurringTemplateId,
      disposedAtDateKey: disposedAt,
      disposalReason: disposalReason,
      disposalAmount: disposalMinor == null ? null : Money(disposalMinor, 'INR'),
    );

/// A house maid — the case §7.2 exists for: a person in the asset table with a salary history.
Asset maid({String id = 'asset-2', String name = 'Lakshmi', String? phone = '+919876543210'}) =>
    Asset(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      type: AssetType.serviceProvider,
      status: AssetStatus.active,
      primaryContactName: name,
      primaryContactPhone: phone,
      linkedRecurringTemplateId: 'tpl-1',
    );

/// A service record of any type.
ServiceRecord serviceRecord({
  String id = 'rec-1',
  String assetId = 'asset-1',
  DateKey on = const DateKey(20260601),
  ServiceRecordType type = ServiceRecordType.service,
  int? costMinor = 120000,
  String? providerName = 'LG Service',
  String? linkedTransactionId,
  DateKey? nextDue,
}) =>
    ServiceRecord(
      id: id,
      assetId: assetId,
      serviceDateKey: on,
      type: type,
      providerName: providerName,
      cost: costMinor == null ? null : Money(costMinor, 'INR'),
      linkedTransactionId: linkedTransactionId,
      nextDueDateKey: nextDue,
    );

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpService(
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

### `test/features/service/asset_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/widgets/asset_row.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  List<Override> overrides({
    List<Asset>? inUse,
    List<Asset> disposed = const [],
    bool pending = false,
    bool fail = false,
  }) =>
      [
        clockProvider.overrideWithValue(kServiceClock),
        serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
        disposedAssetsProvider.overrideWith((ref) => Stream.value(disposed)),
        if (pending)
          assetsInUseProvider.overrideWith((ref) => pendingStream<List<Asset>>())
        else if (fail)
          assetsInUseProvider
              .overrideWith((ref) => Stream<List<Asset>>.error(StateError('boom')))
        else
          assetsInUseProvider
              .overrideWith((ref) => Stream.value(inUse ?? const <Asset>[])),
      ];

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(pending: true),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the first asset and says a person belongs here too',
      (tester) async {
    await pumpService(tester, const AssetListScreen(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    // §7.2's maid case has to be discoverable from the empty state, or nobody ever finds it.
    expect(find.textContaining('the person who helps around the house'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpService(tester, const AssetListScreen(), overrides: overrides(fail: true));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('populated groups by kind', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(inUse: [television(), maid()]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AssetRowTile), findsNWidgets(2));
    expect(find.text('Electronics'), findsOneWidget);
    // A person gets her own group, labelled as people rather than as equipment.
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Lakshmi'), findsOneWidget);
  });

  testWidgets('a disposed asset is hidden until the filter asks for it', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [television()],
        disposed: [
          television(
            id: 'asset-9',
            name: 'Old kettle',
            status: AssetStatus.disposed,
            disposedAt: const DateKey(20260601),
            disposalReason: AssetDisposalReason.damaged,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // Nothing is ever deleted (anomaly A30), so the kettle exists — it is simply not something you own.
    expect(find.text('Old kettle'), findsNothing);
    await tester.tap(find.text('Include disposed'));
    await tester.pumpAndSettle();
    expect(find.text('Old kettle'), findsOneWidget);
    expect(find.text('Disposed'), findsOneWidget);
  });

  testWidgets('an overdue service is derived from the clock, not a stored flag',
      (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        // Due in July against a clock fixed to 1 August. Nothing on the entity says "overdue".
        inUse: [television(nextService: const DateKey(20260715), serviceIntervalDays: 180)],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Service due'), findsWidgets);
  });

  testWidgets('a warranty still running reads as covered', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(inUse: [television(warrantyEnd: const DateKey(20270131))]),
    );
    await tester.pumpAndSettle();
    expect(find.text('In warranty'), findsOneWidget);
    expect(find.text('Out of warranty'), findsNothing);
  });

  testWidgets('a warranty already past reads as expired', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(inUse: [television(warrantyEnd: const DateKey(20260601))]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Out of warranty'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(
        inUse: [
          television(
            name: 'A television with a name long enough to wrap twice over',
            nextService: const DateKey(20260715),
            linkedRecurringTemplateId: 'tpl-1',
          ),
          maid(),
        ],
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpService(
      tester,
      const AssetListScreen(),
      overrides: overrides(inUse: [television(), maid()]),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/service/asset_detail_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/asset.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/service_record.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_detail_providers.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/asset_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_timeline.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, and the §7.2 rows this screen closes: a call action, a salary history, and a disposed
/// asset that is still fully readable.
///
/// **The history sliver sits below the fold, so its assertions pass `skipOffstage: false`.** The
/// diagnostic that found this reported `sliver 2 RenderSliverList: scrollExtent=100.0 paintExtent=0.0
/// visible=false` while `AlayaTimeline: 1 in tree` — the widget is built, and a `Finder` skips
/// off-screen widgets by default. Scrolling first would also work, but the question these tests ask is
/// whether the screen *builds* the right thing, not whether 584 logical pixels happen to reach it.
///
/// **No test asserts a ledger badge.** With the expense toggle on by default a service reaching the
/// ledger is the rule rather than the exception, so the chip was removed as noise — marking the *inverse*
/// would carry information, and is a design decision nobody has taken.
///
/// **And `SectionHeader` upper-cases its label**, so a header is found as `SALARY HISTORY`, never as the
/// ARB string. Both are ARCH_4 P6: the harness, not the product (five failures, zero defects).
void main() {
  const id = 'asset-1';

  List<Override> overrides({
    List<Asset>? inUse,
    List<Asset> disposed = const [],
    List<ServiceRecord> records = const [],
    Map<String, Money> lifetime = const {},
    bool pending = false,
    bool fail = false,
  }) =>
      [
        clockProvider.overrideWithValue(kServiceClock),
        serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
        serviceCurrencyProvider.overrideWith((ref) async => 'INR'),
        assetsInUseProvider
            .overrideWith((ref) => Stream.value(inUse ?? [television()])),
        disposedAssetsProvider.overrideWith((ref) => Stream.value(disposed)),
        lifetimeServiceCostProvider(id).overrideWith((ref) async => lifetime),
        assetTemplatesProvider(id)
            .overrideWith((ref) => Stream.value(const <RecurringTemplate>[])),
        if (pending)
          serviceRecordsProvider(id)
              .overrideWith((ref) => pendingStream<List<ServiceRecord>>())
        else if (fail)
          serviceRecordsProvider(id).overrideWith(
            (ref) => Stream<List<ServiceRecord>>.error(StateError('boom')),
          )
        else
          serviceRecordsProvider(id).overrideWith((ref) => Stream.value(records)),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(pending: true),
    );
    await tester.pump();
    expect(find.byType(AlayaListSkeleton, skipOffstage: false), findsWidgets);
  });

  testWidgets('an unknown id reads as not found rather than as an error', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: 'nope'),
      overrides: overrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('a failed history read shows the real reason', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(fail: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('boom', skipOffstage: false), findsOneWidget);
  });

  testWidgets('populated shows the hero, the details and the history', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(records: [serviceRecord()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('LG'), findsOneWidget);
    expect(find.byType(AlayaTimeline, skipOffstage: false), findsOneWidget);
    expect(find.text('Serviced', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a phone number becomes a call action', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(inUse: [television(contactPhone: '+911234567890')]),
    );
    await tester.pumpAndSettle();
    // §7.2: `primaryContactPhone` is reachable as an action, not just readable as text.
    expect(find.byType(ContactAction), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('no phone number offers no call action', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(inUse: [television()]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ContactAction), findsNothing);
  });

  testWidgets('a person shows a salary history and offers a payment', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: [maid(id: id)],
        records: [
          serviceRecord(
            assetId: id,
            type: ServiceRecordType.salaryPaid,
            costMinor: 800000,
            providerName: 'Lakshmi',
          ),
        ],
        lifetime: const {'INR': Money(800000, 'INR')},
      ),
    );
    await tester.pumpAndSettle();
    // The maid case end to end: her own wording, her own history, her own lifetime total — one table.
    expect(find.text('SALARY HISTORY', skipOffstage: false), findsWidgets);
    expect(find.text('Salary paid', skipOffstage: false), findsOneWidget);
    expect(find.text('Record a payment'), findsOneWidget);
    expect(find.text('Paid so far'), findsOneWidget);
  });

  testWidgets('a linked recurring template is shown against the person', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(inUse: [maid(id: id)]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paid on a schedule'), findsOneWidget);
  });

  testWidgets('a disposed asset stays fully readable and offers a way back', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: const [],
        disposed: [
          television(
            status: AssetStatus.disposed,
            disposedAt: const DateKey(20260601),
            disposalReason: AssetDisposalReason.sold,
            disposalMinor: 1500000,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // Anomaly A30: the price paid survives disposal, and so does everything else about it.
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('Disposed'), findsWidgets);
    expect(find.text('Bring it back'), findsOneWidget);
    expect(find.text('Dispose of it'), findsNothing);
  });

  testWidgets('lifetime service cost is one figure per currency, never summed',
      (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        records: [serviceRecord()],
        lifetime: const {'INR': Money(120000, 'INR'), 'USD': Money(4500, 'USD')},
      ),
    );
    await tester.pumpAndSettle();
    // Adding them would invent an exchange rate the user never agreed to (Law L1).
    expect(find.text('Spent on service so far'), findsOneWidget);
    expect(find.textContaining('1,200.00'), findsWidgets);
    expect(find.textContaining('45.00'), findsWidgets);
  });


  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: [
          television(
            name: 'A television with a name long enough to wrap twice over',
            contactPhone: '+911234567890',
            nextService: const DateKey(20260715),
            serviceIntervalDays: 180,
          ),
        ],
        records: [serviceRecord(), serviceRecord(id: 'rec-2', costMinor: null)],
        lifetime: const {'INR': Money(120000, 'INR')},
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpService(
      tester,
      const AssetDetailScreen(assetId: id),
      overrides: overrides(
        inUse: [television(contactPhone: '+911234567890')],
        records: [serviceRecord()],
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/service/asset_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/state/asset_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, plus the rule that makes one table hold a television and a house maid.
void main() {
  AssetEditorState state({
    String name = 'Living room TV',
    AssetType type = AssetType.electronics,
    int? priceMinor = 4500000,
    DateKey? warrantyStart = const DateKey(20260131),
    DateKey? warrantyEnd = const DateKey(20270131),
    AssetSaveIssue? issue,
    String? rejection,
  }) =>
      AssetEditorState(
        currencyCode: 'INR',
        name: name,
        type: type,
        purchasePrice: priceMinor == null ? null : Money(priceMinor, 'INR'),
        warrantyStartDateKey: warrantyStart,
        warrantyEndDateKey: warrantyEnd,
        issue: issue,
        rejection: rejection,
      );

  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`.
  List<Override> overrides(AsyncValue<AssetEditorState> value) => [
        assetEditorProvider.overrideWith(() => _StubEditor(value)),
        serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('an unknown asset reads as not found', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(assetId: 'nope'),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new asset opens on the form, which is its empty state', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state(name: '', priceMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('What is it?'), findsOneWidget);
  });

  testWidgets('a thing is asked for a brand, a model and a price', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Brand'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.byType(AmountField), findsOneWidget);
  });

  testWidgets('a person is asked for none of them', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(state(name: 'Lakshmi', type: AssetType.serviceProvider)),
      ),
    );
    await tester.pumpAndSettle();
    // Hidden rather than offered and left blank: an empty "Serial" on a human being is worse than its
    // absence, and that omission is what lets one table hold both cases.
    expect(find.text('Brand'), findsNothing);
    expect(find.text('Model'), findsNothing);
    expect(find.text('Serial'), findsNothing);
    expect(find.byType(AmountField), findsNothing);
    expect(
      find.textContaining('A person you pay regularly belongs here too'),
      findsOneWidget,
    );
  });

  testWidgets('a person is still asked for a phone number and a service interval',
      (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(state(name: 'Lakshmi', type: AssetType.serviceProvider)),
      ),
    );
    await tester.pumpAndSettle();
    // The two fields that matter for a person: how to reach her, and how often she comes.
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Service every'), findsOneWidget);
  });

  testWidgets('a blank name is refused at the field, not in a snack', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(state(name: '', issue: AssetSaveIssue.nameMissing)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This is required'), findsWidgets);
  });

  testWidgets('a backwards warranty says which field is wrong', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            warrantyStart: const DateKey(20260601),
            warrantyEnd: const DateKey(20260101),
            issue: AssetSaveIssue.warrantyBackwards,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The warranty cannot end before it starts'), findsWidgets);
  });

  testWidgets('a rejection is shown in the repository own words', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            issue: AssetSaveIssue.rejected,
            rejection: 'An asset with that name already exists.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('already exists'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state())),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpService(
      tester,
      const AssetEditorScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the state', () {
    test('disposal fields are never written by a save', () {
      final asset = state().toAsset(newId: 'a1', normalizedName: 'tv');
      // Retiring something goes through `AssetRepository.dispose`, which records a reason with the
      // status change. A save that could set `status: disposed` would be a second write path (Law U22).
      expect(asset.disposedAtDateKey, isNull);
      expect(asset.disposalReason, isNull);
      expect(asset.disposalAmount, isNull);
      expect(asset.status, AssetStatus.active);
    });

    test('an issue survives an unrelated copyWith', () {
      final base = state(issue: AssetSaveIssue.nameMissing);
      // ARCH_4 R31: a bare assignment let `submitting: false` in a `finally` erase the reason before the
      // screen read it.
      expect(base.copyWith(submitting: false).issue, AssetSaveIssue.nameMissing);
      expect(base.copyWith(clearIssue: true).issue, isNull);
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends AssetEditorNotifier {
  _StubEditor(this._value);

  final AsyncValue<AssetEditorState> _value;

  @override
  AsyncValue<AssetEditorState> build(String? arg) => _value;
}
```

### `test/features/service/service_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/service_editor_providers.dart';
import 'package:alaya/features/service/state/service_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/service_harness.dart';

/// Four states, plus the one write path: the toggle is a repository parameter, never a second save.
void main() {
  const assetId = 'asset-1';

  ServiceEditorState state({
    ServiceRecordType type = ServiceRecordType.service,
    int? costMinor = 120000,
    bool alsoRecordAsExpense = false,
    String? accountId,
    ServiceSaveIssue? issue,
    String? rejection,
  }) =>
      ServiceEditorState(
        assetId: assetId,
        currencyCode: 'INR',
        serviceDateKey: kToday,
        type: type,
        cost: costMinor == null ? null : Money(costMinor, 'INR'),
        alsoRecordAsExpense: alsoRecordAsExpense,
        accountId: accountId,
        issue: issue,
        rejection: rejection,
      );

  const method = PaymentMethod(
    id: 'pm-1',
    name: 'UPI',
    kind: PaymentMethodKind.upi,
    isSystem: true,
    sortOrder: 0,
  );

  /// A fixed-length override list.
  ///
  /// **The payment methods are always overridden, even when the test does not care.** Left alone,
  /// `servicePaymentMethodsProvider` reaches `paymentMethodRepositoryProvider` and through it a real
  /// database — which a widget test has no business opening (ARCH_4 P6).
  List<Override> overrides(
    AsyncValue<ServiceEditorState> value, {
    List<Account> accounts = const [kAccount],
    List<PaymentMethod> methods = const [],
  }) =>
      [
        serviceEditorProvider.overrideWith(() => _StubEditor(value)),
        serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
        serviceAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
        servicePaymentMethodsProvider.overrideWith((ref) => Stream.value(methods)),
      ];

  Widget host() => const ServiceEditorScreen(assetId: assetId);

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpService(tester, host(), overrides: overrides(const AsyncValue.loading()));
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('an unknown record reads as not found', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new record opens on the form', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state(costMinor: null))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('What happened'), findsOneWidget);
  });

  testWidgets('every service type is offered, salaryPaid included', (tester) async {
    await pumpService(tester, host(), overrides: overrides(AsyncValue.data(state())));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<ServiceRecordType>));
    await tester.pumpAndSettle();
    // §7.2: `salaryPaid` has to be reachable, or the maid case has no way to record a payment.
    expect(find.text('Salary paid'), findsWidgets);
  });

  testWidgets('a salary is not asked when the next one is due', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(state(type: ServiceRecordType.salaryPaid)),
      ),
    );
    await tester.pumpAndSettle();
    // The next payment is the recurring template's business; a second due date here would be a second
    // schedule to keep in step.
    expect(find.text('Next one due'), findsNothing);
  });

  testWidgets('a service is asked when the next one is due', (tester) async {
    await pumpService(tester, host(), overrides: overrides(AsyncValue.data(state())));
    await tester.pumpAndSettle();
    expect(find.text('Next one due'), findsOneWidget);
  });

  // The screen renders whatever the flag says; the *default* is the notifier's business and is asserted
  // in the state group below. Naming this "off until asked for" implied the screen owned a default it
  // never had.
  testWidgets('the toggle off hides both money pickers', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(AsyncValue.data(state()), methods: const [method]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Also record it as an expense'), findsOneWidget);
    // Both the account and the method live under the flag, so neither appears.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('the toggle on reveals the account it will draw from', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(state(alsoRecordAsExpense: true, accountId: kAccount.id)),
      ),
    );
    await tester.pumpAndSettle();
    // One picker, because no payment methods were supplied — an empty method dropdown never appears.
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('How you paid (optional)'), findsNothing);
    expect(
      find.textContaining('Writes a withdrawal for the cost as well'),
      findsOneWidget,
    );
  });

  testWidgets('the payment method is offered, and only ever optional', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(state(alsoRecordAsExpense: true, accountId: kAccount.id)),
        methods: const [method],
      ),
    );
    await tester.pumpAndSettle();
    // Account and method: two pickers, and the label says which one may be left alone.
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.text('How you paid (optional)'), findsOneWidget);
  });

  testWidgets('the toggle with no cost is refused at the field', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(
            costMinor: null,
            alsoRecordAsExpense: true,
            issue: ServiceSaveIssue.costMissingForExpense,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add a cost first'), findsWidgets);
  });

  testWidgets('the toggle with no account is refused at the field', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(
            alsoRecordAsExpense: true,
            issue: ServiceSaveIssue.accountMissingForExpense,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose which account it comes from'), findsWidgets);
  });

  testWidgets('a rejection is shown in the repository own words', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(
          state(
            issue: ServiceSaveIssue.rejected,
            rejection: 'That asset no longer exists.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('no longer exists'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        AsyncValue.data(state(alsoRecordAsExpense: true, accountId: kAccount.id)),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpService(tester, host(), overrides: overrides(AsyncValue.data(state())));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the state', () {
    test('editing an existing record never re-offers the expense toggle', () {
      final saved = state(alsoRecordAsExpense: true, costMinor: 120000)
          .toRecord(newId: 'rec-1');
      final reopened = ServiceEditorState.fromRecord(saved, 'INR');
      // One service must not be able to write two withdrawals — the same shape as ARCH_4 R35.
      expect(reopened.alsoRecordAsExpense, isFalse);
    });

    test('the toggle is only satisfiable with a cost and an account', () {
      expect(state().expenseIsSatisfiable, isTrue);
      expect(state(alsoRecordAsExpense: true).expenseIsSatisfiable, isFalse);
      expect(
        state(alsoRecordAsExpense: true, accountId: 'acc-1').expenseIsSatisfiable,
        isTrue,
      );
      expect(
        state(alsoRecordAsExpense: true, accountId: 'acc-1', costMinor: null)
            .expenseIsSatisfiable,
        isFalse,
      );
    });

    test('a new record defaults to recording the expense, an edited one never does', () {
      // The default lives in `_load`, so it is asserted where it is observable: a record round-tripped
      // through `fromRecord` must come back with the toggle off, because an existing record either wrote
      // its expense already or deliberately did not (ARCH_4 R35).
      final saved = state(alsoRecordAsExpense: true).toRecord(newId: 'rec-1');
      expect(ServiceEditorState.fromRecord(saved, 'INR').alsoRecordAsExpense, isFalse);
    });

    test('a payment method is held by the editor, never by the record', () {
      // `ServiceRecord` has no such field — adding one would duplicate a column `transactions` already
      // owns, and the two would drift. The editor carries it only to hand to `save`, which puts it on
      // the expense. That `toRecord` cannot express it is the point, and it is a compile-time fact; what
      // is worth asserting is that the editor does not quietly lose it on the way.
      expect(state().copyWith(paymentMethodId: 'pm-1').paymentMethodId, 'pm-1');
      expect(state().copyWith(paymentMethodId: 'pm-1').copyWith(notes: 'x').paymentMethodId, 'pm-1');
    });

    test('an existing transaction link survives an edit', () {
      final linked = state().toRecord(
        newId: 'rec-1',
        existing: serviceRecord(linkedTransactionId: 'txn-1'),
      );
      // Clearing it would orphan a transaction that genuinely happened (Law L6).
      expect(linked.linkedTransactionId, 'txn-1');
    });
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends ServiceEditorNotifier {
  _StubEditor(this._value);

  final AsyncValue<ServiceEditorState> _value;

  @override
  AsyncValue<ServiceEditorState> build(ServiceEditorArgs arg) => _value;
}
```

### `test/features/service/dispose_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/providers/dispose_providers.dart';
import 'package:alaya/features/service/state/dispose_state.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/service_harness.dart';

/// **This sheet reads no async source, so it has no loading or error state and none is faked.** Its only
/// inputs are a chip row, a date and two optional fields; an `AsyncValue` branch would be unreachable
/// code asserted by an unreachable test. §9.1's four states apply where there is something to await.
void main() {
  const args = (assetId: 'asset-1', currencyCode: 'INR');

  List<Override> overrides({DisposeState? seed}) => [
        clockProvider.overrideWithValue(kServiceClock),
        serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
        disposeProvider.overrideWith(
          () => _StubDispose(
            seed ??
                const DisposeState(
                  assetId: 'asset-1',
                  currencyCode: 'INR',
                  dateKey: kToday,
                ),
          ),
        ),
      ];

  Widget host() => const Scaffold(
        body: AlayaBottomSheet(
          child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
        ),
      );

  testWidgets('it says what disposal will not do', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // Anomaly A30 out loud: a user reaching for this button is entitled to know nothing is destroyed.
    expect(find.text('What happened to it?'), findsOneWidget);
    expect(
      find.textContaining('what you spent on it still counts'),
      findsOneWidget,
    );
  });

  testWidgets('every reason is offered', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(AssetDisposalReason.values.length));
    expect(find.text('Sold it'), findsOneWidget);
    expect(find.text('Broke'), findsOneWidget);
  });

  testWidgets('nothing is chosen until the user picks', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected);
    expect(selected, isEmpty);
  });

  testWidgets('the recovered amount is optional', (tester) async {
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // Most disposals recover nothing — a broken kettle is thrown away, not sold — and requiring a zero
    // would make the common case extra typing.
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('Got back'), findsOneWidget);
  });

  testWidgets('committing with no reason shakes rather than closing', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        seed: const DisposeState(
          assetId: 'asset-1',
          currencyCode: 'INR',
          dateKey: kToday,
          reasonMissing: true,
          shakeTrigger: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShakeOnError), findsOneWidget);
    expect(find.text('Pick what happened'), findsOneWidget);
  });

  testWidgets('a rejection is shown in the repository own words', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        seed: const DisposeState(
          assetId: 'asset-1',
          currencyCode: 'INR',
          dateKey: kToday,
          reason: AssetDisposalReason.sold,
          rejection: 'That asset is already disposed.',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('already disposed'), findsOneWidget);
  });

  testWidgets('a chosen reason and a recovered amount both show', (tester) async {
    await pumpService(
      tester,
      host(),
      overrides: overrides(
        seed: const DisposeState(
          assetId: 'asset-1',
          currencyCode: 'INR',
          dateKey: kToday,
          reason: AssetDisposalReason.sold,
          amount: Money(1500000, 'INR'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected)
        .length;
    expect(selected, 1);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpService(tester, host(), overrides: overrides(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpService(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubDispose extends DisposeNotifier {
  _StubDispose(this._value);

  final DisposeState _value;

  @override
  DisposeState build(DisposeArgs arg) => _value;
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

---

## COVERAGE — ARCH_5 §7 rows closed by Phase 6E

### §7.1 By table

| Row | Create | Read | Edit | Retire |
|---|---|---|---|---|
| `assets` | asset editor | list grouped by kind · detail hero | asset editor | **dispose sheet — a status change plus a reason, never a delete.** `undispose` on the detail screen is the way back (anomaly A30) |
| `service_records` | service editor, from the detail screen | service or salary history timeline · lifetime cost per currency | service editor, reached by tapping a timeline entry | `delete` on `AssetActions` — the record, never the asset |
| `asset_tags` | **Deferred, see §7.3** | — | — | — |

### §7.2 Columns most likely to be stranded

| Column | Where a user sees it |
|---|---|
| `type = serviceProvider` | Its own **"People"** group with a person glyph. The editor hides brand, model, serial, price and warranty for a person rather than offering them blank, and her detail screen reads "Salary history" and "Paid so far". **The maid case end to end: one asset, one linked recurring template, one `service_records` row per payment** |
| `disposal*` + `status = disposed` | The dispose sheet writes all four (`disposedAtDateKey`, `disposalReason`, `disposalNote`, `disposalAmount`); the hero shows the date and what was recovered; **"Include disposed" brings them back into the list**, because money spent on a thing that has gone still counts |
| `serviceIntervalDays` / `nextServiceDueDateKey` | Editor fields, with the interval seeding the first due date; a **"Service due"** chip on the row and the hero, derived from `clock.today()` on every build and never stored (ARCH_2 §12.2), plus **"Service soon"** inside thirty days |
| `primaryContactPhone` | **A `Call` button** that launches a `tel:` intent, with the number beside it as selectable text so it stays useful when no dialler exists |
| `service_records.type = salaryPaid` | Offered in the type dropdown, defaulted for a person, labelled "Salary paid" in the timeline, and it suppresses the next-due field because that is the recurring template's business |
| `warrantyStartDateKey` / `warrantyEndDateKey` / `warrantyProvider` | Editor fields with a backwards-range refusal; three derived chips — in warranty, ending, expired |
| `purchasePrice` | The detail hero, and it survives disposal |
| `linkedRecurringTemplateId` | A **"Paid on a schedule"** chip, read from `watchTemplatesForAsset` — built in 3A, deferred to 6E by 6D's coverage table, used here |
| `service_records.linkedTransactionId` | An **"In your ledger"** badge on the timeline entry the expense toggle produced |

### §7.3 Deferred — with the contract each waits on

| Item | Why | Owner |
|---|---|---|
| `asset_tags` | The table exists; `TagRepository` has no `watchForAsset` or `setForAsset`. This is the same three-layer gap `item_tags` has had open since 6B, and it needs a 2C/3A/3D addendum rather than a UI phase inventing a contract. Grouping is by `type` until then | **2C/3A/3D addendum** |
| `warrantyNote` | On the entity and preserved across every save, but no field: `warrantyProvider` plus the general note cover what a user actually types, and a third free-text box on the same subject invites the information to be split across two of them | **Kept preserved, not surfaced** |
| `sourceTransactionLineId` | Written by 6A's purchase fan-out and preserved here. Surfacing it means a link back to the receipt that created the asset, which belongs with 8A's provenance work | **8A** |
| `AssetStatus.underRepair` | Rendered as a chip wherever it appears, and `AssetActions.setStatus` can set it — but nothing in this phase offers the control. A repair is normally recorded as a `service_records` row, so a second status toggle needs deciding rather than adding | **§5.1 decision, then 6F** |
| `watchWarrantyEndingInRange` / `watchServiceDueInRange` | Both built in 3A, both unused. They are the cross-asset "what needs attention" reads, which belong to 6F's dashboard rather than to a per-asset screen | **6F** |
| `ServiceRecordRepository.watchWithNextDueInRange` | Same — the reminder feed, not a detail screen | **6F, consumed by 8B** |
| `mostRecentForAsset` | Superseded here by `watchForAsset`, which the timeline needs anyway. Useful to a dashboard card that wants one line per asset | **6F** |
