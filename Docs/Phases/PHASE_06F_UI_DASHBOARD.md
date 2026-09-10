# PHASE 6F — The Dashboard

> **Regenerated 2026-08-05 from the canonical tree.** Folds in the four post-6F fix rounds: the
> twenty-six-failure test pass, the insight-card host correction, and the two on-device UI passes — FAB
> action alignment, module-grid navigation, and the range-row split. Earlier revisions reintroduce defects
> listed in ARCH_6 §3 and the new shapes P15–P18 in `ARCH_AMENDMENTS_PRE_7A.md`.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B, 6C and 6D — carry
> **identical** content in every copy, so they may be applied in any order.

`BalanceService.totalInHome` is the only source of the headline figure, and this phase drops
`AccountRepository.watchTotalInHomeCurrency` — the interloper ARCH_4 §5.1 item 13 named. Nothing called
it; it was a second answer to a question with one right answer, and two headline sources is how a
dashboard starts disagreeing with itself.

`app_en.arb`, `routes.dart`, `app_router.dart`, `account_repository.dart` and
`account_repository_impl.dart` supersede their earlier versions; every other file is new.

## The scrim decision — ARCH_4 §5.1 item 19, settled

**No scrim. The decision is recorded here because this is the phase the FAB is first used for real.**

Item 19 left it open on the grounds that a widget in `Scaffold.floatingActionButton` cannot dim the
screen without an `OverlayEntry`, a `GlobalKey` and a global-rect calculation — roughly forty lines whose
only job is to darken. Four reasons not to:

1. **Legibility does not depend on it.** `AlayaExpandableFab` already renders each action row inside a
   `Material(color: surfaceContainerHighest)`. The labels sit on their own opaque surface, so nothing
   behind them competes.
2. **Dismissal is already solved.** `TapRegion` and `PopScope` close the menu on an outside tap and on
   back. Tap-to-close is the only *function* a scrim performs; the rest is signalling.
3. **Three actions is a menu, not a modal.** Nothing is inert while it is open — the dashboard behind it
   stays readable and scrollable, which is closer to right than pretending a short action list has taken
   over the screen.
4. **The cost is a new failure mode on the one control present on every screen.** An overlay anchored by
   `GlobalKey` breaks differently on rotation, on keyboard insets, and when the anchor is offstage.

**The decision lapses if either becomes true:** a later phase takes the FAB past four actions, or the
actions come to overlay a dense list where their labels sit directly on body text. Both change the
legibility argument, which is the only one carrying weight.

## The insight card's second side — an honest limit

The task asks for a switchable **calendar ↔ analytics** preview. The calendar side is built and real. The
analytics side is not, and cannot be: `CalendarAggregator` requires `CalendarRepository` and
`AnalyticsService` requires an `AnalyticsPort` adapter, and **neither has an implementation** — ARCH_4
§5.1 item 15 assigns them to 7A and 7B respectively.

Rather than reimplement either aggregation in the UI — which would leave 7A and 7B finding a competing
implementation to reconcile (ARCH_4 P7) — the analytics side renders an inline empty state naming what it
is waiting for. The switch, the stored preference and both sides' error handling are complete, so 7B
supplies data to a card that already exists.

The **upcoming** side is assembled from five repository reads that were built in Phase 3 and deferred to
this phase by 6D's and 6E's coverage tables: `RecurringRepository.watchDue`,
`AssetRepository.watchServiceDueInRange` and `watchWarrantyEndingInRange`,
`ServiceRecordRepository.watchWithNextDueInRange`, and `BatchRepository.watchExpiringInRange`. That is
what they exist for.

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

### `lib/domain/repositories/account_repository.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/account_balance.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// Reads and writes accounts, and reads the balances derived from them.
abstract interface class AccountRepository {
  /// Emits accounts that may be chosen in a picker — active and unarchived.
  Stream<List<Account>> watchSelectable();

  /// Emits every account, archived included.
  ///
  /// An archived account still counts toward totals and net worth; it has only left the pickers
  /// (ARCH_3 §4).
  Stream<List<Account>> watchAllIncludingArchived();

  /// Reads one account by id, soft-deleted ones included, so history can render a name.
  Future<Account?> byId(String id);

  /// Emits every account's balance, each in its own currency.
  ///
  /// Never sum these directly — accounts may hold different currencies (anomaly A34). Pair them with
  /// `Account.includeInNetWorth` and hand the result to `BalanceService.totalInHome`, which is the only
  /// sanctioned source of a headline figure.
  Stream<List<AccountBalance>> watchBalances();

  /// Emits one account's balance.
  Stream<AccountBalance?> watchBalanceOf(String accountId);


  /// Emits the transactions touching [accountId] on either side, newest first.
  Stream<List<Transaction>> watchLedgerFor(String accountId);

  /// Creates or updates an account.
  Future<Result<Account, Failure>> save(Account account);

  /// Archives or unarchives an account.
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  });

  /// Deletes an account.
  ///
  /// **Fails with a [BusinessRuleFailure] carrying rule `accountInUse` when any live transaction
  /// references it**, and the UI offers Archive instead — a hard block, not a warning
  /// (ARCH_3 §4.1). Deleting an account with history would silently remove money from every total
  /// that history contributed to.
  Future<Result<void, Failure>> delete(String id);
}
```

### `lib/data/repositories/account_repository_impl.dart`

```dart
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/account_dao.dart';
import 'package:alaya/data/daos/transaction_dao.dart';
import 'package:alaya/data/repositories/mappers/money_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/account_balance.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/account_repository.dart';
import 'package:alaya/domain/repositories/currency_repository.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// `AccountRepository` backed by `AccountDao`.
final class AccountRepositoryImpl implements AccountRepository {
  /// Creates the repository over [dao], using [transactionDao] to resolve a transaction's line
  /// mapper dependency for [watchLedgerFor], [currency] for net-worth conversion, [settings] for
  /// the home currency code, and [clock] for write timestamps.
  const AccountRepositoryImpl(
    this._dao,
    this._transactionDao,
    this._currency,
    this._settings,
    this._clock,
  );

  final AccountDao _dao;
  final TransactionDao _transactionDao;
  final CurrencyRepository _currency;
  final SettingsRepository _settings;
  final Clock _clock;

  @override
  Stream<List<Account>> watchSelectable() =>
      _dao.watchSelectable().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<Account>> watchAllIncludingArchived() =>
      _dao.watchAllIncludingArchived().map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<Account?> byId(String id) async => (await _dao.byIdIncludingDeleted(id))?.toEntity();

  @override
  Stream<List<AccountBalance>> watchBalances() {
    return _dao.watchBalances().map(
          (rows) => rows
              .map(
                (r) => AccountBalance(
                  accountId: r.accountId,
                  balance: Money(r.balanceMinor, r.currencyCode),
                ),
              )
              .toList(),
        );
  }

  @override
  Stream<AccountBalance?> watchBalanceOf(String accountId) {
    return _dao.watchBalanceOf(accountId).map(
          (row) => row == null
              ? null
              : AccountBalance(
                  accountId: row.accountId,
                  balance: Money(row.balanceMinor, row.currencyCode),
                ),
        );
  }


  @override
  Stream<List<Transaction>> watchLedgerFor(String accountId) {
    return _transactionDao
        .watchByAccount(accountId)
        .map((rows) => rows.map((r) => r.toEntity()).toList());
  }

  @override
  Future<Result<Account, Failure>> save(Account account) async {
    final existing = await _dao.byIdIncludingDeleted(account.id);

    if (existing == null) {
      final duplicate = await _dao.byNormalizedName(account.normalizedName);
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure('An account named "${account.name}" already exists.'),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _dao.upsert(
      accountToCompanion(account, createdAt: stamps.createdAt, updatedAt: stamps.updatedAt),
    );
    return Result.ok(account);
  }

  @override
  Future<Result<void, Failure>> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    await _dao.setArchived(id: id, isArchived: isArchived, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> delete(String id) async {
    final inUseCount = await _dao.activeTransactionCount(id);
    if (inUseCount > 0) {
      return Result.failure(
        BusinessRuleFailure(
          'This account has $inUseCount transaction(s) and cannot be deleted. Archive it instead.',
          rule: 'accountInUse',
        ),
      );
    }
    await _dao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }
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

### `lib/shared/widgets/module_tile.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A navigation tile carrying a live number (ARCH_5 §8 — the one shared addition Phase 6F makes).
///
/// **The number is the point.** A grid of labelled icons is decoration: it tells the user what the app
/// contains, which they already know, and gives no reason to tap one tile rather than another. A count
/// that moves — three items running low, two bills due — is the difference between a menu and a
/// dashboard.
///
/// The count arrives as already-localised text rather than an `int`, because "nothing tracked" and
/// "3 running low" are different sentences and only the ARB knows which to use.
///
/// ## Requires a bounded height, and never overflows inside one
///
/// A grid cell is a fixed box, and both of this tile's labels grow with text scale while the box does
/// not. The first version put a `MainAxisSize.max` column of freely-wrapping `Text`s inside that box and
/// overflowed by 22px at scale 1 and 250px at scale 2 — the P1 shape, one layer in: not a starved
/// `Expanded` sibling but a starved `Column` (Law U2, U21).
///
/// Both `Text`s are therefore `Flexible` and ellipsise. **Ellipsis is legitimate here precisely because
/// neither string is a `Money` or a `Qty`.** U7 forbids truncating a figure because half a number reads
/// as a smaller number; a truncated sentence still reads as a sentence. `ModuleGrid` sizes its cells from
/// the current text scaler, so the ellipsis is a floor the layout rarely reaches rather than the normal
/// case — but it is the floor, and the tile holds it on its own.
///
/// Given an *unbounded* height the flex assertion fires and names the caller, which is the same contract
/// `ScrollSafeCenter` carries. That is deliberate: a tile with nothing bounding it has no shape to
/// defend.
class ModuleTile extends StatelessWidget {
  /// Creates a tile.
  const ModuleTile({
    required this.label,
    required this.icon,
    required this.detail,
    required this.onTap,
    this.tone,
    this.semanticsLabel,
    super.key,
  });

  /// What the module is called — the drawer's own wording, so the tile names somewhere real.
  final String label;

  /// Its glyph.
  final IconData icon;

  /// The live number, already localised and pluralised.
  final String detail;

  /// Opens the module.
  final VoidCallback onTap;

  /// Colours the glyph when the count is worth noticing; muted when it is not.
  final Color? tone;

  /// Overrides the composed semantics label, which otherwise reads label then detail.
  final String? semanticsLabel;

  /// How many lines each of the two labels may take before it truncates.
  ///
  /// Public because `ModuleGrid` reserves exactly this many when it measures a cell. A tile that budgets
  /// two lines inside a cell sized for one is the overflow all over again, so the two read one number.
  static const int maxLabelLines = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    return Semantics(
      button: true,
      label: semanticsLabel ?? '$label. $detail',
      excludeSemantics: true,
      child: Material(
        color: semantic.surfaceSunken,
        borderRadius: AlayaRadii.borderMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget * 2),
            child: Padding(
              padding: const EdgeInsets.all(AlayaSpacing.sm),
              // A `Column`, not a `Row`: the label and the count both grow with text scale, and side by
              // side one of them starves at 320dp (Law U21).
              //
              // `min` rather than `max`, and `start` rather than `spaceBetween`: the flexible children
              // already absorb whatever room the cell has, so `spaceBetween` had nothing left to
              // distribute while `max` forced the column to fill a box its content could exceed.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: AlayaIconSize.lg, color: tone ?? semantic.muted),
                  const SizedBox(height: AlayaSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
                      maxLines: maxLabelLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Flexible(
                    child: Text(
                      detail,
                      style: AlayaTypography.caption.copyWith(color: tone ?? semantic.muted),
                      maxLines: maxLabelLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/dashboard/state/insight_side.dart`

```dart
/// Which face of the dashboard's insight card is showing.
///
/// Stored in `app_settings` through `SettingsRepository.writeValue`, so the choice survives a restart —
/// a switch that resets every launch is a switch the user has to keep re-making.
enum InsightSide {
  /// Bills, services, warranties and batches falling due soon.
  upcoming,

  /// Spending breakdowns. Waiting on Phase 7B's analytics adapter.
  spending;

  /// The `app_settings` key this preference is stored under.
  static const String settingsKey = 'dashboard.insightSide';

  /// Parses a stored value, defaulting to [upcoming] for anything unrecognised.
  ///
  /// Defaults rather than throws: a settings row is user data and a future version may write a value this
  /// one has never heard of, which is not a reason to fail a dashboard.
  static InsightSide parse(String? stored) => switch (stored) {
        'spending' => InsightSide.spending,
        _ => InsightSide.upcoming,
      };

  /// The value written back to `app_settings`.
  String get stored => name;
}
```

### `lib/features/dashboard/providers/funds_providers.dart`

```dart
/// View-model state for the funds header (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/account_balance.dart';
import 'package:alaya/domain/services/balance_service.dart';

/// The home currency every figure on the dashboard is expressed in.
final dashboardCurrencyProvider = FutureProvider<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR',
);

/// The home currency's decimal precision (ARCH_1 §4.1).
final dashboardDigitsProvider = FutureProvider<int>((ref) async {
  final code = await ref.watch(dashboardCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// Every account, so a balance can be paired with its net-worth flag.
final dashboardAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAllIncludingArchived(),
);

/// Per-account balances, straight from `v_account_ledger`.
final dashboardBalancesProvider = StreamProvider<List<AccountBalance>>(
  (ref) => ref.watch(accountRepositoryProvider).watchBalances(),
);

/// Total available funds — the one headline figure on the dashboard.
///
/// **`BalanceService.totalInHome` and nothing else.** `AccountRepository.watchTotalInHomeCurrency` was a
/// second answer to the same question and is dropped by this phase (ARCH_4 §5.1 item 13); two sources is
/// how a dashboard starts disagreeing with itself.
///
/// **A self-transfer nets to zero here by construction.** The balances come from `v_account_ledger`,
/// which counts a transfer once against each side — so moving money between your own accounts leaves the
/// sum untouched. If this figure ever moves on a transfer, the view is being bypassed, not the maths.
///
/// **Unconvertible balances are excluded, never guessed at** (anomaly A34). `NetWorth` carries the count
/// so the header can say so rather than quietly under-reporting.
final totalFundsProvider = FutureProvider<NetWorth>((ref) async {
  final accounts = await ref.watch(dashboardAccountsProvider.future);
  final balances = await ref.watch(dashboardBalancesProvider.future);
  final code = await ref.watch(dashboardCurrencyProvider.future);

  final flags = <String, bool>{
    for (final account in accounts) account.id: account.includeInNetWorth,
  };
  return ref.watch(balanceServiceProvider).totalInHome(
        balances: [
          for (final balance in balances)
            AccountBalanceInput(
              accountId: balance.accountId,
              balance: balance.balance,
              // An account excluded from net worth is excluded here too. A loan you are servicing is
              // real money owed and belongs in the ledger, but it is not money you can spend today.
              includeInNetWorth: flags[balance.accountId] ?? true,
            ),
        ],
        rates: ref.watch(currencyRateServiceProvider),
        homeCurrencyCode: code,
        asOf: ref.watch(clockProvider).today(),
      );
});
```

### `lib/features/dashboard/providers/range_providers.dart`

```dart
/// View-model state for the dashboard's range rows (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/date_range_service.dart';

/// Money in and money out over one labelled window, with what could not be converted.
class RangeTotals {
  /// Creates a set of totals.
  const RangeTotals({
    required this.moneyIn,
    required this.moneyOut,
    required this.excludedCount,
  });

  /// Deposits, converted into the home currency.
  final Money moneyIn;

  /// Withdrawals, converted into the home currency.
  final Money moneyOut;

  /// How many transactions held a currency no rate could convert.
  ///
  /// Excluded from both figures rather than summed at face value (anomaly A34), and surfaced so the row
  /// can say the total is partial instead of quietly under-reporting.
  final int excludedCount;

  /// Whether the window held nothing at all, which reads differently from holding zero.
  bool get isEmpty => moneyIn.isZero && moneyOut.isZero && excludedCount == 0;
}

/// The last thirty days, ending today.
///
/// **Always labelled with what it means** (anomaly A33). A row reading "last month" is ambiguous between
/// the previous calendar month and the preceding thirty days, and a user cannot tell which they are
/// looking at from the number alone — so the label states the window and the code computes exactly that.
final last30Provider = Provider<DateRange>((ref) {
  final today = ref.watch(clockProvider).today();
  return (from: today.addDays(-29), to: today);
});

/// Everything on record, from the earliest date this app treats as real.
final allTimeProvider = Provider<DateRange>((ref) {
  return (from: DateRangeService.earliest, to: ref.watch(clockProvider).today());
});

/// Totals over one window.
///
/// Converted through `RateTable` once for the whole window rather than per transaction, because
/// `CurrencyRateService.toHome` reloads the table on every call and a year of transactions would reload it
/// a thousand times.
final rangeTotalsProvider =
    FutureProvider.autoDispose.family<RangeTotals, DateRange>((ref, range) async {
  final code = await ref.watch(dashboardCurrencyProvider.future);
  final rows = await ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: range.from, to: range.to)
      .first;
  final table = await ref.watch(currencyRateServiceProvider).table();

  var moneyIn = Money.zero(code);
  var moneyOut = Money.zero(code);
  var excluded = 0;
  for (final transaction in rows) {
    // **Transfers and adjustments are neither in nor out.** A transfer moves money between the user's own
    // accounts, so counting it as both would double every figure and net to a lie. An adjustment is a
    // bookkeeping correction — presenting one as income would tell the user they earned their own
    // reconciliation. The rows are labelled "In" and "Out" and must contain only what those words mean
    // (anomaly A33).
    if (transaction.kind == TransactionKind.transfer ||
        transaction.kind == TransactionKind.adjustmentIncrease ||
        transaction.kind == TransactionKind.adjustmentDecrease) {
      continue;
    }

    final converted = table.convert(
      amount: transaction.originalAmount,
      toCurrencyCode: code,
      on: transaction.dateKey,
    );
    final value = converted.converted;
    if (value == null) {
      excluded++;
      continue;
    }
    switch (transaction.kind) {
      case TransactionKind.deposit:
        moneyIn = moneyIn + value;
      case TransactionKind.withdrawal:
        moneyOut = moneyOut + value;
      case TransactionKind.transfer:
      case TransactionKind.adjustmentIncrease:
      case TransactionKind.adjustmentDecrease:
        break;
    }
  }
  return RangeTotals(moneyIn: moneyIn, moneyOut: moneyOut, excludedCount: excluded);
});
```

### `lib/features/dashboard/providers/insight_providers.dart`

```dart
/// View-model state for the dashboard's insight card (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';

/// One thing that needs attention, and when.
class UpcomingEntry {
  /// Creates an entry.
  const UpcomingEntry({
    required this.kind,
    required this.title,
    required this.dueDateKey,
    this.route,
  });

  /// Which sort of obligation this is, which decides its wording and glyph.
  final UpcomingKind kind;

  /// What it is called.
  final String title;

  /// When it falls due.
  final DateKey dueDateKey;

  /// Where tapping it goes, when there is somewhere useful.
  final String? route;

  /// Whether it is already past its date, derived from the clock and never stored (ARCH_2 §12.2).
  bool isOverdue(DateKey today) => dueDateKey < today;
}

/// The four sorts of thing the upcoming side collects.
enum UpcomingKind {
  /// A recurring occurrence that is due.
  bill,

  /// An asset whose service interval has come round.
  service,

  /// A warranty about to lapse.
  warranty,

  /// A batch at or near its expiry date.
  batch,
}

/// How far ahead the upcoming side looks.
///
/// A fortnight: long enough that a monthly bill appears before it is late, short enough that the card
/// stays a shortlist rather than a second ledger.
const int upcomingHorizonDays = 14;

/// Which face of the insight card is showing, restored from `app_settings`.
final insightSideProvider = NotifierProvider<InsightSideNotifier, InsightSide>(
  InsightSideNotifier.new,
);

/// Holds and persists the insight card's side.
class InsightSideNotifier extends Notifier<InsightSide> {
  @override
  InsightSide build() {
    unawaited(_restore());
    return InsightSide.upcoming;
  }

  Future<void> _restore() async {
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readValue(InsightSide.settingsKey);
    final restored = InsightSide.parse(stored);
    if (restored != state) state = restored;
  }

  /// Shows [side] and remembers it.
  ///
  /// The write is not awaited: the card should flip on the frame the user taps, and a settings row that
  /// lands a millisecond later changes nothing they can see.
  void show(InsightSide side) {
    state = side;
    unawaited(
      ref
          .read(settingsRepositoryProvider)
          .writeValue(
            key: InsightSide.settingsKey,
            value: side.stored,
            // `app_settings` stores its own type alongside the value, and every row this app writes is a
            // string. An enum's name is a string; declaring it anything else would be a claim the reader
            // has to unpick.
            valueType: 'string',
          ),
    );
  }
}

/// Everything falling due inside [upcomingHorizonDays], soonest first.
///
/// **Now `CalendarAggregator`, which is what the previous version said it could not be.** It read four
/// repositories directly because `CalendarRepository` had no implementation until Phase 7A
/// (ARCH_4 §5.1 item 15); it does now, so the stand-in retires rather than drifting alongside the real
/// engine. Three things were wrong with it, and none were visible from here:
///
/// 1. Its own doc comment claimed five reads including `ServiceRecordRepository.watchWithNextDueInRange`.
///    The body performed four and never called it, so a service due recorded against a **service record**
///    rather than against the asset never reached this card (ARCH_6 P18 — a comment asserting what the
///    code does not do).
/// 2. Batches were titled `batch.id`, so an expiring item showed a **UUID** where the calendar, whose
///    view `COALESCE`s the item name, showed "Yoghurt".
/// 3. Severity was nobody's job here. `CalendarAggregator` applies ARCH_3 §6's per-type thresholds
///    against the injected clock, so "needs attention" now means the same thing on both screens.
///
/// **Transactions and shopping targets are filtered out, deliberately.** Every kind this card carries is
/// consequential if ignored: a bill goes late, a service lapses, a warranty dies, food spoils. A past
/// transaction is not an obligation, and a shopping target is self-imposed — missing it costs nothing,
/// and a weekly shop would land in almost every fortnight, so it would be the one row always present and
/// therefore the one carrying no signal. The calendar is where plans belong; this card is for obligations.
final upcomingProvider = FutureProvider.autoDispose<List<UpcomingEntry>>((
  ref,
) async {
  // The same materialisation the calendar waits on. Without it this card cannot show a bill that is
  // not already overdue, which was true of the version it replaced too.
  await ref.watch(recurringHorizonProvider.future);

  final today = ref.watch(clockProvider).today();
  final horizon = today.addDays(upcomingHorizonDays);

  // A year back, not `DateRangeFloor.past`. Overdue still matters more than upcoming, but a floor in
  // 1900 makes the range nominally bounded and practically a full scan of seven tables — and nothing
  // outstanding for over a year is going to be actioned from a fortnight's shortlist.
  final days = await ref
      .watch(calendarAggregatorProvider)
      .watchDays(from: today.addDays(-overdueLookbackDays), to: horizon, today: today)
      .first;

  final entries = <UpcomingEntry>[];
  for (final day in days) {
    for (final event in day.events) {
      final kind = _kindOf(event.type);
      if (kind == null) continue;
      entries.add(
        UpcomingEntry(
          kind: kind,
          title: event.title,
          dueDateKey: event.dateKey,
        ),
      );
    }
  }

  entries.sort((a, b) => a.dueDateKey.compareTo(b.dueDateKey));
  return entries;
});

/// The [UpcomingKind] for [type], or null where the type is not an obligation.
UpcomingKind? _kindOf(CalendarEventType type) => switch (type) {
      CalendarEventType.recurringDue => UpcomingKind.bill,
      CalendarEventType.serviceDue => UpcomingKind.service,
      CalendarEventType.warrantyEnd => UpcomingKind.warranty,
      CalendarEventType.batchExpiry => UpcomingKind.batch,
      CalendarEventType.transaction => null,
      CalendarEventType.shoppingTarget => null,
    };

/// How far back the card reaches for things still outstanding.
const int overdueLookbackDays = 365;

/// The lower bound for a read that should include things already overdue.
///
/// Overdue matters more than upcoming, so the floor reaches back rather than starting at today — a
/// service three weeks late must not fall off the card for being too late.
abstract final class DateRangeFloor {
  /// Far enough back to catch anything still outstanding.
  static final DateKey past = DateKey.fromYmd(1900, 1, 1);
}
```
### `lib/features/dashboard/providers/module_providers.dart`

```dart
/// The live numbers on the dashboard's navigation tiles (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/inventory/providers/inventory_list_providers.dart';

/// How many transactions were recorded this calendar month.
///
/// The month rather than a rolling window, because the tile's wording says "this month" and a tile whose
/// number does not match its label is worse than no number (anomaly A33).
final expenseCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final today = ref.watch(clockProvider).today();
  final month = ref.watch(dateRangeServiceProvider).wholeMonthOf(today);
  final rows = await ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: month.from, to: month.to)
      .first;
  return rows.length;
});

/// How many items sit below their low-stock level.
///
/// **Phase 6B's provider, not a second one.** `lowStockCountProvider` already answers exactly this and is
/// derived from the same stream the inventory list watches — a dashboard-local reimplementation would be a
/// second definition of "low" to keep in step (ARCH_4 P7).
final inventoryCountProvider = Provider.autoDispose<int>(
  (ref) => ref.watch(lowStockCountProvider),
);

/// How many things are still to buy on the default list.
final shoppingCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final repository = ref.watch(shoppingRepositoryProvider);
  final list = await repository.watchDefaultList().first;
  if (list == null) return 0;
  final entries = await repository.watchUncheckedEntries(list.id).first;
  final today = ref.watch(clockProvider).today();
  // The entity decides what counts: a snoozed suggestion and a bought entry are both unchecked and
  // neither is something to buy (see `ShoppingEntry.isOutstandingAsOf`).
  return entries.where((entry) => entry.isOutstandingAsOf(today)).length;
});

/// How many recurring obligations are outstanding.
final recurringCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final due = await ref.watch(recurringRepositoryProvider).watchDue().first;
  return due.where((row) => row.occurrence != null).length;
});

/// How many assets need a service or are losing their warranty.
///
/// Reuses the dashboard's own upcoming list rather than re-querying, so the tile and the insight card can
/// never disagree about what needs attention.
final serviceCountProvider = Provider.autoDispose<int>((ref) {
  final upcoming = ref.watch(upcomingProvider).valueOrNull ?? const <UpcomingEntry>[];
  return upcoming
      .where(
        (entry) =>
            entry.kind == UpcomingKind.service || entry.kind == UpcomingKind.warranty,
      )
      .length;
});
```

### `lib/features/dashboard/presentation/widgets/funds_header.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Total available funds — the one `displayAmount` on the dashboard (ARCH_5 §3 archetype F).
///
/// **One headline, because two headline numbers is no headline number.** Every other figure on this
/// screen is `AmountSize.small` or smaller, and that hierarchy is the whole reason a glance works.
///
/// **The figure comes from `BalanceService.totalInHome` and nothing else.** A self-transfer cannot move
/// it: the balances behind it come from `v_account_ledger`, which counts a transfer once against each
/// side. If this number ever changes when money moves between the user's own accounts, the view is being
/// bypassed rather than the arithmetic being wrong.
///
/// **What cannot be converted is excluded and said out loud** (anomaly A34). Summing a dirham balance
/// into a rupee total at face value would be a wrong number presented as a right one; a smaller number
/// with a chip beside it is honest, and the chip explains itself rather than just counting.
class FundsHeader extends ConsumerWidget {
  /// Creates the header.
  const FundsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(totalFundsProvider);
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: async.when(
        // Its own skeleton rather than the screen's: a slow rate table must not blank the range rows or
        // the module grid beneath it (ARCH_5 §3 archetype F).
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.fundsAvailable,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            Text(
              strings.loadingDashboard,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            ),
          ],
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(totalFundsProvider),
        ),
        data: (worth) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.fundsAvailable,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            AmountText(
              worth.total,
              // The one `displayAmount` on the screen (ARCH_5 §2.3). Omitting this fell back to
              // `AmountSize.medium` — the ledger-row size — which left the dashboard with no headline
              // at all while every doc comment claimed it had one.
              size: AmountSize.display,
              showSign: false,
              decimalDigits: digits,
            ),
            if (!worth.isComplete || worth.isApproximate) ...[
              const SizedBox(height: AlayaSpacing.sm),
              Wrap(
                spacing: AlayaSpacing.xs,
                runSpacing: AlayaSpacing.xxs,
                children: [
                  if (!worth.isComplete)
                    StatusChip(
                      label: strings.fundsUnconverted(worth.unconvertedCount),
                      tone: StatusTone.warning,
                    ),
                  if (worth.isApproximate)
                    StatusChip(label: strings.fundsApproximate, tone: StatusTone.info),
                ],
              ),
              if (!worth.isComplete) ...[
                const SizedBox(height: AlayaSpacing.xs),
                Text(
                  strings.fundsWhyExcluded,
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
```

### `lib/features/dashboard/presentation/widgets/range_row.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Money in and money out over one window, always labelled with what the window means.
///
/// **The label is not decoration** (anomaly A33). "Last month" is ambiguous between the previous calendar
/// month and the preceding thirty days, and no user can tell which they are looking at from the figures
/// alone — so the row states its window in words and the provider computes exactly that window. A range
/// row without its label is a number with no meaning.
///
/// **Transfers are not counted.** Money moving between the user's own accounts is neither income nor
/// expenditure, and including it would double both figures and net to a lie.
///
/// ## Two cells, split by a rule, rather than a sentence of four words
///
/// The first version laid the two legs out as a `Wrap` of `label figure  label figure`, which reads as
/// prose and makes the eye parse before it can compare. In and out are a **pair** — the whole reason to
/// show them together is that one is measured against the other — so they get equal halves and a hairline
/// between them, and the caption sits above its figure rather than beside it. That halves the row's width
/// and lets the two windows stack tightly enough to read as one block.
///
/// **The figures scale down rather than truncate.** U7 forbids clipping a `Money`, because half a number
/// reads as a smaller number — but a fixed half-width cell at a doubled text scale cannot always hold one.
/// `BoxFit.scaleDown` keeps every digit and gives up type-scale fidelity instead, which is the correct
/// trade: a figure one step smaller than its token is still true, and an overflowed one is a crash.
class RangeRow extends ConsumerWidget {
  /// Creates a row over [range], described by [label].
  const RangeRow({required this.label, required this.range, super.key});

  /// What this window means, in words.
  final String label;

  /// The window itself.
  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(rangeTotalsProvider(range));
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AlayaTypography.label.copyWith(color: semantic.muted),
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          async.when(
            loading: () => Text(
              strings.loadingDashboard,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            // Inline, and it keeps the label: a failed conversion must not take the window's meaning down
            // with it, and the reader still needs to know which row broke.
            error: (error, stack) => Text(
              error.toString(),
              style: AlayaTypography.caption.copyWith(color: semantic.danger),
            ),
            data: (totals) => totals.isEmpty
                ? Text(
                    strings.rangeNothingYet,
                    style: AlayaTypography.body.copyWith(color: semantic.muted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Split(
                        left: _Leg(
                          label: strings.rangeMoneyIn,
                          amount: totals.moneyIn,
                          kind: TransactionKind.deposit,
                          digits: digits,
                        ),
                        right: _Leg(
                          label: strings.rangeMoneyOut,
                          amount: totals.moneyOut,
                          kind: TransactionKind.withdrawal,
                          digits: digits,
                        ),
                      ),
                      // Below the pair, not inside it. The chip is a caveat about the figures, and a
                      // caveat sitting in one of the two cells looks like it belongs to that cell alone.
                      if (totals.excludedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: AlayaSpacing.xs),
                          child: StatusChip(
                            label: strings.rangeExcluded(totals.excludedCount),
                            tone: StatusTone.warning,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Two equal cells with a hairline between them.
class _Split extends StatelessWidget {
  const _Split({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // `IntrinsicHeight` so the rule can stretch to the taller cell. Without it, `stretch` asks for the
    // incoming maxHeight — unbounded inside the dashboard's sliver — and the layout throws.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Equal halves, so the two figures start at predictable places and the eye can compare them
          // without measuring. Neither cell can starve the other (Law U21) because neither is intrinsic.
          Expanded(child: left),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
            child: SizedBox(
              width: 1,
              // `outlineVariant` is Material 3's divider role. Using it rather than a muted text colour
              // at low opacity keeps the rule at divider weight across every palette preset.
              child: ColoredBox(color: theme.colorScheme.outlineVariant),
            ),
          ),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// One side of the split: what it is, then how much.
class _Leg extends StatelessWidget {
  const _Leg({
    required this.label,
    required this.amount,
    required this.kind,
    required this.digits,
  });

  final String label;
  final Money amount;
  final TransactionKind kind;
  final int digits;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        // Left-aligned as it shrinks, so both figures keep a common left edge whatever their length.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: AmountText(
            amount,
            size: AmountSize.small,
            showSign: false,
            decimalDigits: digits,
            kind: kind,
          ),
        ),
      ],
    );
  }
}
```
### `lib/features/dashboard/presentation/widgets/insight_card.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// A switchable card: what is coming up, or where the money went.
///
/// **Each side owns its own loading, empty and error state, inline.** That is the whole reason this is one
/// card with a switch rather than two cards: a failing rate table or an unreachable engine must cost the
/// user this card and nothing else. One failing card never blanks the dashboard (ARCH_5 §3 archetype F).
///
/// **The spending side has no data, and says so rather than pretending.** `AnalyticsService` has no
/// `AnalyticsPort` adapter and `CalendarAggregator` has no `CalendarRepository`, both assigned to Phase 7B
/// and 7A (ARCH_4 §5.1 item 15). Aggregating spending here instead would leave 7B a competing
/// implementation to reconcile, so the side is built, switchable and honest — and 7B supplies data to a
/// card that already exists.
///
/// The choice is stored in `app_settings`, so it survives a restart.
class InsightCard extends ConsumerWidget {
  /// Creates the card.
  const InsightCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final side = ref.watch(insightSideProvider);
    final notifier = ref.read(insightSideProvider.notifier);

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: strings.insightSwitchLabel,
            child: SegmentedButton<InsightSide>(
              segments: [
                ButtonSegment(
                  value: InsightSide.upcoming,
                  label: Text(strings.insightUpcoming),
                ),
                ButtonSegment(
                  value: InsightSide.spending,
                  label: Text(strings.insightSpending),
                ),
              ],
              selected: {side},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => notifier.show(selection.first),
            ),
          ),
          const SizedBox(height: AlayaSpacing.md),
          switch (side) {
            InsightSide.upcoming => const _Upcoming(),
            InsightSide.spending => const _Spending(),
          },
        ],
      ),
    );
  }
}

class _Upcoming extends ConsumerWidget {
  const _Upcoming();

  static IconData _glyph(UpcomingKind kind) => switch (kind) {
        UpcomingKind.bill => Icons.event_repeat,
        UpcomingKind.service => Icons.build_outlined,
        UpcomingKind.warranty => Icons.verified_outlined,
        UpcomingKind.batch => Icons.inventory_2_outlined,
      };

  static String _label(AlayaStrings strings, UpcomingKind kind) => switch (kind) {
        UpcomingKind.bill => strings.insightBillDue,
        UpcomingKind.service => strings.insightServiceDue,
        UpcomingKind.warranty => strings.insightWarrantyEnding,
        UpcomingKind.batch => strings.insightBatchExpiring,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final async = ref.watch(upcomingProvider);
    final today = ref.watch(clockProvider).today();

    return async.when(
      loading: () => Text(
        strings.loadingDashboard,
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      error: (error, stack) => Text(
        error.toString(),
        style: AlayaTypography.caption.copyWith(color: semantic.danger),
      ),
      data: (entries) => entries.isEmpty
          ? Text(
              strings.insightNothingUpcoming,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Capped, not scrolled: a card inside a `CustomScrollView` that scrolls on its own is two
                // scroll gestures competing for the same drag. Five is a shortlist; the modules behind it
                // hold the rest.
                for (final entry in entries.take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _glyph(entry.kind),
                          size: AlayaIconSize.md,
                          color: entry.isOverdue(today) ? semantic.danger : semantic.muted,
                        ),
                        const SizedBox(width: AlayaSpacing.sm),
                        Expanded(
                          // The title, its sort and its date all grow with text scale, so they wrap
                          // among themselves rather than starving the icon's neighbour (Law U21).
                          child: Wrap(
                            spacing: AlayaSpacing.xs,
                            runSpacing: AlayaSpacing.xxs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                entry.title,
                                style: AlayaTypography.body
                                    .copyWith(color: theme.colorScheme.onSurface),
                              ),
                              Text(
                                _label(strings, entry.kind),
                                style: AlayaTypography.caption
                                    .copyWith(color: semantic.muted),
                              ),
                              DateText(
                                entry.dueDateKey,
                                style: DateTextStyle.dayMonth,
                                muted: true,
                              ),
                              if (entry.isOverdue(today))
                                StatusChip(
                                  label: strings.recurringOverdue,
                                  tone: StatusTone.danger,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Spending extends StatelessWidget {
  const _Spending();

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    // Not a loading state and not an error: nothing is being fetched and nothing has failed. The engine
    // this side needs has no adapter yet, which is a fact about the app's build order rather than about
    // the user's data — so it reads as an absence, calmly.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.insights_outlined, size: AlayaIconSize.md, color: semantic.muted),
        const SizedBox(width: AlayaSpacing.sm),
        Expanded(
          child: Text(
            strings.insightAnalyticsPending,
            style: AlayaTypography.body.copyWith(color: semantic.muted),
          ),
        ),
      ],
    );
  }
}
```

### `lib/features/dashboard/presentation/widgets/module_grid.dart`

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/dashboard/providers/module_providers.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

/// Navigation tiles, each carrying a live number (ARCH_5 §3 archetype F).
///
/// **Every tile's number is real, and a zero is worded rather than shown.** "0 running low" is a figure
/// the reader has to interpret; "nothing tracked" is an answer. The ARB holds both wordings and picks by
/// count, which is why `ModuleTile` takes text rather than an `int`.
///
/// A count still arriving shows the module's name and no number rather than a spinner: the tile's job is
/// navigation, and it can do that job before its count lands.
///
/// ## The cell height is measured, not a ratio
///
/// `childAspectRatio` ties a cell's height to its *width*, and width does not move when the user doubles
/// their text size. So the box stayed put while both labels inside it grew, and every dashboard test
/// overflowed — by 22px at scale 1 and 250px at scale 2 (Law U15, and the reason U15 asks for a test
/// rather than an opinion).
///
/// `mainAxisExtent` computed from `MediaQuery.textScalerOf` grows with the text instead. The grid gets
/// taller and the dashboard scrolls, which is the right outcome: archetype F requires the screen to
/// *survive* 320dp at scale 2, not to fit on it.
///
/// ## `push`, not `go` — a tile is a drill-down
///
/// Tapping a tile is a "go into this" gesture, so it should come back. `go` made the module a peer of the
/// dashboard and left the drawer as the only way home: two taps, and no back affordance at all. `push`
/// slides the module over the dashboard and `_ShellScaffold` now shows a back arrow when it can pop, so
/// the way out is the arrow, the OS gesture, or the drawer — three, rather than one.
///
/// The drawer still `go`es, which is correct: choosing Expenses from a list of nine destinations *is* a
/// peer switch, and it should not accumulate a stack.
///
/// `push` also keeps the dashboard live underneath. Six of its providers are `autoDispose`, so leaving the
/// location tears their subscriptions down and returning refetches — a visible loading flash on a screen
/// the user was just looking at. Pushed, the dashboard stays mounted, its drift streams keep emitting, and
/// a transaction added on the pushed screen has already landed in the figures before the pop finishes.
///
/// The budget below is what one tile actually needs — its glyph, its two spacers, both labels at
/// `ModuleTile.maxLabelLines`, and the tile's own padding — floored at two tap targets so a tile is never
/// smaller than something you can hit (U3).
class ModuleGrid extends ConsumerWidget {
  /// Creates the grid.
  const ModuleGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    final expenses = ref.watch(expenseCountProvider).valueOrNull;
    final inventory = ref.watch(inventoryCountProvider);
    final shopping = ref.watch(shoppingCountProvider).valueOrNull;
    final recurring = ref.watch(recurringCountProvider).valueOrNull;
    final services = ref.watch(serviceCountProvider);

    // A count worth acting on is coloured; a settled one is not. Colour is the only thing distinguishing
    // "two bills due" from "two bills paid", and the wording carries the rest.
    Color? toneFor(int? count) =>
        count != null && count > 0 ? semantic.warning : null;

    final scaler = MediaQuery.textScalerOf(context);

    // The height one label occupies at its full line budget, at the scale in force right now.
    double labelBudget(TextStyle style) =>
        scaler.scale(style.fontSize!) * style.height! * ModuleTile.maxLabelLines;

    final tileExtent = math
        .max(
          AlayaSpacing.minTapTarget * 2,
          AlayaIconSize.lg +
              AlayaSpacing.xs +
              labelBudget(AlayaTypography.body) +
              AlayaSpacing.xxs +
              labelBudget(AlayaTypography.caption) +
              AlayaSpacing.sm * 2,
        )
        .toDouble();

    return GridView(
      shrinkWrap: true,
      // The dashboard owns the scroll (Law U13): a grid that scrolls inside a `CustomScrollView` is two
      // gestures fighting over one drag. `shrinkWrap` and `NeverScrollableScrollPhysics` travel together
      // — one without the other is the defect (ARCH_6 P2).
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AlayaSpacing.sm,
        crossAxisSpacing: AlayaSpacing.sm,
        mainAxisExtent: tileExtent,
      ),
      children: [
        ModuleTile(
          label: strings.navExpenses,
          icon: Icons.receipt_long_outlined,
          detail: expenses == null ? '' : strings.moduleExpenses(expenses),
          onTap: () => context.push(Routes.expenses),
        ),
        ModuleTile(
          label: strings.navInventory,
          icon: Icons.inventory_2_outlined,
          detail: strings.moduleInventory(inventory),
          tone: toneFor(inventory),
          onTap: () => context.push(Routes.inventory),
        ),
        ModuleTile(
          label: strings.navShopping,
          icon: Icons.shopping_basket_outlined,
          detail: shopping == null ? '' : strings.moduleShopping(shopping),
          tone: toneFor(shopping),
          onTap: () => context.push(Routes.shopping),
        ),
        ModuleTile(
          label: strings.navRecurring,
          icon: Icons.event_repeat,
          detail: recurring == null ? '' : strings.moduleRecurring(recurring),
          tone: toneFor(recurring),
          onTap: () => context.push(Routes.recurring),
        ),
        ModuleTile(
          label: strings.navServices,
          icon: Icons.handyman_outlined,
          detail: strings.moduleServices(services),
          tone: toneFor(services),
          onTap: () => context.push(Routes.services),
        ),
      ],
    );
  }
}
```

### `lib/features/dashboard/presentation/screens/dashboard_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/dashboard_calendar.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/presentation/widgets/module_grid.dart';
import 'package:alaya/features/dashboard/presentation/widgets/range_row.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';

/// The dashboard (ARCH_5 §3 archetype F).
///
/// **One `displayAmount`, in the funds header.** Everything else on this screen is `small` or smaller, and
/// that hierarchy is the only reason a glance works — two headline numbers is no headline number.
///
/// **Four independent sections, four independent failures.** The header, each range row, the insight card
/// and the grid each render their own loading, empty and error state inline. A rate table that will not
/// load costs the header and the range rows their figures; it does not blank the dashboard, and it does
/// not stop the grid navigating.
///
/// **No scrim behind the FAB** — decided in this phase, recorded in the phase document's header. Its action
/// rows carry opaque surfaces of their own and `TapRegion` plus `PopScope` already dismiss it, so the
/// remaining argument for dimming was signalling modality that a three-item menu does not have.
class DashboardScreen extends ConsumerWidget {
  /// Creates the screen.
  const DashboardScreen({super.key});

  /// Opens the transaction editor pre-set to a deposit.
  ///
  /// **Through the draft channel Phase 6C built**, not a second route or a query parameter. `_load(null)`
  /// already consumes a draft, so "money in" costs one provider write rather than a parallel entry point
  /// that would then need its own maintenance (ARCH_4 P7).
  void _addIncome(BuildContext context, WidgetRef ref) {
    ref
        .read(transactionDraftProvider.notifier)
        .offer(
          const TransactionDraft(
            lines: <TransactionLine>[],
            kind: TransactionKind.deposit,
            subtype: TransactionSubtype.otherIn,
          ),
        );
    context.push(Routes.transactionNew);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.screenEdge,
                AlayaSpacing.md,
                AlayaSpacing.screenEdge,
                AlayaSpacing.sm,
              ),
              child: const FundsHeader(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Both windows are stated in words. A row reading "last month" would be ambiguous
                  // between thirty days and a calendar month, and the figures cannot disambiguate
                  // themselves (anomaly A33).
                  RangeRow(
                    label: strings.rangeLast30,
                    range: ref.watch(last30Provider),
                  ),
                  RangeRow(
                    label: strings.rangeAllTime,
                    range: ref.watch(allTimeProvider),
                  ),
                  const SizedBox(height: AlayaSpacing.sm),
                  // After the funds figures and before "Coming Up": the month's *shape* first, then the
                  // shortlist that says which of those days matters soonest.
                  const DashboardCalendar(),
                  const SizedBox(height: AlayaSpacing.sm),
                  const InsightCard(),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AlayaSpacing.xl,
                      bottom: AlayaSpacing.xs,
                    ),
                    child: Text(
                      strings.moduleGridTitle,
                      style: AlayaTypography.sectionHeader.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                  ),
                  const ModuleGrid(),
                  // Clears the FAB, which floats over the last row otherwise.
                  const SizedBox(height: AlayaSpacing.xxxl * 2),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: AlayaExpandableFab(
        openLabel: strings.fabOpenLabel,
        closeLabel: strings.fabCloseLabel,
        actions: [
          FabAction(
            label: strings.addExpense,
            icon: Icons.remove,
            onPressed: () => context.push(Routes.transactionNew),
          ),
          FabAction(
            label: strings.fabAddIncome,
            icon: Icons.add,
            onPressed: () => _addIncome(context, ref),
          ),
          FabAction(
            label: strings.fabAddItem,
            icon: Icons.inventory_2_outlined,
            onPressed: () => context.push(Routes.itemNew),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/dashboard/presentation/widgets/dashboard_calendar.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';

/// This month at a glance. Each day opens its entries in a sheet — where the day is big enough to hit.
///
/// **The interaction is measured, not assumed.** Seven columns need 336dp to give every day the 48dp
/// tap-target floor, and this card's inner width is the screen minus 64dp of padding. So a 320dp phone
/// yields 36.6dp per day and a 412dp phone yields 49.7dp: the same widget is compliant on one and not on
/// the other. Rather than ship undersized targets everywhere or drop the feature everywhere, the grid
/// asks its own constraints:
///
/// * **48dp or more per cell** — every day is tappable and opens `DaySheet`.
/// * **less than that** — the days go inert (`IgnorePointer` removes the gestures, `ExcludeSemantics` the
///   undersized nodes) and the whole card becomes one large target that opens the calendar screen, which
///   has the room to do this properly.
///
/// That is why the dashboard's `androidTapTargetGuideline` test passes at 320dp with no exclusion: at
/// that width there are genuinely no small targets, rather than small targets the test agreed to ignore.
/// Suppressing the check would have hidden a real defect on exactly the phones least able to afford it.
///
/// `DaySheet` is the same sheet the calendar's deep link opens, so a day reads identically wherever it is
/// reached from. Ranges and month paging stay on the full screen.
///
/// Dots only in the grid itself: "Coming Up" sits directly below this card, and repeating the same events
/// as cards would say the same thing twice in one scroll. What the grid adds is shape — which days have
/// something on them — which no list conveys.
class DashboardCalendar extends ConsumerWidget {
  /// Creates the section.
  const DashboardCalendar({super.key});

  /// The Android tap-target floor, below which a day cell stops accepting taps.
  static const double _tapTargetFloor = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    // `currentMonthProvider`, never `focusedMonthProvider`: this grid must not follow wherever the
    // calendar screen was last left, or returning from December would show December here.
    final month = ref.watch(currentMonthProvider);
    final today = ref.watch(calendarTodayProvider);
    final index = ref.watch(calendarDayIndexProvider(month));
    final label = DateFormat.yMMMM(Localizations.localeOf(context).toLanguageTag())
        .format(month.toUtcMidnight());

    return LayoutBuilder(
      builder: (context, constraints) {
        // The width the grid will actually hand each of its seven columns.
        final cellWidth = (constraints.maxWidth - 2 * AlayaSpacing.md) / DateTime.daysPerWeek;
        final tappable = cellWidth >= _tapTargetFloor;

        final grid = CalendarMonthGrid(
          month: month,
          today: today,
          daysByKey: index.valueOrNull ?? const <int, CalendarDay>{},
          selected: today,
          onDaySelected: (day) => DaySheet.show(context: context, dateKey: day),
          // A long-press starts a range on the full screen; here there is nowhere to show one, so it
          // opens the same sheet. One gesture, one outcome, no hidden mode.
          onDayLongPressed: (day) => DaySheet.show(context: context, dateKey: day),
          // Nothing to change to: the grid is bounded to this month and its gestures are off.
          onMonthChanged: (_) {},
          lockedToMonth: true,
        );

        final card = AlayaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AlayaSpacing.xs),
              if (tappable)
                grid
              else
                IgnorePointer(child: ExcludeSemantics(child: grid)),
              // Full width and free to wrap. Beside the month title this button wanted 435dp of the 256
              // available at a doubled text scale — the 179dp of overflow the dashboard's layout test
              // reported (Law U21).
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.push(Routes.calendar),
                  icon: const Icon(Icons.open_in_new, size: AlayaIconSize.sm),
                  label: Text(strings.dashboardOpenCalendar),
                ),
              ),
            ],
          ),
        );

        // Narrow: the card itself is the target, so the month is still one tap from being explored.
        if (tappable) return card;
        return Semantics(
          container: true,
          button: true,
          label: strings.dashboardCalendarSemantics(label),
          child: InkWell(onTap: () => context.push(Routes.calendar), child: card),
        );
      },
    );
  }
}
```
### `test/support/fake_settings_repository.dart`

New in this revision. `InsightSideNotifier.build` reads settings on the first frame, so any scope that
mounts the insight card and leaves `settingsRepositoryProvider` un-overridden resolves `databaseProvider`
and throws by design (L10) — twenty-one tests died on it. A `NotifierProvider` instance cannot be
overridden (ARCH_6 P5), so the repository beneath it is the only seam. Shared by the dashboard harness and
`layout_overflow_test.dart`, because a fake written twice is a fake that will disagree with itself.

```dart
/// An in-memory [SettingsRepository] for widget tests.
///
/// **Needed because a notifier may read settings during `build`.** `InsightSideNotifier.build` restores
/// the insight card's side from `app_settings`, so any scope that mounts the card and leaves
/// `settingsRepositoryProvider` un-overridden resolves `databaseProvider`, which throws by design
/// (Law L10). The symptom is a `StateError` about the database in a test that never mentions one, which
/// reads as a product bug and is not (ARCH_6 P6).
///
/// Kept in `test/support/` rather than inside one harness because two suites need it — the dashboard
/// harness and `layout_overflow_test.dart` — and a fake written twice is a fake that will disagree with
/// itself (ARCH_4 R25, one layer down).
library;

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';

/// Key/value settings held in a map, with writes readable back.
class FakeSettingsRepository implements SettingsRepository {
  /// Creates a store seeded with [values].
  ///
  /// [homeCurrencyCode] and [defaultAccountId] are separate rather than map entries so the fake does not
  /// have to know `SettingsKeys`' spelling — a test asserting on a key it guessed wrong passes for the
  /// wrong reason.
  FakeSettingsRepository({
    Map<String, String>? values,
    this.homeCurrencyCode = 'INR',
    this.defaultAccountId,
  }) : _values = {...?values};

  final Map<String, String> _values;

  /// What `readHomeCurrencyCode` answers.
  final String? homeCurrencyCode;

  /// What `readDefaultAccountId` answers.
  final String? defaultAccountId;

  /// Everything written so far, so a test can assert a preference was actually persisted.
  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> readValue(String key) async => _values[key];

  @override
  Stream<String?> watchValue(String key) => Stream.value(_values[key]);

  @override
  Stream<Map<String, String>> watchAll() => Stream.value(values);

  @override
  Future<Result<void, Failure>> writeValue({
    required String key,
    required String value,
    required String valueType,
  }) async {
    _values[key] = value;
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> remove(String key) async {
    _values.remove(key);
    return const Result.ok(null);
  }

  @override
  Future<String?> readHomeCurrencyCode() async => homeCurrencyCode;

  @override
  Future<String?> readDefaultAccountId() async => defaultAccountId;
}
```

### `test/support/dashboard_harness.dart`

```dart
/// Shared scaffolding for the Dashboard's widget tests.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/providers/module_providers.dart';
import 'package:alaya/features/dashboard/providers/range_providers.dart';

import 'fake_settings_repository.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is the same on every machine.
final Clock kDashClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kDashClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays loading.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A headline total, with however many balances it could not convert.
NetWorth netWorth({
  int minor = 12345678,
  int unconverted = 0,
  bool approximate = false,
}) =>
    NetWorth(
      total: Money(minor, 'INR'),
      unconvertedCount: unconverted,
      isApproximate: approximate,
    );

/// Totals over one window.
RangeTotals totals({int inMinor = 500000, int outMinor = 320000, int excluded = 0}) =>
    RangeTotals(
      moneyIn: Money(inMinor, 'INR'),
      moneyOut: Money(outMinor, 'INR'),
      excludedCount: excluded,
    );

/// One thing needing attention.
UpcomingEntry upcoming({
  UpcomingKind kind = UpcomingKind.bill,
  String title = 'Rent',
  DateKey on = const DateKey(20260805),
}) =>
    UpcomingEntry(kind: kind, title: title, dueDateKey: on);

/// Overrides every dashboard provider to a settled, harmless value.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod
/// refuses it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a
/// varying list fails in both directions (ARCH_4 P5).
///
/// Every provider is overridden even where a test does not care, because an un-overridden repository
/// provider reaches a real database, which a widget test has no business opening (P6).
List<Override> dashboardOverrides({
  AsyncValue<NetWorth>? funds,
  AsyncValue<RangeTotals>? last30,
  AsyncValue<RangeTotals>? allTime,
  AsyncValue<List<UpcomingEntry>>? upcomingEntries,
  int inventory = 0,
  int services = 0,
  AsyncValue<int>? expenses,
  AsyncValue<int>? shopping,
  AsyncValue<int>? recurring,
}) =>
    [
      clockProvider.overrideWithValue(kDashClock),
      // `InsightSideNotifier.build` reads settings during the first frame, so this is not optional
      // even for a test that never touches the insight card: without it the notifier resolves
      // `databaseProvider`, which throws by design (Law L10). A `NotifierProvider` instance cannot be
      // overridden (ARCH_6 P5), so the repository beneath it is the only seam.
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) => _resolve(funds ?? AsyncValue.data(netWorth())),
      ),
      rangeTotalsProvider.overrideWith(
        (ref, range) => _resolve(
          (range == (from: DateKey(20260703), to: kToday) ? last30 : allTime) ??
              AsyncValue.data(totals()),
        ),
      ),
      upcomingProvider.overrideWith(
        (ref) => _resolve(upcomingEntries ?? const AsyncValue.data(<UpcomingEntry>[])),
      ),
      inventoryCountProvider.overrideWith((ref) => inventory),
      serviceCountProvider.overrideWith((ref) => services),
      expenseCountProvider.overrideWith((ref) => _resolve(expenses ?? const AsyncValue.data(0))),
      shoppingCountProvider.overrideWith((ref) => _resolve(shopping ?? const AsyncValue.data(0))),
      recurringCountProvider.overrideWith((ref) => _resolve(recurring ?? const AsyncValue.data(0))),
    ];

/// Turns an [AsyncValue] back into the future a `FutureProvider` override expects.
Future<T> _resolve<T>(AsyncValue<T> value) => value.when(
      data: Future.value,
      loading: pendingFuture<T>,
      error: (error, stack) => Future<T>.error(error, stack),
    );

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
Future<void> pumpDashboard(
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

### `test/features/dashboard/funds_header_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/dashboard_harness.dart';

/// The one headline figure, and the two things it must never do quietly.
void main() {
  Widget host() => const Scaffold(body: FundsHeader());

  testWidgets('loading says so without a spinner', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(funds: const AsyncValue.loading()),
    );
    expect(find.text('Adding it up'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        funds: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('a complete total is the only figure, and carries no chips', (tester) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(find.text('Total available funds'), findsOneWidget);
    // Exactly one AmountText, and it is the display size — archetype F allows one headline.
    expect(find.byType(AmountText), findsOneWidget);
    expect(tester.widget<AmountText>(find.byType(AmountText)).size, AmountSize.display);
    // Nothing to warn about, so nothing is said.
    expect(find.textContaining('not converted'), findsNothing);
    expect(find.text('Rate is older than today'), findsNothing);
  });

  testWidgets('a zero total is still a total, not an empty state', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(funds: AsyncValue.data(netWorth(minor: 0))),
    );
    await tester.pumpAndSettle();
    // Nought available funds is a fact about the accounts, not an absence of data — showing an empty
    // state here would imply Alaya had failed to look.
    expect(find.byType(AmountText), findsOneWidget);
    expect(find.text('Total available funds'), findsOneWidget);
  });

  testWidgets('unconvertible balances are counted out loud, never summed', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(funds: AsyncValue.data(netWorth(unconverted: 2))),
    );
    await tester.pumpAndSettle();
    // Anomaly A34: a dirham balance folded into a rupee total at face value would be a wrong number
    // presented as a right one. A smaller number plus a chip is honest — and the chip explains itself
    // rather than only counting.
    expect(find.text('2 balances not converted'), findsOneWidget);
    expect(
      find.textContaining('left out rather than guessed at'),
      findsOneWidget,
    );
  });

  testWidgets('a stale rate is disclosed separately from an exclusion', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(funds: AsyncValue.data(netWorth(approximate: true))),
    );
    await tester.pumpAndSettle();
    // Converted with yesterday's rate is a different claim from not converted at all, so it gets its own
    // chip and no exclusion note.
    expect(find.text('Rate is older than today'), findsOneWidget);
    expect(find.textContaining('not converted'), findsNothing);
    expect(find.textContaining('left out rather than guessed at'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(unconverted: 3, approximate: true)),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/dashboard/range_row_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/dashboard/presentation/widgets/range_row.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

import '../../support/dashboard_harness.dart';

/// The label is the test. A range row without one is a number with no meaning (anomaly A33).
void main() {
  const window = (from: DateKey(20260703), to: kToday);

  Widget host(String label) =>
      Scaffold(body: RangeRow(label: label, range: window));

  testWidgets('the window is stated in words, never implied', (tester) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    // "Last month" would be ambiguous between thirty days and a calendar month, and the figures cannot
    // disambiguate themselves. The label states the window the provider actually computed.
    expect(find.text('Last 30 days'), findsOneWidget);
  });

  testWidgets('loading keeps the label', (tester) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(last30: const AsyncValue.loading()),
    );
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Adding it up'), findsOneWidget);
  });

  testWidgets('an error keeps the label and names itself', (tester) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(
        last30: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    // A failed conversion must not take the window's meaning down with it — the reader still needs to
    // know which row broke.
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('an empty window reads as nothing yet, not as zero', (tester) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(
        last30: AsyncValue.data(totals(inMinor: 0, outMinor: 0)),
      ),
    );
    await tester.pumpAndSettle();
    // Two zeroes side by side look like a computation; "nothing yet" is what actually happened.
    expect(find.text('Nothing yet'), findsOneWidget);
    expect(find.byType(AmountText), findsNothing);
  });

  testWidgets('populated shows both legs, each labelled and each small', (tester) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    expect(find.text('In'), findsOneWidget);
    expect(find.text('Out'), findsOneWidget);
    final amounts = tester.widgetList<AmountText>(find.byType(AmountText)).toList();
    expect(amounts.length, 2);
    // Neither is a headline: the funds header owns the only display-sized figure on the dashboard.
    expect(amounts.every((a) => a.size == AmountSize.small), isTrue);
    expect(amounts.first.kind, TransactionKind.deposit);
    expect(amounts.last.kind, TransactionKind.withdrawal);
  });

  testWidgets('excluded transactions are disclosed, not folded in', (tester) async {
    await pumpDashboard(
      tester,
      host('Last 30 days'),
      overrides: dashboardOverrides(last30: AsyncValue.data(totals(excluded: 3))),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 left out'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      host('All time'),
      overrides: dashboardOverrides(last30: AsyncValue.data(totals(excluded: 2))),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(tester, host('Last 30 days'), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/dashboard/insight_card_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/features/dashboard/state/insight_side.dart';

import '../../support/dashboard_harness.dart';

/// Both sides, both empty states, and the switch. One failing card never blanks the dashboard.
void main() {
  // Inside a scroll view, because that is the only place the app ever puts this card: `DashboardScreen`
  // mounts it in a `CustomScrollView`, and the card's own contract is that it must not scroll on its own
  // — two scroll gestures competing for one drag. A bare `Scaffold` body bounds the main axis at the
  // viewport, so at a doubled scale this failed the card for being tall, which is what a card full of
  // wrapped text at 2x is supposed to be.
  //
  // This does not weaken the assertions. The cross axis stays tight at 320dp, and that is where the
  // overflow class this suite exists for actually lives (Law U21) — a starved `Expanded`, or a `Row`
  // that will not stack, still throws here.
  Widget host() => const Scaffold(
        body: SingleChildScrollView(child: InsightCard()),
      );

  testWidgets('it opens on what is coming up', (tester) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(find.text('Coming up'), findsOneWidget);
    expect(find.text('Where it went'), findsOneWidget);
  });

  testWidgets('loading the upcoming side says so, inline', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(upcomingEntries: const AsyncValue.loading()),
    );
    // Inline, inside the card: the header and the module grid above and below must stay usable.
    expect(find.text('Adding it up'), findsOneWidget);
  });

  testWidgets('a failed upcoming read shows its reason inline', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('nothing upcoming is good news, and reads like it', (tester) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(
      find.text('Nothing needs attention in the next fortnight.'),
      findsOneWidget,
    );
  });

  testWidgets('populated lists what is due, soonest first', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([
          upcoming(title: 'Rent'),
          upcoming(
            kind: UpcomingKind.service,
            title: 'Living room TV',
            on: const DateKey(20260810),
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Bill due'), findsOneWidget);
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('Service due'), findsOneWidget);
  });

  testWidgets('something already late says so', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        // Due in July against a clock fixed to 1 August. Derived from the clock, never stored.
        upcomingEntries: AsyncValue.data([upcoming(on: const DateKey(20260715))]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsOneWidget);
  });

  testWidgets('the spending side says what it is waiting for', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: [
        ...dashboardOverrides(),
        insightSideProvider.overrideWith(() => _FixedSide(InsightSide.spending)),
      ],
    );
    await tester.pumpAndSettle();
    // `AnalyticsService` has no port adapter until Phase 7B (ARCH_4 §5.1 item 15). Aggregating here
    // instead would leave 7B a competing implementation, so the side is honest rather than invented.
    expect(
      find.text('Spending breakdowns arrive with the analytics module.'),
      findsOneWidget,
    );
    expect(find.text('Nothing needs attention in the next fortnight.'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([
          upcoming(title: 'A bill with a name long enough to wrap at a doubled scale'),
          upcoming(kind: UpcomingKind.batch, on: const DateKey(20260710)),
        ]),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([upcoming()]),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the stored side', () {
    test('an unknown value falls back to upcoming rather than throwing', () {
      // A settings row is user data, and a future version may write a value this one has never heard of.
      expect(InsightSide.parse('spending'), InsightSide.spending);
      expect(InsightSide.parse('upcoming'), InsightSide.upcoming);
      expect(InsightSide.parse('something-else'), InsightSide.upcoming);
      expect(InsightSide.parse(null), InsightSide.upcoming);
    });

    test('what is stored round-trips', () {
      for (final side in InsightSide.values) {
        expect(InsightSide.parse(side.stored), side);
      }
    });
  });
}

/// A notifier reporting a fixed side, so each face can be pumped directly.
class _FixedSide extends InsightSideNotifier {
  _FixedSide(this._value);

  final InsightSide _value;

  @override
  InsightSide build() => _value;
}
```

### `test/features/dashboard/module_grid_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/dashboard/presentation/widgets/module_grid.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

import '../../support/dashboard_harness.dart';

/// The grid is navigation, not decoration — so every tile's number is the test.
void main() {
  Widget host() => const Scaffold(body: SingleChildScrollView(child: ModuleGrid()));

  testWidgets('five tiles, each naming a module the drawer also names', (tester) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    expect(find.byType(ModuleTile), findsNWidgets(5));
    for (final label in ['Expenses', 'Inventory', 'Shopping', 'Recurring', 'Services']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('a zero is worded, never shown as a figure', (tester) async {
    await pumpDashboard(tester, host(), overrides: dashboardOverrides());
    await tester.pumpAndSettle();
    // "0 running low" is a number the reader has to interpret; "nothing tracked" is an answer. Only the
    // ARB knows which sentence a count needs, which is why ModuleTile takes text rather than an int.
    expect(find.text('nothing tracked'), findsOneWidget);
    expect(find.text('list is clear'), findsOneWidget);
    expect(find.text('all settled'), findsOneWidget);
    expect(find.text('nothing needs doing'), findsOneWidget);
  });

  testWidgets('a live number appears, singular and plural both worded', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        inventory: 1,
        services: 4,
        shopping: const AsyncValue.data(7),
        recurring: const AsyncValue.data(2),
        expenses: const AsyncValue.data(31),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 running low'), findsOneWidget);
    expect(find.text('4 need attention'), findsOneWidget);
    expect(find.text('7 to buy'), findsOneWidget);
    expect(find.text('2 due'), findsOneWidget);
    expect(find.text('31 this month'), findsOneWidget);
  });

  testWidgets('a count still arriving leaves the tile navigable', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(shopping: const AsyncValue.loading()),
    );
    await tester.pump();
    // The tile's job is navigation and it can do that before its count lands — a spinner on a nav tile
    // would suggest the destination itself was unavailable.
    expect(find.byType(ModuleTile), findsNWidgets(5));
    expect(find.text('Shopping'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed count leaves the tile navigable too', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        recurring: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    // One broken count must not cost the user five destinations.
    expect(find.byType(ModuleTile), findsNWidgets(5));
    expect(find.text('Recurring'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(
        inventory: 12,
        services: 9,
        shopping: const AsyncValue.data(23),
        recurring: const AsyncValue.data(5),
        expenses: const AsyncValue.data(147),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tile is a labelled button of a reachable size', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(
      tester,
      host(),
      overrides: dashboardOverrides(inventory: 2),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/dashboard/dashboard_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/presentation/widgets/module_grid.dart';
import 'package:alaya/features/dashboard/presentation/widgets/range_row.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/amount_text.dart';

import '../../support/dashboard_harness.dart';

/// The §9.1 gate for the dashboard, plus the two invariants archetype F exists to protect.
void main() {
  testWidgets('loading: every section says so on its own', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        funds: const AsyncValue.loading(),
        last30: const AsyncValue.loading(),
        allTime: const AsyncValue.loading(),
        upcomingEntries: const AsyncValue.loading(),
      ),
    );
    await tester.pump();
    // Four sections still present while none of them has a figure — the screen is a frame, not a spinner.
    expect(find.byType(FundsHeader), findsOneWidget);
    expect(find.byType(RangeRow, skipOffstage: false), findsNWidgets(2));
    expect(find.byType(InsightCard, skipOffstage: false), findsOneWidget);
    expect(find.byType(ModuleGrid, skipOffstage: false), findsOneWidget);
  });

  testWidgets('empty: a household with no data still gets a usable screen', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(minor: 0)),
        last30: AsyncValue.data(totals(inMinor: 0, outMinor: 0)),
        allTime: AsyncValue.data(totals(inMinor: 0, outMinor: 0)),
      ),
    );
    await tester.pumpAndSettle();
    // There is no whole-screen empty state, deliberately: every section has its own, and a first-run
    // dashboard should still show a user where everything is.
    expect(find.text('Nothing yet'), findsWidgets);
    expect(find.byType(ModuleGrid, skipOffstage: false), findsOneWidget);
  });

  testWidgets('error: one failing section never blanks the others', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        funds: AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    await tester.pumpAndSettle();
    // The whole point of archetype F's inline states: a broken rate table costs the headline and nothing
    // else. The grid must still navigate.
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(ModuleGrid, skipOffstage: false), findsOneWidget);
    expect(find.byType(RangeRow, skipOffstage: false), findsNWidgets(2));
  });

  testWidgets('populated: exactly one headline figure on the whole screen', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([upcoming()]),
        inventory: 3,
      ),
    );
    await tester.pumpAndSettle();
    final display = tester
        .widgetList<AmountText>(find.byType(AmountText, skipOffstage: false))
        .where((a) => a.size == AmountSize.display)
        .length;
    // Two headline numbers is no headline number (ARCH_5 §3 archetype F). Every other figure is small.
    expect(display, 1);
  });

  testWidgets('both range windows are named, and named differently', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    // Anomaly A33: never an unlabelled window, and never two rows a user cannot tell apart.
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('All time'), findsOneWidget);
  });

  testWidgets('the FAB offers three ways in and nothing else', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlayaExpandableFab), findsOneWidget);
    await tester.tap(find.byTooltip('Add something'));
    await tester.pumpAndSettle();
    expect(find.text('Add expense'), findsOneWidget);
    expect(find.text('Money in'), findsOneWidget);
    expect(find.text('New item'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        funds: AsyncValue.data(netWorth(unconverted: 2, approximate: true)),
        last30: AsyncValue.data(totals(excluded: 4)),
        upcomingEntries: AsyncValue.data([
          upcoming(title: 'A bill with a name long enough to wrap twice over'),
          upcoming(kind: UpcomingKind.batch, on: const DateKey(20260710)),
        ]),
        inventory: 12,
        services: 9,
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDashboard(
      tester,
      const DashboardScreen(),
      overrides: dashboardOverrides(
        upcomingEntries: AsyncValue.data([upcoming()]),
        inventory: 2,
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

---

## COVERAGE — ARCH_5 §7 rows closed by Phase 6F

### §7.1 By surface

| Row | Where it lands |
|---|---|
| **Funds header** | `BalanceService.totalInHome` and nothing else. `AccountRepository.watchTotalInHomeCurrency` is **dropped** from the contract and the impl by this phase — it was a second answer to a question with one right answer (ARCH_4 §5.1 item 13), and nothing called it |
| **Range rows** | Last-30-days and all-time, each **always labelled with the window it computed** (anomaly A33). Transfers and adjustments are excluded from both legs, because "In" and "Out" must contain only what those words mean |
| **Insight card** | Switchable, the choice stored in `app_settings`, and **each side renders its own loading, empty and error state inline** — one failing card never blanks the dashboard |
| **Module grid** | Five tiles, each carrying a live number, each naming a module the drawer also names. A zero is worded, never shown as a figure |
| **Approximate / unconverted chips over `currency_rates`** | `NetWorth.unconvertedCount` becomes a counted chip with a sentence explaining the exclusion; `NetWorth.isApproximate` becomes a separate chip, because a stale rate is a different claim from no rate (anomaly A34) |

### §7.2 What each surface makes reachable

| Data | Where a user sees it |
|---|---|
| `v_account_ledger` totals | The one `displayAmount` on the dashboard. **A self-transfer cannot move it** — the view counts a transfer once against each side, so the invariant is structural rather than defended |
| `currency_rates` gaps | The unconverted chip, plus a plain sentence saying balances with no rate are left out rather than guessed at |
| `recurring_occurrences` due | The upcoming side, and the Recurring tile's count |
| `assets.nextServiceDueDateKey` / `warrantyEndDateKey` | The upcoming side, and the Services tile's count |
| `inventory_batches.expiryDateKey` | The upcoming side |
| `items` below their low-stock level | The Inventory tile — via **6B's `lowStockCountProvider`**, not a second definition of "low" |
| `shopping_entries` outstanding | The Shopping tile, filtered by `ShoppingEntry.isOutstandingAsOf` so a snoozed suggestion is not counted as something to buy |
| `app_settings` | The insight card's stored side — the first user preference this app persists outside Settings |

### §7.3 Deferred — with the contract each waits on

| Item | Why | Owner |
|---|---|---|
| The insight card's **spending** side | `AnalyticsService` has no `AnalyticsPort` adapter and `AnalyticsCacheRepository` has no implementation (ARCH_4 §5.1 item 15). The switch, the stored preference and both sides' state handling are complete; the side renders an inline empty state naming what it waits for. **Aggregating spending here instead would leave 7B a competing implementation to reconcile** (ARCH_4 P7) | **7B** |
| A real **calendar** surface | `CalendarAggregator` requires `CalendarRepository`, also unimplemented. The upcoming side is a dashboard-scoped shortlist over four repositories and deliberately not a general calendar — the month grid, day cells and event tones belong to 7A and to the aggregator that already models them | **7A** |
| `ServiceRecordRepository.mostRecentForAsset` | Still unused. It answers "when was this last serviced", which is a detail-screen question the asset detail already answers from `watchForAsset` | **Kept, unused** |
| Tapping an upcoming row | Every row carries a nullable `route` and none is populated: a bill's occurrence and a batch's expiry both need an id the shortlist does not carry today. Wiring it means widening `UpcomingEntry`, which is better done when 7A's calendar needs the same navigation | **7A** |
| A dashboard **date-range picker** | The two windows are fixed. `DateRangeService` supports presets and custom ranges, and 7B's analytics screen is where a picker belongs — putting one here would make the dashboard a report | **7B** |
