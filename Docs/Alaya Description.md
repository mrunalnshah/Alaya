Alaya is a finance and home management application. The app targets dynamic number of users from multiple countries, regions and ethnicity. The app targets different professions like Students, Serviceman, homemakers, etc...

The goal of the app is to create an all-in-one environment for all users to manage their home and finances.

This is an Android Only App.

# Features

## Specific Features

### Dashboard
Dashboard will have following things:
1. Total Available Funds
2. A switchable widget, by default calendar and a top right side option to switch to analytics graphs (overall only) of last month. 
3. Total deposit and total withdrawal for last month shown below the widget of calender cum analytics.
4. Below all, there should be total deposit and total withdrawal done of all time on app.
5. The sidebar menu must have all features selection.
6. floating icons should have two buttons: one for fast expense add, one for fast inventory.

### Expense Manager
- This feature allows users to keep track of deposits and withdrawals.  
	- Deposit contains options for user to deposit transaction using Cash, UPI, Bank Transfer, Salary, and User defined option (like Zelle, Google Pay, etc...)
		- With Option to deposit allow users to add more optional details later on, or on the spot: From where the money came (From), Note, To which part of my account like did I receive cash, upi, or bank transfer and respectevely it adds to that.
	- Withdrawal contains options for users to buy grocery, buy household items, electronics, pay bills, transfer money, others
		- For both grocery and household item purchase allow users to add items of what they purchase like tomatos 250g for 100 rs, etc... let user make list of their purchase. This list will add to the existing inventory for ease of user convience so they dont have to add again to inventory.
		- For electronics, allow user to add what they purchase and add warrenty of their product so we can add this to service section to keep track of service. 
		- For bill payment, allow users to add what bill they are paying and give list of recurring payments to make it easy as well to select from and connect with recurring amount. User can pay any bill which can be different from recurring bill.
		- Transfer amount. Allow user to add transfer amount, whom they transfererd, and allow them to add note.
		- Others. This is a detailed section where user can add items with option to add them to inventory, or service, or recurring like Netflix Subscription to make a new tag. 
	- Remember payments are dynamic and every country and person has different payments, so allow them to create new tags or details.
	- Users can create their own tags from where the deposits come and to where the withdrawals go for example users can say I got deposit from UPI, and I paid  cash to grocery in withdrawal. 
	- Remember to have some basic tags used. 
### Inventory Manager
- This feature allows users to organize their inventory and even edit their inventory items to organize it. 
- Users can build tags to create new groups within inventory like grocery, household items, beauty, etc.. to organize items within Inventory list. 
- The biggest challenge will be that exisitng inventory and new inventory can have different units, allow users to create that, edit later and if the units match merge else if units are different consider them different. This is also applicable to expense withdrawal where we can add to inventory from withdrawal. 
- Units will be a biggest challenge. 2 product with same name can have different units like g and l, make two different entry and when they have same base units, merge.
- Remember to always store in base units, but show in convienent units like if i purchase 2 kg potatos, and later purchase 250 g potato than show 2 kg and 250 g potatos and not 2.25 kg.
- Allow user to edit or deduct the amount with ease, user can use the product like 100g out of 1 Kg.
- Allow users to add expiry date for knowing when before to use it.
- Allow user to add threshold amount so if the amount goes down, its automatically added to shopping list.
- Use item and batch implementation. 1 Item can have multiple batches bought with multiple expiry dates and quantities. Keep them different but show the added values in interface. Calculate from all active batches in use. 
	- Two purchases of the same item (matched by normalized name + unit category) become two Batches under one Item. The Item screen **displays** the summed quantity (e.g., "2 kg 450 g total") but every operation below acts on individual Batches.

## Shopping List
- Allow users to add shopping list, and also generate the list based on inventory stock.
- This allows users to not miss any item. Shopping list can be organized into different groups by user if wanted like in grocery they can add tomatos, for beauty they can add shampos, etc...
- Example:
	Grocery
		Tomatos 250g CHECKBOX
		Onions 1 kG CHECKBOX
	Beauty
		Shampos 2 px CHECKBOX
	Electronics
		TV CHECKBOX
	
### Recurring Manager
One unified entity — **Recurring Template** — used both by the dedicated Recurring Manager screen and by Expense → Others' "make this recurring" action. There is no separate parallel system.

|Field|Requirement|
|---|---|
|Name (e.g., "Netflix", "Electricity Bill")|Required|
|Amount|Required|
|Payee/Company|Optional|
|Category tag|Optional|
|Frequency (monthly/yearly/custom interval)|Required|
|Default source bucket|Optional|

Paying an instance of a template creates a normal Withdrawal transaction linked back to the template (for history) and advances "next due." History of all past payments for a template is viewable from the template's detail screen.

### Service Manager
- Allows users to keep track of their electronics items with warranty expiry, next service due, service contact number, history logs of previous services
- This also allows users to maintain house maid, and others.
- If user buys a electronic item, it should be added here.
- Allow users to delete also like they can delete their TV by selecting reasons, or expired, etc...
## General Features applied to whole app

### Minimal, Beautiful and Animation Enriched App
- App should be designed with minimal but detailed at the same time.
- App should focus on optional first approach for fast transaction across app allowing them to edit the transaction to add more details later on.
- Dashboard should contains 
	- Total Money Left (1 row)
	- Total Deposits and Total Withdrawals for last month (1 row)
	- Calendar (look at calendar details for more information)
	- Module showcase
	- Total Deposits and Total Withdrawals of all time
- Floating Button should have 2 items, rest all should be in dashboard's module section:
	- Expense
	- Inventory
### Theme customization
- Allow users to choose from light theme or dark theme.
- Write code in a way to have all customizing options available to me so I can choose the best color combination later on with ease.
### Remember to calculate based on transcations
- Dont keep track of total deposits, and total withdrawals rather calculate the transactions to calculate deposit, and withdrawals so that we have an exact amount.

### Show Details with simplicity every place
- if total deposit is in negative, show in red, if its positive show in green else red. use colors to make it more intuitive where every we can but keep it more uniformed across app.
- If a card is made, try to add more details till it looks good like in Expense details show expense type, expense date, expense amount (with green, red), to/from or grocery, electronics, tags, etc... 

### Simple to add 
- The app is based on the fact that everything is optional unless extremely required allowing you to add fast transactions and later edit for more details.
- Remember to add animations if field is not field like amount is essential in expense withdrawal, if there is any error, show it.

### Base Units & Currency
- Store all units in base units and later build a system to convert it into a simpler to look units like store as 2500 g but show 2 kg 500 g.
	- Potato 250 g 2 kg 1.5 kg 700 g. Internally 4450 g, but Display 2 kg 450 g
- Allow users to convert to currencys while keeping original amount of purchase currency same. If i purchase 100 INR fruits, and later i switch to USD. keep INR same. 
- Every transaction stores: Original Amount, Original Currency, Optional Converted Amount, Conversion Rate, Conversion Date
- So if user purchases 100 INR item,and later goes to US and converts to USD. He sees the conversion on the day of him purchasing like 1 USD = 89 INR when he purchase so conversion should happen like that. 
- Now this requires API and Internet, and this is the only place where we allow. 
- We only support INR, USD, EUR, JPY, Chinese Yen, and some most used currency. Use the open source API which is future-proof and may not ask for money if possible.
- Supported currencies at launch: **INR, USD, EUR, JPY, CNY** (list is extensible later without a data migration).
- **Home Currency**: one setting, defaults to the currency implied by device locale, changeable anytime in Settings. Used only for _display aggregation_ — never rewrites stored data.
- Every transaction permanently stores: `originalAmount`, `originalCurrency` (immutable once saved).
- A local **rate cache** table stores the daily rate fetched from the currency API (see 2.3.1). Dashboard totals convert each transaction's original amount into Home Currency using the cached rate closest to that transaction's date, purely for display — this calculation is never persisted back onto the transaction.
- If a transaction is in a foreign currency and no rate is cached yet (e.g., first run, fully offline), it's excluded from the converted total and flagged with a small "unconverted" indicator until a rate becomes available.
- Separately, a user can explicitly **convert** an individual transaction (e.g., "I paid ₹100, now show me what that was in USD on the day I paid it"). This stores `convertedAmount`, `conversionRate`, `conversionDate` as a frozen snapshot — independent of the live Home Currency aggregation above.
- Do your own research: **Currency data source:** `fawazahmed0/currency-api` (free, no API key, no rate limits, 150+ currencies) as primary, with **Frankfurter** (open-source, ECB-backed, no key) as a silent fallback if the primary is unreachable. Rates are fetched once daily and cached locally; a failed fetch never blocks a transaction from being saved.
- Applies to Inventory and Shopping List quantities.

| Category | Base Unit       | Display Rule                   | Example               |
| -------- | --------------- | ------------------------------ | --------------------- |
| Weight   | gram (g)        | Show as kg + g when ≥1000g     | 2450g → "2 kg 450 g"  |
| Volume   | millilitre (ml) | Show as L + ml when ≥1000ml    | 1200ml → "1 L 200 ml" |
| Count    | piece (pc)      | Shown as-is, never broken down | 3 pcs                 |

**Rule:** an Item's unit category is fixed at creation and can never be changed or cross-converted. If a user picks the wrong category, they create a new Item — this prevents silent data corruption from category mismatches.

### Tags
- allow a single tags table which connects all other systems.
- tag needs to have specifications like id name color icon allowedInDeposit allowedInWithdrawal allowedInInventory allowedInShopping allowedInRecurring allowedInService.
- Example, Kitchen tag created in shopping list should not be displayed in deposits
- Allow users to add tags as a optional thing in grocery and household, or electronics or others purchase in withdrawal in expense.

### Analytics
- I want a strong analytics engine which creates charts for expense, inventory, etc... all data. 
- I want users to see how much expense they did and in what domain, by which method. how much grocery they bought overall compare to other expense, but also allows users to see which grocery like which vegetable user bought  the most or which most expenseive vegetable user bought.
- Write the analytics at last. So after database is finalized, we can have most analysis out of the data. This is the most intuitive and should help user know and make them really happy seeing this.

### Calendar
- Use calender to keep track of all data for each day, for all service pending, service incoming, medicine expiry, etc...

### Ads & Support Us
- Rewarded ads only appear via **Settings → Support Us → Watch Ads**, never anywhere else in the app
- A one-time "Tip" purchase is also offered as a Support Us option, implemented as a Google Play Billing one-time non-consumable product

### Pin Code security
- A bit of security, users once enabled the security, they need a 4 digit pin code to login into the app and for loading the database.
- **Critical UX requirement**: because the PIN derives the encryption key, there is no server-side "forgot PIN" reset. At setup, the app must generate and display a one-time recovery phrase, force the user to explicitly confirm they've saved it elsewhere, before security can be enabled. Losing both the PIN and the recovery phrase means the data is unrecoverable — this must be communicated clearly during setup, not buried in settings.

### Backup & Restore
- Users can backup the data offline (SQL file directly) and allows users to store the data in their file manager or share the database to whatsapp, email.
- No encryption required for this. Keep it plain.

# Coding Guidelines
- Allow users to delete expense, inventory or any transactions or services. Dont make it strong delete, rather a soft delete. keep the data in database, just dont use that to calculate expenes like total available funds, and all.
- First write the most quality database required for the whole requirement and later I can just add the database code to prompts to save adding all files for code generating that doesnt require those files to save tokens. I mean, generate the most important stuff first which will define whole app. Requirements --> Database --> Repositories --> Business     --> Logic --> UI. 
- If you write 1 file of code, write the whole code at once. If required create files which will be coded later and use them as Placeholders for a while. 
- Give me only code and no explanation. 1 md file can contain code for multiple files with path for the file mentioned.
- I will be using free version of Claude Sonnet 5 (free tier) so create prompts based on that fact, I should not run out of usage. If 1 prompt can manage multiple files, give that, if 1 prompt needs 1 strong requirement of max effort like database files, give me that.
- Make the whole app in phases but give me code for a file complete so i dont have to change the code for that file again until and unless its a placeholder file generated.
- When you generate docs, architecture mds and prompts. In prompts, mention which Claude version and effort to use, so it makes it easy for me to safe money, time and can help me add a project with less tokens and a deployment level app which is one of the top in the area on google play store. 

# Development Environment to consider while generating code
- Flutter **3.44.x** (stable), Dart **3.12.x**
- Android only. Kotlin **2.3.20**, AGP **9.0.1**, Gradle **9.6.1**, JDK **17**, `compileSdk`/`targetSdk` = **36 (API 36.1)**.
- `android/gradle.properties` keeps the Flutter transitional flags **as-is**:
  `android.builtInKotlin=false` and `android.newDsl=false`.
  Rationale: AGP 9 removed the Kotlin Gradle Plugin requirement and enables built-in Kotlin by default; Flutter's temporary compatibility layer (these two flags) lets plugins that still apply KGP keep building. Keep the flags until **every** native plugin in the app is built-in-Kotlin ready, then flip them (this must happen before AGP 10). **Do not edit these Gradle files inside feature prompts until required for library dependencies.**
- Use Libraries if they are compatible with my latest flutter development environment and Kotlin flutter latest compatiblity guidelines.

