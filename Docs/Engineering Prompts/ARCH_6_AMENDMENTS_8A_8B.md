# ARCH_6 AMENDMENTS — Phases 8A and 8B

Read this alongside ARCH_1, ARCH_3, ARCH_4 and ARCH_5. It records what those documents now get wrong, what
exists that they do not mention, and what Phase 9 will otherwise rediscover the hard way.

**Nothing here supersedes a Law.** Where an amendment touches a binding section, it says which and why.

---

## 1. ARCH_1 §7 — the package table is wrong in three places

### 1.1 `file_picker` must never be added. It cannot work in this project.

§7 pins `file_picker` to 8A. **Remove that row.** §7.4's own worked example turned out to be a live problem
rather than a historical one: the version that resolves under §7.3's analyzer cap is **3.0.4, from 2020**,
whose `android/build.gradle` calls `jcenter()` — shut down in 2021. `flutter pub add file_picker` reports
success, the analyzer is clean, `flutter test` passes, and `assembleDebug` fails.

§7 already anticipated it — *"evaluate whether a small SAF platform channel is preferable to the whole
plugin"* — and 8B built that channel. See §4 below.

**Phase 9: do not add `file_picker` for any reason.** Use `SafChannel`.

### 1.2 `image_picker` is pinned nowhere, so camera capture does not exist

Attachments pick an **existing** image through the SAF channel. Capturing one needs `image_picker`, which no
ARCH document pins. §7.4 forbids adding a package absent from the table, so 8B shipped gallery-only and the
copy says *"choose a photo"* rather than promising a camera.

**Phase 9 decision required:** amend §7 with an `image_picker` row, or leave capture out permanently. It is a
product call, not a technical one.

### 1.3 Gradle coordinates are outside §7.4's scope

§7.4 says never hand-write a version. That governs **pub**, which has `flutter pub add`. Gradle has no
equivalent, and two coordinates are now written by hand in `android/app/build.gradle.kts`:

- `com.android.tools:desugar_jdk_libs:2.1.4` — **required**; `flutter_local_notifications` uses `java.time`
  and the AAR metadata check refuses the build without desugaring enabled.
- Nothing else. **Do not add `play-services-ads`** — `google_mobile_ads` brings the version it is tested
  against, and pinning a second by hand produces a runtime `NoSuchMethodError` rather than a build error.

---

## 2. Toolchain state, which no ARCH document covers

Recorded because three build failures in 8B came from here and none from app code.

| | |
|---|---|
| Flutter | 3.44.8 stable, Dart 3.12.2 — matches §7 |
| Gradle | **9.1.0** |
| AGP | **9.0.1** |
| `android.newDsl` | **`false`** in `gradle.properties`. Flutter's Gradle plugin is not AGP-9-new-DSL compatible |
| `android.builtInKotlin` | `false` |
| `repositoriesMode` | **`PREFER_SETTINGS`**, not `FAIL_ON_PROJECT_REPOS` |
| Flutter engine repo | Declared **at settings level**: `maven { url = uri("https://storage.googleapis.com/download.flutter.io") }` |

### Why those last two matter

Flutter's Gradle plugin adds its engine artifact repository at **project** level. Under
`FAIL_ON_PROJECT_REPOS` the plugin cannot apply at all; under `PREFER_SETTINGS` it applies and its repository
is **silently ignored**, so `io.flutter:flutter_embedding_debug` becomes unresolvable. Declaring the engine
repo in `settings.gradle.kts` is what makes both work.

**Do not re-add `allprojects { repositories { ... } }` to `android/build.gradle.kts`.** It is a second
violation and, under `PREFER_SETTINGS`, would silently shadow the settings-level declarations.

### Known warning, non-blocking

```
Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): workmanager_android
Future versions of Flutter will fail to build...
```

Upstream. `workmanager` must migrate to Built-in Kotlin. **It is the only caller of `purgeExpired` and
`rescheduleAll`**, so if a future Flutter upgrade breaks it, thirty-day retention and the daily digest stop
silently. Belongs on the release checklist.

---

## 3. ARCH_3 amendments

### 3.1 §3.3 — SAF is implemented in-project, not by a plugin

Export and import both go through `lib/data/platform/saf_channel.dart` over
`android/app/src/main/kotlin/com/alaya/saf/SafPlugin.kt`. Two methods:

| | |
|---|---|
| `openDocument` | `ACTION_OPEN_DOCUMENT`, **copies into the app cache** and returns that path |
| `createDocument` | `ACTION_CREATE_DOCUMENT`, writes a given file into the chosen URI |

`openDocument` returns a copy rather than the URI because `RestoreService` runs `ATTACH DATABASE` on a
filesystem path and SQLite cannot open `content://` — and because the read grant expires with the activity
result, so a retained URI is unreadable exactly when the restore needs it.

**No storage permission is declared anywhere, and none is needed.** The manifest has zero
`<uses-permission>` entries.

### 3.2 §3.4 — the warning text is now enforced verbatim

8A shipped a paraphrase that dropped the third sentence. The ARB key `backupNotEncryptedWarning` now carries
§3.4 exactly:

> This backup is not encrypted. Anyone who opens this file can read every transaction, balance and account
> name. Only share it somewhere you trust.

`ops_screens_test.dart` asserts the third clause **by phrase**, and asserts that cancelling the sheet leaves
`exports == 0`. **Phase 9 must not reword this string.** It is the one place in the app where a requirement
says "every single time".

### 3.3 §7 — the digest text is assembled in Dart, not the ARB

A `workmanager` isolate has no `BuildContext` and no `AlayaStrings`. Passing pre-localised text into a job
that may run days later, in a locale since changed, would be worse than plain English. This is a **recorded
deviation from Law U5**, confined to `LocalNotificationScheduler._digestBody`.

### 3.4 §7 — `lowStock` is excluded from reminders

`NotificationKind.lowStock` exists in the enum and is deliberately absent from `reminderKinds`. It is a
*state*, not a date: everything a digest mentions falls on a day, and "you are low on rice" would fire every
morning until somebody shopped.

---

## 4. New architecture: seven domain ports

The most significant structural change across both phases, and the reason it happened is worth keeping.

**`PinService`, `BackupService` and `RestoreService` are `final class`.** In Dart 3 that means they can be
neither extended nor implemented outside their own library — **a test fake is impossible, not merely
awkward**. Add platform channels for `flutter_secure_storage`, `local_auth`, `flutter_local_notifications`,
`timezone`, `workmanager`, `google_mobile_ads` and `in_app_purchase`, and ARCH_5 §9.1's four-states-per-screen
gate was unreachable by any route.

So every plugin-bound or `final`-class service now sits behind a contract in `domain/services/`:

| Port | Implementation | Wraps |
|---|---|---|
| `lock/app_lock.dart` | `PinService` (`implements AppLock`) | `flutter_secure_storage` |
| `lock/biometric_gate.dart` | `LocalAuthBiometricGate` | `local_auth` |
| `backup/data_transfer_port.dart` | `ShareBackupTransfer` | `BackupService`, `RestoreService`, `EraseService`, `SafChannel`, `share_plus` |
| `attachments/attachment_port.dart` | `AttachmentStore` | `SafChannel`, `path_provider`, drift |
| `reminders/reminder_port.dart` | `LocalNotificationScheduler` | `flutter_local_notifications`, `timezone` |
| `trash/trash_port.dart` | `TrashAdapter` | drift |
| `support/support_port.dart` | `AdsAndBilling` | `google_mobile_ads`, `in_app_purchase` |

**Every provider in `service_providers.dart` is typed as the contract**, never the implementation. That is
what keeps `features/ → domain/ → core/` intact (Law L12) — verified across 84 files: no `features/` file
imports `data/`, and no `domain/` file imports `data/`, `flutter/` or `drift/`.

### 4.1 The rule Phase 9 must follow

**A new plugin gets a port before it gets a caller.** If a screen needs to name a type from `data/`, that is
the signal — put the type in `domain/` and the implementation behind a contract. Two of 8B's ports exist
solely so a plugin never enters the test binary.

### 4.2 `UnlockOutcome`, `UnlockRefusal`, `BackupArtefact`, `RestoreMode` moved to `domain/`

They were in `data/`. `BackupArtefact` is a record typedef, so the move was free — the `domain/` and `data/`
names refer to the same structural type and no adapter is needed.

---

## 5. New capabilities, and where they live

### 5.1 The only hard delete in the codebase

`TrashAdapter._hardDelete` (ARCH_3 §4.2). All three purge paths — one row, everything, only the expired —
arrive there; `_deleteRow` beneath it is a `switch` over seven tables with no logic and no other caller.
Runs under `PRAGMA defer_foreign_keys`, because **`foreign_keys = OFF` is silently ignored inside a
transaction** — the same trap `EraseService` documents.

**Phase 9: do not write a second `DELETE FROM` anywhere.** A row that can vanish without appearing in the
trash breaks the retention promise.

### 5.2 `EraseService` — clears data *and* the lock

Wiping a locked-out user's history while leaving the lock in place leaves them exactly as locked out. It
re-seeds from `AlayaDatabase.seeder` rather than a passed-in one, so a re-seed cannot differ from the install
it restores.

### 5.3 `alayaDatabaseFile()` in `open_database.dart`

Replace-mode restore has to move the live database file and nothing exposed its path. **It opens nothing**,
so Law L10's single-open-path rule is intact. Use it rather than deriving the path a second time.

### 5.4 The daily job

`lib/data/reminders/daily_job.dart`, registered once from `bootstrap()`. It runs in its own isolate with no
access to the UI Riverpod container, so it rebuilds its dependencies and opens the database through
`openAlayaDatabase`.

`@pragma('vm:entry-point')` is load-bearing — without it, tree-shaking removes the entry point from a release
build and the job silently never runs. It returns `true` even on failure, because `false` asks Android to
retry with backoff and a structurally failing job would retry forever.

**Verified working:** `WM-WorkerWrapper: Worker result SUCCESS` on device.

---

## 6. Android files now under version control

Previously only `AndroidManifest.xml` and `data_extraction_rules.xml` were project-specific. Now:

| File | Why |
|---|---|
| `MainActivity.kt` | Registers `SafPlugin` in `configureFlutterEngine`. **Base class deliberately unchanged** (`FlutterActivity`) — `local_auth` would want `FlutterFragmentActivity`, and that is a separate decision this does not foreclose |
| `com/alaya/saf/SafPlugin.kt` | The SAF channel. Its own package, independent of `applicationId` |
| `AndroidManifest.xml` | AdMob `APPLICATION_ID` via `${admobAppId}` placeholder. `allowBackup="false"` and `dataExtractionRules` unchanged (ARCH_3 §2.4) |
| `app/build.gradle.kts` | Desugaring, per-build-type AdMob IDs, release signing from `key.properties` |
| `build.gradle.kts` | **No `allprojects { repositories }`** — see §2 |
| `settings.gradle.kts` | `PREFER_SETTINGS` plus the Flutter engine repo |
| `gradle.properties` | `android.newDsl=false` |
| `key.properties` | **Git-ignored.** Release signing. Absent ⇒ debug-signed release build, which Play rejects |

### 6.1 Ad identifiers are split by build type

A live AdMob ID in a debug build is how an account gets flagged for invalid traffic. Both are split
structurally rather than by discipline:

- **Dart:** `AdsAndBilling.rewardedAdUnitId => kReleaseMode ? live : test`
- **Manifest:** `${admobAppId}` from `manifestPlaceholders`, per build type — a manifest cannot read
  `kReleaseMode`

---

## 7. ARCH_5 §7 coverage — rows now closed

**8A:** `app_settings` · `accounts` · `payment_methods` · `payees` · `tags` · `units` · `currencies`
§7.2: `includeInNetWorth` · `openingBalance*` · `tags.parentTagId` · `tags.allowedIn*`

**8B:** `attachments` · `notification_schedule` · `backup_history`

**ARCH_4 §5.1 item 23** (theme choice persisted) closed in 8A. Both theme providers became persisted
`Notifier`s, which also retired the app's last `StateProvider`.

### 7.1 A stale comment to ignore

`service_providers.dart` (Phase 5) says *"`calendarAggregatorProvider` could not exist"*. **It exists** — 7A
added it, 7B carries it. The comment misleads in a file six phases carry.

---

## 8. The check that ARCH_5 §9 is missing

8B built five screens, routed all five, tested all five — and **four were unreachable**. Every COVERAGE row
was honestly earned and no user could get to the feature.

Two checks passed and neither asks the right question: *every screen the router names exists*, and *every
route constant is declared*. **Add this to §9.2:**

```
for each route R declared in routes.dart:
    assert some widget calls context.push(R) or context.go(R),
    or R appears as an `_Entry.route` in the settings tree
```

It found all four in one pass. **Phase 9 should run it before claiming a coverage row.**

---

## 9. Open items for Phase 9

| Item | State |
|---|---|
| **Camera capture for attachments** | Needs an `image_picker` row in §7. Product decision |
| **`share_plus` never exercised** | Confined to `share_backup_transfer.dart`. The share path has not run on device |
| **`workmanager` KGP migration** | Upstream. Only caller of `purgeExpired`/`rescheduleAll` |
| **Real ad unit + privacy policy URL** | `docs/SUPPORT_SETUP.md`. URL needed **before** first upload |
| **Play publishing** | `docs/PUBLISHING_FROM_SCRATCH.md`. Independent of Phase 9 |
| **`TagRepository.watchTransactionIdsFor`** | Recorded in 7B, still unbuilt. Tag→ledger drill-down needs it |
| **`custom` DateRangePreset** | No picker shipped (7B) |
| **Unsorted imports** in `repository_providers.dart`, `service_providers.dart`, `app_router.dart` | Pre-existing since 7A |

---

## 10. What 8A and 8B taught, in one page

Recorded because each cost a build cycle and each will recur.

**A `final class` cannot be faked.** Check that before designing a test strategy around one.

**An awaited plugin call is not a completed one.** `RewardedAd.load` and `requestConsentInfoUpdate` both
dispatch and call back. Awaiting them proves nothing, and the compiler cannot tell you.

**Read the SDK's own flow, not its type signatures.** Three defects in `ads_and_billing.dart` across three
attempts, all from inferring the flow from types. The consent gate is `canRequestAds()`, not the status enum —
documented, and not discoverable from the API shape.

**Check a package against §7.4 before `pub add`.** `file_picker` was written down as a hazard and added
anyway.

**Assert on code, not on prose.** Four self-satisfying assertions this session — a check for
`'isZipped' not in file` while the replacement comment contained the word. Strip comments before asserting.

**A `Stream.value` fake cannot exercise a loading state.** It resolves in the first frame's microtask drain.
Use a stream that never emits.

**A lazy list hides everything below the fold.** `findsNothing` against one passes for the wrong reason.
Content assertions get a tall viewport; the 320×640 gate stays narrow.

**Extract ARB keys from call sites, never from memory.** It guarantees both directions — nothing referenced
that does not exist, nothing added that nothing uses.

**Reaching a feature is not the same as building it.** See §8.
