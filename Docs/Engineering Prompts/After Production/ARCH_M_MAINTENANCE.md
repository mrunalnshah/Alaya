# ARCH_M — Maintenance architecture

**What this is.** Alaya is 478 files and 85,000 lines. No model can hold that, and no person should paste it.
This document is the routing layer: you describe a change, it names the three or four bundles that change
needs, and you upload only those.

**Read this first, alone.** It is small on purpose. Give it to a model with your request and nothing else;
the model tells you what to upload, and only then do you upload.

---

## 1. How a change happens

```
  You                              Model
   |  ARCH_M + "what I want"   ->   |
   |                                |  routes the change (§3)
   |  <- "upload these bundles"     |
   |  those .md files          ->   |
   |                                |  writes the change
   |  <- changed files only         |
   |  apply, build, report errors ->|
```

**Five rules that keep it cheap:**

1. **Never upload a bundle the routing table did not name.** Extra context makes answers worse, not better —
   a model given the whole app writes vaguer code than one given the four files that matter.
2. **Take back changed files only**, never the bundle. A bundle is an input format; the output is a diff.
3. **Complete files, never fragments.** A file is the unit of exchange in both directions. See §7's entry on
   the patch that deleted a harness: a fragment carrying a `.dart` extension will be applied as a file,
   because that is what it looks like.
4. **The ARB comes back as a patch.** It is 3,243 lines and 4% of the codebase for two new strings. The model
   returns the new keys as a JSON fragment and you merge them; see §5.
5. **Build after every round.** Every plugin surface in this project has needed at least one correction the
   analyzer found and no amount of reading could have.

---

## 2. The bundles

> **The line counts below are a snapshot and are stale after any applied change.** They predate the reminders
> timezone work and the recipe measure work, which between them touched `B1_CORE`, `B3_DOMAIN`, `B4_DATA`,
> `B5_APP`, `B6_SHARED`, `B7_TESTKIT`, `F_OPS`, `F_RECIPE` and `ARB`. Regenerate per §8; `_manifest.json`
> holds the authoritative file list.

| Bundle | Files | Lines | Contains |
|---|---|---|---|
| `B1_CORE` | 31 | 2,707 | Money, Qty, Measure, DateKey, Result, ids, enums. No Flutter, no drift. Everything depends on this and it depends on nothing. |
| `B2_SCHEMA` | 46 | 8,470 | Drift tables, converters, migrations, DAOs. **Change this and you change the database** — read ARCH_2 §13 before touching a column. |
| `B3_DOMAIN` | 64 | 10,296 | Entities, repository contracts, service contracts and the pure engines. No Flutter, no drift, no data/. |
| `B4_DATA` | 47 | 8,672 | Repository implementations, security, backup, platform channels, reminders. Everything that talks to a plugin or the disk. |
| `B5_APP` | 19 | 3,173 | Router, providers, theme, bootstrap. **The router imports every screen**, so a new screen always touches this bundle. |
| `B6_SHARED` | 32 | 3,860 | The widget vocabulary — AmountText, DateText, QtyText, MeasureText, AlayaBottomSheet, AlayaFormScaffold, EmptyState and the rest. |
| `B7_TESTKIT` | 17 | 4,712 | Test harnesses, fakes, pumpers, the layout-overflow suite and the layering checker. |
| `B8_ANDROID` | 5 | 378 | MainActivity, the SAF platform channel and the Gradle files. **The manifest is not here** — see §3's Android row. |
| `F_EXPENSE` | 38 | 6,466 | Transactions, lines, tags, payees, the ledger and the editor. The largest feature. |
| `F_INVENTORY` | 24 | 4,042 | Items, batches, stock movements, consume/waste/adjust. |
| `F_SHOPPING` | 17 | 2,925 | Shopping lists and entries, and the convert-to-purchase flow. |
| `F_RECIPE` | 11 | ~2,900 | Recipes, ingredients, steps, the editor's measuring controls. **Coupled to `F_INVENTORY`**: cookability reads stock, cooking deducts it, and the spoon conversions live on `items` |
| `F_RECURRING` | 19 | 3,246 | Recurring templates and occurrences. |
| `F_SERVICE` | 20 | 4,187 | Assets, service records, warranties. |
| `F_DASHBOARD` | 16 | 2,132 | Funds header, module grid, insight cards, the dashboard calendar. |
| `F_CALENDAR` | 9 | 1,863 | The calendar screen and its day sheet. |
| `F_ANALYTICS` | 24 | 4,723 | The analytics home, its 24 query surfaces and the drill-down. |
| `F_SETTINGS` | 38 | 7,325 | The settings tree and every branch, plus onboarding, PIN setup, lock and recovery. |
| `F_OPS` | 14 | 2,517 | Backup, restore, trash, reminders, attachments and Support Us. |
| `F_SPLIT` | ~40 | — | Shared expenses: the resolver, the simplifier, balances, groups, settlements. Spans `lib/features/split/**`, `lib/domain/services/split/**`, `lib/domain/entities/split_*.dart`, `lib/data/daos/split_*.dart`, `lib/data/repositories/split_*.dart`. **`make_bundles.py` was rewritten to emit this and, for the whole of the split cycle, never produced it** — so every session began by pasting files a bundle should have carried, several of them twice. |
| `ARB` | 1 | 3,243 | Every user-visible string. **Upload only when a change adds or edits one**, and take back a patch rather than the whole file. |

**Layering (Law L12), and why the dependency arrows only point one way:**

```
  B1_CORE  <-  B3_DOMAIN  <-  B4_DATA  <-  B5_APP
                    ^                          ^
                    |                          |
              F_* features  ------------>  B6_SHARED
```

`B5_APP` is the only bundle that imports every feature — the router names every screen. That is why a new
screen always touches it, and why it is deliberately small (19 files) rather than merged into anything.

**`B6_SHARED` may import domain entities**, and does — `qty_field.dart` and `measure_text.dart` both take a
`Unit`. That is not a violation: the arrow from `F_*` to `B6_SHARED` is about who consumes whom, and a shared
widget rendering a domain value needs to name its type. `B1_CORE` is the bundle that imports nothing, which
is why arithmetic belongs there and not in a feature.

---

## 3. The routing table

Find the row that matches your change. Upload exactly what the **Bundles** column names.

| I want to… | Bundles | Lines | Why |
|---|---|---|---|
| Change how a screen **looks** — spacing, an added field, a reordered row | `F_<feature>` + `B6_SHARED` + `ARB` | 7,103 | The widget vocabulary plus the feature. `ARB` only if a string changes |
| Fix a **bug** you can point at a screen for | `F_<feature>` + `B6_SHARED` | 3,860 | Add `B3_DOMAIN` if the wrong number is arithmetic rather than display |
| Change a **calculation** — a total, a projection, a conversion | `B3_DOMAIN` + `B1_CORE` | 13,003 | Engines are pure and live in domain. No UI needed to change one |
| Change **how a number is displayed** — a format, a rounding, a unit | `B1_CORE` + `B6_SHARED` + `F_<feature>` | 9,470 | The formatters are core and the single path to pixels is shared (Law U7). A feature that formats for itself is how two screens come to disagree — see §7 |
| Add a **column** to an existing table | `B2_SCHEMA` + `B3_DOMAIN` + `F_<feature>` + `ARB` | 22,009 | **Read ARCH_2 §13 and §8 below.** Schema is at **v3**. A migration is forward-only, `stepByStep` will demand a new `fromNToM`, and seeded rows need the seed **and** the migration |
| Add a whole **new feature** with its own table | `B1_CORE` + `B2_SCHEMA` + `B3_DOMAIN` + `B4_DATA` + `B5_APP` + `B6_SHARED` + `F_<nearest>` + `ARB` | 40,421 | The nearest existing feature is the pattern to copy. See §4 |
| Add a **screen** to a feature that exists | `F_<feature>` + `B5_APP` + `B6_SHARED` + `ARB` | 10,276 | `B5_APP` because the router must learn the route |
| Change **wording** only | `ARB`, then `B7_TESTKIT` + whichever feature bundle fails | 3,243+ | **The ARB alone writes the copy; it does not finish the job.** Every test asserting a changed string breaks, and those live in feature bundles you cannot predict. Patch, run the suite, fix what fails |
| Change **theme, colour or typography** | `B5_APP` + `B6_SHARED` | 7,033 | Tokens live in `app/theme`; the widgets consume them. **Then `flutter test --update-goldens`** — four golden files compare pixels, so any width or type change fails them and no `grep` can predict which |
| Change **navigation** — a new tab, a moved destination | `B5_APP` + `B6_SHARED` | 7,033 | `alaya_drawer` and the shell scaffold are in shared |
| Change **backup, restore, trash, reminders or ads** | `F_OPS` + `B4_DATA` + `B3_DOMAIN` + `B5_APP` | 24,658 | The ports are in domain, the plugin adapters in data. **`B5_APP` because `bootstrap()` is where a scheduled obligation is armed**, and without it you cannot tell "no caller" from "a caller I cannot see" |
| Change **PIN, lock or onboarding** | `F_SETTINGS` + `B4_DATA` + `B5_APP` | 19,170 | `B5_APP` because both gates are resolved in `bootstrap` and wired in `app.dart` |
| Fix a **test** | `B7_TESTKIT` + `F_<feature>` | 4,712 | Harnesses and fakes are in the test kit |
| Change **Android config** — icon, permission, signing, Gradle | `B8_ANDROID` | 378 | Plus `android/app/src/main/AndroidManifest.xml` and `proguard-rules.pro`, which are **not in any bundle** — paste them. `B8_ANDROID` holds the Gradle files and Kotlin, not the manifest |

**If two rows apply, take the union.** If none does, upload `ARCH_M` alone and ask — routing a change is
cheaper than guessing at it.

**A union of three is normal for anything about numbers.** The recipe measure work took *looks* + *calculation*
+ *how a number is displayed*, which is `B1_CORE` + `B3_DOMAIN` + `F_RECIPE` + `B6_SHARED` + `ARB`. Splitting
it by layer (§4's advice) mattered more than trimming it.

---

## 4. Adding a feature — the recipe module, worked

> **This module was built, and then revised five times.** The split below is what actually happened,
> corrected for what went wrong. The revisions were not schema errors — they were the interaction: an
> ingredient with no way to name its unit, a picker that hid the units the schema existed to support, and
> a rounding bug that read as a missing feature. **Budget for the UI to need more rounds than the data.**
>
> Corrected for what went wrong:
> session 2 needed all of `B2_SCHEMA`, and session 3 had to be halved because the wiring alone is ~1,500 lines of
> carried files. Screens and tests arrived last, and the ARB patch had to ship with the screens that referenced
> it rather than after — `flutter gen-l10n` fails on a referenced key that does not exist.
>
> **The measure rework confirmed the ratio.** The arithmetic took one session and landed green first time; the
> three screens consuming it took three, and two of those rounds were spent on my own test expectations rather
> than on the code.

Your example: *recipes, connected to inventory, telling me what I can cook.* It is a good test of this
architecture because it touches every layer.

### What it needs

| Layer | Work |
|---|---|
| `B2_SCHEMA` | `recipes`, `recipe_ingredients`. Both need `deletedAt`, `createdAt`, `updatedAt` (ARCH_2 §2) and a migration |
| `B3_DOMAIN` | `Recipe`, `RecipeIngredient` entities; `RecipeRepository` contract; a `CookabilityEngine` that answers *can I make this* from stock |
| `B4_DATA` | `RecipeRepositoryImpl` over a new DAO |
| `F_RECIPE` | List (archetype D), detail, editor (B), ingredient picker |
| `B5_APP` | Routes, providers, a drawer destination |
| `ARB` | Every string |

### What to upload

```
ARCH_1_FOUNDATION.md   ARCH_2_DATABASE.md   ARCH_5_UIUX.md   ARCH_M.md
B1_CORE  B2_SCHEMA  B3_DOMAIN  B4_DATA  B5_APP  B6_SHARED
F_INVENTORY          <- the pattern to copy, and the module you are joining
ARB
```

Roughly 44,000 lines. Large, but it is a whole feature and it is **once** — the follow-up rounds need only
`F_RECIPE` and whatever the build complained about.

**`F_INVENTORY` is there for two reasons**, and the second matters more: it is the closest existing feature, so
its shape is the pattern to copy, *and* cookability reads stock — so the model needs the real
`InventoryRepository` surface rather than an invented one. Every wrong-API failure this project has had came from
writing against a remembered signature.

### Split it across sessions

A whole feature does not fit one useful response. Split by layer, and build between each:

| Session | Upload | Produces |
|---|---|---|
| 1 | ARCH_1, ARCH_2, ARCH_M, `B1`, `B2`, `B3` | Tables, migration, entities, repository contract, engine |
| 2 | ARCH_M, **all of `B2_SCHEMA`**, `B3`(new), `B4` | DAO, repository implementation. The whole schema bundle, not just the new files: a DAO cannot be written without reading one, and `alaya_database.dart` is an existing file you will be modifying |
| 3 | ARCH_5, ARCH_M, `B3`(new), `B5`, `B6`, `F_INVENTORY` | Screens, providers, routes |
| 4 | ARCH_M, `F_RECIPE`, `ARB`, `B7_TESTKIT` | Tests, strings |

**Build after each.** A schema error found in session 1 costs one round; found in session 4 it invalidates
everything downstream.

**Put the pure arithmetic in its own session, first.** It changes no screen, so it cannot break anything, and it
settles the questions the UI will otherwise re-open three times. The measure rework did this and session 1 was
the only round of four that needed no correction.

---

## 4b. Two couplings the bundle table does not show

The routing table treats features as independent. Two are not, and both will surprise a change that
assumes otherwise.

### Recipe ↔ Inventory

**Cookability reads stock and cooking deducts it**, so `F_RECIPE` cannot be reasoned about alone:

| Where the coupling lives | What it means for a change |
|---|---|
| `CookabilityEngine` reads `ItemStock` and `Item` | A change to either entity changes what recipes report |
| `RecipeCookService` calls `StockRepository.consume` | FEFO ordering and the shortfall refusal are inventory's, not the recipe module's |
| **`items.densityMilliGramsPerMl`** and `items.milliGramsPerPiece` | The spoon conversions live on the *item*. Editing them is an `F_INVENTORY` change that alters recipe behaviour |
| `items` fields drive which units a recipe row offers | Removing a column would silently shrink the unit picker |
| The item editor asks **"one tablespoon weighs ___ g"** | Not a density. One number derives every volume unit — 8 g/tbsp gives 2.7 g/tsp and 130 g/cup — and a per-unit table would let tsp and tbsp disagree about the same substance |

**Touching recipes usually means uploading `F_INVENTORY` too.** Not for the pattern — for the real
surface, because every wrong-API failure in this project came from writing against a remembered one.

### Dashboard ↔ everything

`F_DASHBOARD`'s module grid counts rows from six features and its tile census asserts every label. Adding
a feature means a tile, a count provider, **and** two numbers in `module_grid_test.dart` — the tile count
and the name list. A tile with a blank label passes the count check on its own.

---

## 4c. Where the schema stands

**v4.** The snapshots in `lib/data/db/migrations/schema/` are `v1` through `v4`, and `stepByStep` in
`migration_strategy.dart` carries `from1To2`, `from2To3` and `from3To4`.

| Version | Added |
|---|---|
| v1 | 26 tables |
| v2 | `recipes`, `recipe_ingredients`, `recipe_steps`, `recipe_cook_log` |
| v3 | `items.density_milli_grams_per_ml`, `items.milli_grams_per_piece`, and the `tsp`/`tbsp`/`cup` units |
| v4 | the five split tables, fourteen indexes, four views, and a `splitSettleBy` arm on `v_calendar_events` |

**Adding v5 makes the build fail until a `from4To5` exists**, which is the property worth having: a
forgotten migration is a compile error rather than a crash on a user's device.

Two things about v4 worth stating rather than leaving to be rediscovered.

**Both arms of `v_split_balances` are only reachable if a screen can write both.** The "I owe" arm depends
on `paid_by_payee_id <> split.selfPayeeId`, and the bill screen hardcoded the payer to the user for the
whole first cycle — so that arm never fired, "You owe" was structurally zero, and *nothing on screen could
contradict a second bug sitting in the other arm*. A view arm with no writer is not a view arm.

**`PayeeKind.splitPlaceholder` was added with no migration at all, deliberately.** `SafeEnumConverter`
stores an enum by `name`, so a new member costs nothing — which is exactly why Law L13 forbids *renaming*
one while adding is free. Recorded here so the next person does not reach for `dart run drift_dev schema
dump` out of habit.

Two things that must both happen for a seeded row: `seed_data.dart` for new installs, the migration step
for existing ones. `INSERT OR IGNORE` keeps the migration re-runnable.

**Both of the last two changes avoided v4, and the avoidance was the design.** Fractional spoon amounts could
have been stored as an exact numerator and denominator; they are stored as the existing `Qty` and reconstructed
on read instead, because the error is a thousandth of a teaspoon and the migration would have bought correctness
nobody can taste. Ask what a schema change buys in units a user can perceive before taking one.

---

## 5. The ARB protocol

`app_en.arb` is 3,243 lines — 4% of the codebase — and almost every change adds two or three strings to it.
Uploading and returning it whole is the single most wasteful thing this workflow can do.

**Upload it when a change adds or edits a string. Take back a patch.** The model returns only:

```json
{
  "recipeTitle": "Recipes",
  "recipeCanCook": "{count, plural, =0{Nothing you can make} =1{1 recipe} other{{count} recipes}}",
  "@recipeCanCook": { "placeholders": { "count": { "type": "int" } } }
}
```

You merge it. Any editor does this; so does:

```bash
python3 - <<'EOF'
import json, collections
arb = json.load(open('lib/app/l10n/app_en.arb'), object_pairs_hook=collections.OrderedDict)
arb.update(json.load(open('patch.json'), object_pairs_hook=collections.OrderedDict))
json.dump(arb, open('lib/app/l10n/app_en.arb','w'), indent=2, ensure_ascii=False)
EOF
flutter gen-l10n
```

**The check that matters**, run before you accept any change that touched strings:

```bash
python3 tool/check_arb_keys.py            # missing keys, with file:line for every site
python3 tool/check_arb_keys.py --unused   # keys nothing references
```

That tool replaced a two-command shell pipeline that had two independent faults, and both produced a wrong
answer rather than a noisy one:

1. **`sort` and `comm` disagreed on collation.** One out-of-step line and `comm` began reporting keys as
   missing that were present — three of them, all in the ARB — then aborted, so the run was *silent* about
   everything after the desync rather than clean. `LC_ALL=C` on both fixes it; doing the comparison in Python
   removes the question.
2. **It grepped raw source, so it matched comments** — in direct contradiction of §7's own rule about exactly
   this hazard, three sections below it in the same document.

**Run `--unused` as well, and read it.** `recipeAmountHint` and `recipeAmountHintVessel` both read like
promises of fraction input and were referenced by nothing, written for a field that could not accept any of it.
An unused string is the same fault as an unreachable method, one layer down — and §7's tool does not see the
string table.

---

**Run `check_arb_keys.py --unused` in the same session as any change that renames or removes a rendered
string**, not at the end of a cycle. The split cycle added roughly sixty keys and orphaned at least six —
`splitTapToSettle`, `splitQuickAddNames`, `splitTipTotal`, `splitTipPercent`, `splitNameEveryoneToSave` and
the `splitSettingsUpi*` set — and by the twelfth round a key orphaned in the third is indistinguishable from
one that was never used at all.

## 6. Rules a change must not break

Any model touching this codebase inherits these. They are not style preferences; each one was paid for.

| Rule | Where |
|---|---|
| `features/` never imports `data/` — a plugin gets a port in `domain/services/` first | ARCH_1 §6 |
| The database is **plaintext**. No encryption, no `PRAGMA key`, ever | ARCH_1 §2.1 |
| `drift_dev` is the only codegen. Never `@riverpod`, never `go_router_builder` | ARCH_1 §7.3 |
| Never hand-write a version, never use `any`. **Never add `file_picker`** | ARCH_1 §7.4 |
| One open path for the database: `openAlayaDatabase` | Law L10 |
| `TrashAdapter._hardDelete` is the only hard delete in the codebase | ARCH_3 §4.2 |
| The backup warning is ARCH_3 §3.4 verbatim, on every export, every time | ARCH_3 §3.4 |
| Every screen implements loading, empty, error and populated | Law U4 |
| No string literal, raw colour, spacing, radius, duration, icon size or text style | Laws U5, U6 |
| Money through `AmountText`, Qty through `QtyText`, DateKey through `DateText`, a Measure through `MeasureText` | Law U7 |
| Every list virtualised | Law U13 |
| A new route must have a widget that navigates to it | ARCH_5 §9.2 |
| Routing state is resolved in `bootstrap()` before the first frame, and screens navigate explicitly after an action | §7 below |
| **A formatted number is not copy.** A time, a fraction, a decimal separator go through a formatter, not the ARB — but the *sentence* explaining one does go through the ARB | §7 below |
| **No value is displayed from a second source.** If a screen shows a stored figure, it reads that figure — not the input the figure was derived from | §7 below |

---

## 7. What has actually gone wrong, so it does not again

Each of these cost a build cycle or reached a user. A model reading this file should treat them as
the project's real failure modes rather than hypotheticals.

### Plugins and platform

**An awaited plugin call is not a completed one.** `RewardedAd.load`, `requestConsentInfoUpdate` and
`initialize` all dispatch and call back. `await` proves nothing and the compiler cannot help. Read the SDK's own
sequence, not its type signatures.

**This project's `flutter_local_notifications` is named-only, everywhere.** `zonedSchedule`, `cancel` and
`initialize` all refuse positional arguments. Assume named first.

**`initializeTimeZones()` does not choose a zone.** It loads the database; `tz.local` stays UTC until
`setLocalLocation` is called, and for months nothing called it. Every digest was therefore booked against UTC
wall time — 5½ hours late in India, 8 early in California, a day out in Auckland — while the screen displayed
the hour the user had picked. **No number anywhere was wrong.** The schedule was internally consistent and
externally hours off, which is why four rounds of investigation preceded the one-line cause.

**The device's zone is resolvable in pure Dart, and a plugin is the wrong tool here.** `dart:core` knows the
device's offset at any instant including DST, so sampling it across fourteen months and matching every zone in
the database identifies the zone behaviourally. That matters for two reasons that are not about dependencies: a
platform channel registered in `MainActivity` is **not registered in the `workmanager` isolate**, which is the
caller that matters most after a reboot; and a channel cannot be exercised in a widget test, so a fix built on
one inherits the untestability that let the bug live.

**`+ Duration(days: 1)` is not tomorrow.** A `Duration` is elapsed time, so adding 24 hours across a DST
boundary moves the wall clock by an hour and a 9am reminder becomes 8am for six months. Overflow the day field
and let the date type resolve the civil date. Invisible in India, which has no DST; live for a third of the world.

**An alarm does not survive a reboot; a `WorkManager` job does.** So a daily recompute is not a re-arm, and
between a restart and the job's next run there is nothing scheduled and nothing saying so. The user reports "it
worked, then it stopped."

**A `final class` cannot be faked.** Check before designing a test strategy around one — it is why seven ports
exist.


**A resource reached by name is invisible to the shrinker, and the failure is release-only.**
`isShrinkResources = true` keeps a drawable when something *references* it — `R.drawable.foo` in compiled
code, or `@drawable/foo` inside another resource. `flutter_local_notifications` resolves its icon with
`getResources().getIdentifier("ic_notification", "drawable", packageName)`, and the only mention of that name
in the project is a **Dart string**. aapt2 does not read Dart; R8 does not read Dart. So nothing static points
at the drawable: it is merged, carried as far as `build/app/intermediates/packaged_res/release/`, and dropped
before the APK is written.

`initialize` then throws `PlatformException(invalid_icon, ...)`, and every call touching the plugin fails with
it — switches that will not stay on, a digest that never fires, a test notification that never arrives, **in
release only.** Debug does no shrinking, so all three work there, which is what makes it slow to find.

The remedy is the shrinker's own escape hatch: `android/app/src/main/res/raw/keep.xml` carrying
`tools:keep="@drawable/ic_notification"`. It must be under `raw/` — anywhere else is silently ignored, which
fails exactly like doing nothing.

**Any resource this app names as a string needs a line in that file.** A channel icon, a custom sound, a
per-kind glyph. Nothing will fail until release and nothing will name the cause.

**And the reference itself is a name, not a path.** The constant read `'@drawable/ic_notification'` — XML
syntax, valid in a manifest or a layout and nowhere else. `getIdentifier` wants `ic_notification` and matches
nothing against the `@` form. Both spellings look equally plausible in review, and the wrong one felt right
because it *is* right four files away, in `AndroidManifest.xml`, edited in the same change.

### Screens that agree with themselves

**A screen must not report its input as its output.** The reminders row printed the digest time from the
*settings object passed down from its parent* while claiming to show what the OS held; the recipe row rendered
a date from a UTC conversion and a time from the settings above it. In both cases every value on screen agreed
with every other and all of them were wrong together. **Two controls showing one fact from two sources is the
bug**, and it is invisible by construction — the screen answers the question by reading it back.

**A screen showing the app's own record cannot report the app's own failure.** `watchScheduled` read the
`notification_schedule` table, which is written *before* `zonedSchedule` is called and never reconciled against
it. A digest the OS refused looked identical to one it accepted. Where a screen reports on something external,
one value must come from the external thing — `pendingNotificationRequests` here — and that value is the only
one that can contradict the others.

**A snapped or rounded display must say so.** Recipe amounts snap to what a measuring set can produce when
servings scale them, and the row carries `≈`. One character is the whole cost of not asserting that a derived
figure is the stored one. Show the mark **only when the rounding happened**, so it is informative rather than
decorative.

**A redirect is a guard, not a navigation mechanism.** Three bugs reached the user from screens that changed a
router gate and waited for the redirect to carry them. Resolve routing state in `bootstrap()`; navigate
explicitly after an action.


**A capability with no affordance is a missing feature, however well it works.** Recording a repayment was
reachable only by tapping a balance row — no button, no icon, no chevron. A card with none of those reads
as a list item, and the one sentence saying otherwise sat centred and muted *below* every row, off screen
the moment somebody had four balances. It was reported as absent. It was not absent; it was unmentioned.

Three times in one module: the settings redirect chain, *"Who is this?"* offering no way to pick an existing
person, and this. **No test can catch it** — the handler works, the sheet works, the transaction works.

**A default in a shared widget is a decision made for callers who will never see it.** `PayeeSheet` defaults
a new payee to `PayeeKind.merchant`, which is right for the expense editor and wrong throughout the split
module, where `splitPeopleProvider` filters to `person`. Everybody added from a split screen was filed as a
shop and vanished — emptying the picker, emptying the "which person is you" list, leaving
`split.selfPayeeId` unsettable, and making **saving a split impossible**. One wrong default, four steps
upstream of the symptom. When reusing a widget across features, read its defaults before its API.

### Tests

**A `Stream.value` fake cannot exercise a loading state.** It resolves in the first frame's microtask drain.

**A lazy list hides everything below the fold**, so `findsNothing` passes for the wrong reason. Content
assertions get a tall viewport; the 320×640 gate stays narrow.

**Extending a contract obliges every implementer, including test fakes.**

**A test that names a widget class breaks on refactors that do not change behaviour.** `find.byType(QtyField)`
failed when the control was replaced for a reason unrelated to what the test protected. Assert what the user
sees — a dropdown appears, a chip lights — and the test survives the next rebuild.

**A count assertion beside a set assertion is not redundant.** `expected.difference(actual)` passes happily
when the expected set *shrinks*, so the literal `hasLength(n)` is what catches a name deleted by accident.
`findsNWidgets(6)` passes when all six chips read `1/4`; the loop over the six labels is what does not.

**A screen-wide negative finder will find the legend explaining the thing it says is absent.**
`find.textContaining('≈')` with `findsNothing` cannot pass while the sentence *"anything marked ≈ is
rounded"* is on screen. The broad finder reads as the stronger assertion and is the one that cannot hold —
scope a negative to the value, not the screen.

**Verify a test's arithmetic independently before shipping it.** An expectation that 625 thousandths snaps to
`3/4` was reasoned from halves and quarters, forgetting the set contains `2/3` between them. Recomputing every
literal in a throwaway script found it, and also found that 875 is the *only* genuine tie in that set. A wrong
expectation costs the same round as wrong code and is harder to see.

**A fixture that cannot express the bug cannot catch it.** `scheduledReminder` took a `DateKey`, so no test
could construct a schedule whose time differed from the setting — the exact divergence that shipped. The
detail-screen row took a `Qty`, so a vessel amount could not be stated as a fraction of a vessel.

**An unoverridden provider degrades to green.** A screen watching a provider the harness does not override gets
an `AsyncError`, `valueOrNull` is null, and the code path falls back silently. The suite passes and the feature
is entirely unexercised. Adding an override to a fixed-length list (ARCH_6 P5) is what makes the path reachable
at all.

**`RecipeDetailScreen` had no widget test and could not have had one** — `recipeProvider` needs a database and
the harness did not cover it. The screen a user reads while cooking rendered `7 ml` for half a tablespoon
through every green run of the suite. **Check whether a screen appears in any test before trusting the suite
about it.**


**A snack shown after `Navigator.pop()` is never shown.** `PayeeSheet` popped, then checked
`context.mounted`, then showed the result — and a sheet's context is unmounted the instant it pops, so both
the success and the failure message were dropped. A duplicate-name refusal, the one message that explains
why nothing happened, had never once been visible.

`ScaffoldMessenger` lives above the route, so showing before popping works. The guard that caused the
silence is correct almost everywhere else, which is why it survived review.

**`@override` on a member the supertype does not declare is a lint, not an error.** So `flutter test` passed
on an implementation whose contract had never been extended, and I read that as evidence the declaration was
there. Only a *caller* surfaced it. After adding to any interface, reconcile both sides by name:

```bash
grep -rn 'implements SplitLedgerRepository' lib test
```

### Editing and searching

**A `grep` for a symbol matches comments that mention it.** Strip comment lines before searching. This produced
four false findings in one phase, has broken an edit script five times, and is the fault §5's own snippet
carried until it was replaced.

**`sort` and `comm` do not agree about order.** A locale-collated sort feeding `comm` produces invented
differences and then aborts, so the output is both wrong and truncated. `LC_ALL=C` on every stage, or do the
comparison in a language with sets.

**A `.replace` that matches nothing succeeds.** It returns the string unchanged and reports nothing, so the
next edit lands on text the first was meant to have removed. Assert that each edit **applied**, not merely
that the result looks right — and strip comment lines first, because a replacement comment explaining a fix
routinely contains the symbol the assertion is checking has gone.

**A slice to end-of-file assumes the target is last.** Replacing `s[s.index(marker):]` deleted an entire
widget class that happened to follow the helpers being swapped. **Balanced braces do not catch it** — a
removed class takes its braces with it. Compare the list of top-level declarations before and after, or
append instead of replacing a range.

**A fragment with a `.dart` extension will be applied as a file.** A "patch" containing one function and a
comment block explaining where it went replaced a 520-line test harness, deleting four fakes, two pumpers and
every fixture — about a hundred analyzer errors from one paste. The instructions were in comments, where a human
reads them and a filesystem does not. **§1 rule 3 exists because of this.** If a change to a large file is
genuinely one line, describe it in prose with the exact old and new text; never in something file-shaped.

**Bundles go stale, and a stale bundle looks authoritative.** `F_RECIPE.md` was regenerated before a fix and
then used after it, so it described code that no longer existed. Regenerate the bundles a change touched
immediately after applying it — §8 is not advice, it is the thing that went wrong.


**Filtering in a screen leaves every other reader of that provider stale.** Placeholder payees were filtered
inside `PayeesSettingsScreen`, so the list showed one row while the settings tree said *3 payees* — both
correct for what they read. Moving the filter into `payeesSettingsProvider` fixed both and broke a harness
that overrode it with a stream, because the shape had changed as well as the source.

What survived both attempts: **name the predicate once and let every reader call it.** `isContactPayee` sits
beside the provider, both readers call it, and the provider's type never changed.

**A multi-line regex over structured code is a guess about where the structure ends.** Deleting three
`GoRoute` blocks with `(?:[^\n]*\n)*?` ate 141 lines instead of 19, taking `/split`, `/split/new` and
`splitGroupNew` with them. The verification caught it — `SplitBillScreen kept: False` — and the second
attempt walked **brace balance** to find each block's span, naming 4, 6 and 6 lines before writing anything.
The parser knows where a block ends; the pattern is guessing.

### Reachability

**The recurring fault is not missing code — it is code nothing reaches.** Discovered by users reporting missing
features rather than by anything in the build:

| Capability | Built | Reachable |
|---|---|---|
| `QuickAddSheet` | golden-tested, layout-tested, documented | never opened; every add button pushed the 11-control editor |
| `ShoppingActions.delete` | soft-delete, correct | no UI called it |
| `BalanceService.convertOne` | doc comment names the row it is for | zero callers |
| `AppLock.changePin` / `disable` | full contract, verified against `currentPin` | **no callers anywhere — a PIN cannot be changed or removed** |
| `ReminderPort.refreshSchedule` | worked, returned a count | **resolved.** Now called from `bootstrap()`, the daily job and the screen, and the count reaches the user in a snackbar |

**The recipe measure work found six more in one feature area, forming a chain:**

| Capability | Reachable |
|---|---|
| `parseAmountMilli` — accepted `1 1/2`, `3/4`, `.5` | no callers. The field it was written for used `int.tryParse` |
| `UnitConverter.parseToMilliBase` — lenient decimal→milliBase, half-up | no callers |
| `UnitRepository.factorsByCode` — the map `UnitConverter` needs | no callers |
| `recipeAmountHint`, `recipeAmountHintVessel` — ARB strings promising fraction input | no references |
| `RecipeDetailScreen` | in no test file |

Every piece of a working feature existed and none of it was connected. **The feature was not missing; it was
never wired.** When a user reports something as absent, grep for it before writing it.

**A tested-but-unreachable capability is the dangerous kind**: the suite is green, the code is proven, and
the feature does not exist. Nothing in a build or a test run can see it, because a test *is* a caller.

`tool/reachability.py` finds them, and **the hand-maintained list above was five while the tool reported 41.**
Run it before declaring a feature done, and read the output as a list to check rather than a list of bugs — a
deliberately dropped method (ARCH_4 §5.1 item 13 dropped `watchTotalInHomeCurrency`) belongs on it too, and the
fix for that one is deletion.


**Adding an enum member: the compiler finds every exhaustive `switch` and no loop at all.**
`PayeeKind.splitPlaceholder` broke `payeeKindLabel` immediately — Law L13 working — and said nothing about
`PayeeSheet`'s chip row, which iterates `PayeeKind.values` and offered *"Unnamed on a split"* as a kind a
user could assign to a real contact. After adding to an enum:

```bash
grep -rn '<EnumName>.values' lib
```

**Two capabilities existed with no caller in one cycle**, each found only when somebody asked for the feature
it already implemented. `SplitLedgerRepository.watchActivity` took a nullable `groupId` that nothing ever
passed null, so a split filed under no group appeared on no screen. `SplitExpenseService.record` took an `id`
documented as *"supplied when re-saving an existing split"* that no screen supplied, so editing needed no new
domain code — only a caller.

`reachability.py` finds unreachable code. **It does not find unreached parameters**, and those read as
finished work in every review.

### Arithmetic

**Truncating integer division breaks a round-trip.** Half a tablespoon is 7393.5 milli-millilitres; stored
as an integer and divided back it returns 499, not 500 — so a field showed `0.499` and a chip never
highlighted. **Whole numbers survived**, which made an arithmetic bug look like a missing feature. Round
in both directions, and test with the awkward factors: 240000 divides cleanly and would have passed, 4929
and 14787 do not.

**Recognition by round-trip beats a table of known values.** A remainder was matched against nine hardcoded
thousandths and anything else rendered as a decimal, so `1/16` displayed as `0.062` and every new fraction
needed a code change. Accepting `p/q` if and only if storing it reproduces the same value needs no table, finds
every fraction a kitchen has, and returns null honestly when the value is not a simple fraction at all.

**Two rounding directions in one feature must be reconciled explicitly.** `CookabilityEngine.scaleMilli` takes
a ceiling because a false "you have enough" ruins dinner. A display that rounded to nearest would show less than
the verdict demands. `Measure.scaled` rounds up for that reason and says so, because the arithmetic is
duplicated across a layer boundary that forbids the import.

**Truncating integer division breaks a round-trip** — and so does a nullable field read after a method that
always assigns it. Return the value rather than only storing it; a later edit will otherwise reintroduce the
crash the type system was willing to prevent.

**An enum value that reads naturally may not exist.** `ItemKind.grocery`, `StockMovementKind` — check the
declaration. Before delivering, sweep every `Enum.value` in the change against the enum's real members; it is
one pass and it catches the whole class.

**Dart imports are not transitive.** A symbol that resolves because a neighbouring file imports it does not
resolve in this one. Harnesses hide this especially well: the harness imports everything, the test file imports
the harness, and the test file's own symbols go unnoticed until the compiler objects. **An extension type needs
its declaration in scope for its members to resolve**, so a `DateKey` whose `addDays` is called keeps the import
alive even when the type is never named.

### Layout

**`ListTile` is the wrong widget for a row carrying a value.** Its `trailing` slot is unbounded, so at textScaler
2.0 it throws *"trailing widget consumes the entire tile width"* — and every render object below it then fails to
lay out, turning one bad row into sixteen exceptions. `item_row.dart` reached this conclusion first and uses
`InkWell` → `Row` → `Expanded` with a `stacked` branch above 1.5.

**A `Row` of fixed-size children has no strategy for growth.** The 320dp × 2.0 gate roughly halves usable width.
Two filter chips overflowed by 434px. `Wrap` when children can reflow, `Expanded` when one should absorb the
slack, an explicit `stacked` branch when neither is enough. A `Wrap` with a spacing token also removes the
separator string a `Row` needed, which Law U5 wanted gone anyway.

**A positional key is the wrong key for a list you can delete from.** Two `ValueKey<int>(0)` siblings crash
outright, which is the mild failure. The quiet one: delete row 0 and row 1 inherits its element, so a
`TextFormField` keeps showing the deleted row's text — `initialValue` applies on first build only. Give drafts an
id when they are **created**, not when they are saved.

**`TextInputType.number` has no `/` key.** A field intended to accept `1/2` and typed as numeric is a fraction
feature that cannot be used on the only platform this app ships to. Check the keyboard before concluding the
parser is at fault.

**`SectionHeader` renders `label.toUpperCase()`.** A test asserting the ARB's sentence case is testing the
string table rather than the screen. Cost two rounds in two different sessions.

### Migrations

**`onUpgrade` must be wired, not merely generated.** `schema_steps.dart` contained a working v1 -> v2 step
for three phases while `migration_strategy.dart` still threw — so any device holding a v1 database could not
open the build at all. The file *mentioned* `stepByStep` in a doc comment, which is why a quick look said
"wired". Grep for the call, not the name.

**Seeded reference data needs both `onCreate` and `onUpgrade`.** They are two routes to one destination and
neither substitutes for the other: seed-only reaches new installs and never existing ones, migration-only
does the reverse. I shipped the second and wrote a confident comment asserting it was correct.

### Judgement

**Do not gate creation on configuration.** The recipe editor hid spoons until the item declared what a
tablespoon of it weighed — so writing a recipe required configuring inventory first, and the option simply
was not there. Offer everything; explain what cannot be checked, and name the field that would fix it.

**Write an API from the declaration, never from memory.** In one session I invented `Money(minorUnits:)`
(it is positional, and the field is `minor`), `RateQuality.stale`, `Icons.approximate_outlined`,
`Icons.tilde`, `AssetEditorState.warrantyUntil`, `ItemKind.grocery` and `strings.labelRemindDaysBefore`; in
another, `recipeAmountHintFraction`, which already existed twice under other names. Every one would have taken
ten seconds to check and each cost a round. **A second guess after the first fails is worse than the first** —
when a name is wrong, read the file rather than trying another name.

**When a pinned dependency is newer than what you know, look it up.** `flutter_local_notifications` at 22.2.0
and `timezone` at 0.11.1 are both past any remembered surface. The version lives in `pubspec.yaml`, which is in
no bundle, and the answer to "does this API still take these arguments" is in the changelog rather than in
recall.

**Counting tokens tells you nothing about structure.** Four failures passed a balanced-brace check: a
deleted class took its braces with it, a spread block cut open re-closed inside another list, a method
inserted into another method's body, and an override passed as an argument instead of a sibling. What
catches these:

| Check | Catches |
|---|---|
| Per-character depth walk, reporting the line where depth goes negative | genuine imbalance |
| Which class each method is *declared* in, versus which calls it | a method in the wrong scope |
| A door's indent versus the sibling above it | a splice across a nesting boundary |
| Overrides are direct list elements at one indent | an argument mistaken for a sibling |
| Declaration list before and after the edit | a class deleted by a slice to end-of-file |

**A partial check that reports success is worse than none**, because it stops you looking. Run every check
on every file the change touched, not on the one you were thinking about.

**The codebase's refusals are where the lessons are.** `Qty` is deliberately not a `TypeConverter`;
`date_key_filters.dart` exists because `DateKey` deliberately does not implement `int`; `item_row` deliberately
does not use `ListTile`; `QtyParser` deliberately refuses `0.5` of a teaspoon because 4929 is not divisible by
two, which is why `MeasureParser` is a sibling rather than a relaxation of it. Read for what a file *refused to
do*, not only what it does — and when a refusal is right for one caller and wrong for another, add a sibling
rather than loosening the original.

---


**Eight of these laws were already written down and I broke them anyway.** *Extending a contract obliges
every implementer*, *an unoverridden provider degrades to green*, *write an API from the declaration*, *a
grep matches comments*, *a partial check is worse than none*, *a tested-but-unreachable capability is the
dangerous kind*, *bundles go stale*, *a `Row` of fixed-size children has no strategy for growth* — each
cost a round of the split cycle, and each was in this section before that cycle began.

**The file is not the mechanism.** A law only fires if something reads it at the moment of the change, and
nothing does. The entries that actually held were the ones turned into a command — the import audit, the
provider reconciliation, the U15 gate. Prefer writing a check over writing a paragraph, and when only a
paragraph is possible, expect to break it.

**A test can agree with a bug, and then defend it.** `split_bill_screen_test.dart` asserted *"opens with
two anonymous people"*, encoding the model where the user is not a participant in their own split. Dividing
₹5,000 four ways therefore produced four strangers owing ₹1,250 each — ₹5,000 owed to you on a ₹5,000 bill,
when one of those four *was* you. The suite confirmed it on every run for weeks.

Green means the code matches the tests. It says nothing about whether either matches the world, and a wrong
test is worse than a missing one because it actively resists the fix.

**One dead code path hides bugs in the paths beside it.** `v_split_balances` has two arms, and the bill
screen could only write one of them. That made "You owe" structurally zero — the reported bug — and it also
meant nothing could contradict the over-owing in the other arm, which nobody had reported because nothing
showed it. When a feature is half-reachable, suspect the reachable half.


**Four layers, three defects, and each fix revealed the next.** The reported symptom was one sentence: *the
reminder switch turns on and immediately off.* Underneath it were an uncaught throw in
`ReminderController`, a malformed icon reference in `LocalNotificationScheduler`, and a release-only resource
shrink in `build.gradle.kts`. The drawable itself was correct throughout.

I twice announced I had found "the" cause and was twice wrong, because each defect hid the one below it. What
actually moved it forward was **making the failure speak**: five candidates were live at the start, and the
first real error message eliminated four in one run. The provider and screen changes that produced that
message were worth more than any of the individual guesses, and they are worth keeping now that the bug is
gone.

The general form: when a symptom survives a confident fix, suspect a *stack* of causes rather than a wrong
diagnosis. A screen that cannot report its own failure turns that stack into guesswork — which is Law U4's
neighbour, and the reason it cost four rounds instead of one.

## 8. Keeping the bundles current

The bundles are a snapshot. After you apply a change, they are stale — and a stale bundle is worse than no
bundle, because it looks authoritative.

**Regenerate from the repo, not from a phase document.** The repo is the truth once code is applied:

```bash
python3 tool/make_bundles.py        # see the script shipped alongside these bundles
```

Regenerate **the bundles the change touched**, not all of them. `_manifest.json` records each bundle's file list,
so a regeneration is mechanical.

**If you skip this, the next change is written against code that no longer exists** — which is the same failure
as writing against a remembered API, one level up.

**Update §2's line counts and §7's tables in the same pass.** The counts drift silently; the unreachable table
was five entries while the tool reported forty-one. A reference document nobody maintains becomes a document
nobody trusts.

---

## 9. The prompt to open a change with

Copy this, fill the first line, send it with `ARCH_M.md` **and nothing else**.

```
I want to: <describe the change in a sentence or two>

You have Alaya's maintenance architecture (ARCH_M). Do not write code yet.

1. Which routing-table row (§3) does this match, and what should I upload?
2. What will the change touch that I have not mentioned?
3. Which of §6's rules does it come near?
4. If it needs more than one session, what is the split?

Ask for anything ambiguous. Do not guess at an API you cannot see —
if you need a signature, tell me which bundle has it.
```

**Then, once you have uploaded:**

```
Here are the bundles. Write the change.

- Complete files, never fragments, never "rest unchanged", never a patch
  carrying a source-file extension.
- Only files that changed.
- ARB as a patch, not the whole file.
- Say which of §6's rules you had to work around, and how.
- If something I asked for conflicts with a rule, stop and tell me.
- Before shipping a test, recompute its expected values independently.
```

The second prompt matters as much as the first. *"Only files that changed"* is what keeps a response readable,
*"stop and tell me"* is what stops a model improvising around a Law it was told was binding, and the last two
lines were each added after a round was lost to their absence.

**A third prompt, for when a fix has not worked twice:**

```
Three fixes have landed and the symptom has not moved. Do not write a fourth.
Tell me what observation would distinguish the remaining causes, and what
each outcome would mean.
```

The reminders investigation went four rounds because each round produced a plausible fix instead of a
discriminating test. Two real bugs were fixed and the reported symptom was neither of them.
