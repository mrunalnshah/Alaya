# Alaya — codebase state after 8A and 8B

Every file below is the **current** version, extracted from the phase documents after all build and runtime
fixes. Copy the tree over your project root; each path is its destination.

```
cp -r alaya_codebase_8A_8B/lib     <project>/
cp -r alaya_codebase_8A_8B/test    <project>/
cp -r alaya_codebase_8A_8B/android <project>/
cp -r alaya_codebase_8A_8B/docs    <project>/
```

`android/key.properties.template` is a template — copy it to `android/key.properties`, fill it in, and keep it
out of git. `MainActivity.kt` is under `com/wildewulf/alaya/`, matching your `applicationId`.

---

## Earlier phase documents now superseded

These files were first delivered by an earlier phase and have since changed. **Regenerate those documents from
the versions here**, or treat the versions here as authoritative.

| File | Originally from | Why it changed |
|---|---|---|
| `lib/data/db/connection/open_database.dart` | PHASE_01C_DB_RUNTIME | gained `alayaDatabaseFile()` — Replace-mode restore needs the live path and nothing exposed it. Opens nothing, so Law L10 holds |
| `lib/domain/repositories/settings_repository.dart` | PHASE_03A_DOMAIN | gained `writeHomeCurrencyCode`, so no feature has to duplicate a `data/` key |
| `lib/data/repositories/settings_repository_impl.dart` | PHASE_03B_REPO_MONEY | implements the above, routed through `writeValue` (one write path) |
| `lib/data/security/pin_service.dart` | PHASE_04C_ENGINE_REST | `implements AppLock`; `UnlockOutcome`/`UnlockRefusal` moved to `domain/`; gained `readPinLength` and `readFailedCount` |
| `lib/app/app.dart` | PHASE_05_SHELL | persisted theme providers (ARCH_4 item 23); **both router gates and `refreshListenable` wired**; `AutoLockObserver` mounted |
| `lib/app/bootstrap.dart` | PHASE_05_SHELL | awaits the lock and onboarding startup values before `runApp`; registers the daily job |
| `lib/app/l10n/app_en.arb` | PHASE_05_SHELL | 696 → 1,127 keys. §3.4's warning corrected to the spec verbatim |
| `lib/app/providers/service_providers.dart` | PHASE_05_SHELL | five ports typed as contracts; `pinServiceProvider` retyped `Provider<AppLock>` |
| `lib/app/router/app_router.dart` | PHASE_05_SHELL | onboarding gate, `refreshListenable`, the `/lock` **prefix** fix, 18 screens, `SupportAction` |
| `lib/app/router/routes.dart` | PHASE_05_SHELL | +26 routes, patterns, parameters and builders |
| `lib/features/settings/presentation/theme_lab_screen.dart` | PHASE_05_SHELL | calls `use()` rather than assigning `state`, which never persisted |
| `lib/shared/widgets/alaya_drawer.dart` | PHASE_05_SHELL | Support Us row, with `titleFor`/`iconFor` cases |
| `test/shared/layout_overflow_test.dart` | PHASE_05_SHELL | +13 cases for 8A and 8B surfaces |
| `test/support/fake_settings_repository.dart` | PHASE_06F_UI_DASHBOARD | implements the new contract member |

---

## Runtime defects fixed after delivery

All four were routing, and none was catchable by a widget test.

| Defect | Cause | Fix |
|---|---|---|
| The PIN was never asked for | `routerProvider` called `AppRouter.build()` **with no arguments**, so `isLocked` defaulted to `() => false`. `routerRefreshProvider` was never written; `AutoLockObserver` was never mounted | `app.dart` wires both gates, the bridge and the observer |
| A fresh install showed a lock screen it could not pass | `LockNotifier.build()` returned `unknown`, which counted as locked; `UnlockRefusal.notEnabled` was unhandled, so every digit said "not right" | Lock resolved in `bootstrap()` before the first frame; `notEnabled` now releases |
| Onboarding appeared when opening Settings | Same async race, plus a dropped notification: if `_restore()` resolved before `GoRouter` attached its listener, the redirect did not re-run until the next navigation | Onboarding resolved in `bootstrap()` too |
| Finish did nothing (though the write succeeded) | The flow changed a gate and waited for the redirect to carry the user. **A redirect is a guard, not a navigation mechanism** | `onboarding_flow` and `lock_screen` navigate explicitly |

## Build fixes

`file_picker` removed entirely — it resolves to 3.0.4 (2020) whose `jcenter()` call fails at `assembleDebug`
while `pub get`, the analyzer and `flutter test` all pass (ARCH_1 §7.4). Replaced by the SAF platform channel.

Also: `zonedSchedule` and `cancel` are named-only on the installed plugin; `local_auth` takes no
`AuthenticationOptions`; UMP needs `requestConsentInfoUpdate` before the status is meaningful, and the ad gate is
`canRequestAds()` rather than the status enum; desugaring is required; the AdMob App ID is a manifest
placeholder split per build type.

## Still open for Phase 9

| Item | Note |
|---|---|
| Camera capture | Needs an `image_picker` row in ARCH_1 §7. Product decision |
| `share_plus` untested | The share path has not run on device |
| `workmanager` KGP | Upstream. Only caller of `purgeExpired` and `rescheduleAll` |
| A router-level test | Build the router with `isLocked: () => true` and assert the resolved location. **Three routing bugs reached the user through green test runs** |
| Real ad unit + privacy policy | `docs/SUPPORT_SETUP.md` |
| Play publishing | `docs/PUBLISHING_FROM_SCRATCH.md` |

