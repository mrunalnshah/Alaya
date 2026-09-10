# Changing Alaya's name, icon and branding on Android

Everything visible to a user, in the order it is worth doing. Written for this project specifically — the
file paths, the current values and the two things already wrong are all real.

---

## Part 0 — What cannot be changed

**`applicationId = "com.wildewulf.alaya"` is permanent.** It is the app's identity to Play and to every device
that has installed it. Changing it produces a *different app*: a new listing, zero installs, no update path for
anyone who already has Alaya, and the old ID can never be reused.

Everything else on this page is changeable at any time, including after release.

Note that `applicationId` and the Kotlin `namespace` are separate settings that happen to match here. The
`namespace` is a compile-time package for generated classes and can be changed safely; the `applicationId`
cannot.

---

## Part 1 — The three names, which are not the same thing

Alaya has **three** independent names, and people usually change one and wonder why the others did not follow.

| Where | Set in | Shows up |
|---|---|---|
| Launcher label | `android/app/src/main/AndroidManifest.xml` → `android:label` | Under the icon on the home screen, in the app switcher, in Settings › Apps |
| In-app name | `lib/app/l10n/app_en.arb` → `appName` | The app bar title, wherever the app names itself |
| Store name | Play Console → Main store listing → App name | Search results, the store page |

### Changing the launcher label

```xml
<application
    android:label="Alaya"
    ...
```

Keep it short. Android truncates around 12 characters under the icon, and a truncated name looks like a bug
rather than a choice.

**For a translated launcher label**, move it to a string resource instead:

```xml
android:label="@string/app_name"
```

with `android/app/src/main/res/values/strings.xml` holding the default and `values-gu/strings.xml`,
`values-hi/strings.xml` and so on holding translations. This is Android resources, not the ARB — the launcher
reads the label before any Dart code runs, so `app_en.arb` cannot reach it.

### Changing the in-app name

`appName` in `lib/app/l10n/app_en.arb`, then `flutter gen-l10n`. It is already an ARB key rather than a literal,
which is why `AlayaApp` uses `onGenerateTitle` instead of `title`.

---

## Part 2 — Launcher icons

Android has **three** icon systems layered on top of each other, and a modern app ships all three.

| System | Since | What it is |
|---|---|---|
| Legacy | forever | One square PNG per density. Used on Android 7.1 and below, and as a fallback |
| **Adaptive** | Android 8.0 (API 26) | Two layers — foreground and background — that the launcher masks into a circle, squircle, rounded square or teardrop depending on the device |
| **Themed (monochrome)** | Android 13 (API 33) | A single-colour silhouette the system tints to match the user's wallpaper |

Skipping adaptive icons is the commonest mistake: the launcher then puts your square PNG inside a white circle
with a visible border, which looks broken next to every other app on the phone.

### The geometry that matters

An adaptive icon is **108 × 108 dp**, but the launcher can crop hard:

- **Outer 108 dp** — full canvas, only the background layer reliably fills it
- **Inner 72 dp** — what most masks show
- **Safe zone: a 66 dp circle in the centre** — the only region guaranteed visible on every device

**Put nothing meaningful outside the 66 dp circle.** A logo drawn to the edges will have its edges eaten on a
circular-mask launcher, and the parallax effect some launchers apply shifts the layers as the user scrolls.

### The sizes, if you generate by hand

**Legacy** — `android/app/src/main/res/mipmap-*/ic_launcher.png`:

| Density | Pixels |
|---|---|
| mdpi | 48 × 48 |
| hdpi | 72 × 72 |
| xhdpi | 96 × 96 |
| xxhdpi | 144 × 144 |
| xxxhdpi | 192 × 192 |

**Adaptive layers** — `mipmap-*/ic_launcher_foreground.png` and `ic_launcher_background.png`:

| Density | Pixels |
|---|---|
| mdpi | 108 × 108 |
| hdpi | 162 × 162 |
| xhdpi | 216 × 216 |
| xxhdpi | 324 × 324 |
| xxxhdpi | 432 × 432 |

Plus `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
```

A flat background colour is better than a background image: it is one line, it scales to every density for free,
and adaptive icons look better with a plain field behind the mark anyway. Put the colour in
`android/app/src/main/res/values/colors.xml`:

```xml
<resources>
    <color name="ic_launcher_background">#0E1116</color>
</resources>
```

### Generating them instead — the easier path

```
flutter pub add dev:flutter_launcher_icons
```

**This is a dev dependency and a build-time asset generator — nothing in `lib/` imports it.** ARCH_1 §7.4's rule
about the package table governs packages the app's code depends on; a tool that writes PNGs and then plays no
part in the build is a different category, like `build_runner`. Worth noting in §7 all the same, so the next
person knows why it is in `pubspec.yaml`.

Configuration, in `pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/branding/icon_1024.png"
  adaptive_icon_background: "#0E1116"
  adaptive_icon_foreground: "assets/branding/icon_foreground_1024.png"
  adaptive_icon_monochrome: "assets/branding/icon_monochrome_1024.png"
  min_sdk_android: 21
```

Then:

```
dart run flutter_launcher_icons
```

**Supply three source images at 1024 × 1024**, not one:

| File | What it holds |
|---|---|
| `icon_1024.png` | The complete icon, edge to edge — used for legacy and for the Play listing |
| `icon_foreground_1024.png` | The mark **only**, on transparency, sized so it sits inside the middle 66% |
| `icon_monochrome_1024.png` | The same mark as a **solid white silhouette** on transparency |

Letting the tool derive the foreground from the full icon is what produces those adaptive icons where the logo
is comically large and clipped — the tool cannot know which part of your artwork is the mark.

---

## Part 3 — The notification icon, which is the one everybody gets wrong

**Android tints notification icons to a flat white silhouette on API 21 and above.** Any colour, gradient or
detail in the image is discarded — only the alpha channel survives.

Pointing the notification at `@mipmap/ic_launcher`, which is the Flutter default and what most guides suggest,
therefore produces **a solid white square** in the status bar. It is not a subtle problem; it looks like a
rendering fault.

### Make a proper one

`android/app/src/main/res/drawable-*/ic_notification.png` — **white shape on transparency, nothing else:**

| Density | Pixels |
|---|---|
| mdpi | 24 × 24 |
| hdpi | 36 × 36 |
| xhdpi | 48 × 48 |
| xxhdpi | 72 × 72 |
| xxxhdpi | 96 × 96 |

Simplify hard. At 24 dp a detailed mark becomes a smudge; most apps use a single glyph from their logo rather
than the whole thing.

### The bug this guide found

**`FlutterLocalNotificationsPlugin.initialize()` is never called in this project.** I checked while writing this,
because initialisation is where the notification icon is declared — and it is not there.

`LocalNotificationScheduler` calls `zonedSchedule` and `cancel` but never `initialize`, so on a real device the
daily digest has never been able to fire. It is not an icon problem; it is a "notifications do not work" problem,
and Phase 8B's tests could not catch it because the plugin is behind `ReminderPort` and every test uses the fake.

The fix belongs in `LocalNotificationScheduler`, alongside `_ensureTimezones`:

```dart
bool _pluginReady = false;

Future<void> _ensurePlugin() async {
  if (_pluginReady) return;
  await _plugin.initialize(
    const InitializationSettings(
      // Not `@mipmap/ic_launcher`: Android flattens a notification icon to a white silhouette, so the
      // launcher icon renders as a solid white square. This is a purpose-made 24dp white-on-transparent
      // drawable.
      android: AndroidInitializationSettings('@drawable/ic_notification'),
    ),
  );
  _pluginReady = true;
}
```

then `await _ensurePlugin();` at the top of `_scheduleDigest` and `cancelAll`.

Ask me to apply it properly and I will — it needs the same care as the rest of that file, and the plugin's
`initialize` signature is another R22 surface I would want to check rather than assume.

---

## Part 4 — The launch screen

The white flash before the first Flutter frame is a **theme**, not an image, and Alaya already defines two:

- `android/app/src/main/res/values/styles.xml` → `LaunchTheme`, shown by the system before Flutter starts
- `NormalTheme`, applied once the engine is up

To brand it, edit the `LaunchTheme` background drawable:

```xml
<!-- android/app/src/main/res/drawable/launch_background.xml -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/ic_launcher_background" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/ic_launcher_foreground" />
    </item>
</layer-list>
```

Add a `values-night/` copy so a dark-mode user does not get a white flash. **Keep it to a colour and a centred
mark** — the launch screen is shown for a few hundred milliseconds and anything more elaborate is work nobody
sees.

---

## Part 5 — Play Store graphics

None of these live in the repo; they are uploaded in Play Console.

| Asset | Size | Notes |
|---|---|---|
| App icon | 512 × 512 PNG, 32-bit with alpha | **Not** the adaptive icon — a complete square mark. Play applies its own rounding |
| Feature graphic | 1024 × 500 PNG or JPG | Shown at the top of the listing. No transparency. Avoid text near the edges; it is cropped on some layouts |
| Phone screenshots | min 2, max 8; 16:9 or 9:16; 320–3840 px | Take these from a real device, not an emulator |
| Short description | 80 characters | The line under the title in search |
| Full description | 4000 characters | |

**A note specific to Alaya:** the store description is where its main selling point lives, and it is unusual
enough to lead with — the app works entirely offline, keeps financial data on the device, and has no account to
sign up for. That is a genuine differentiator in a category where almost every competitor requires a login, and
it is also exactly what the Data safety section will confirm rather than contradict.

---

## Part 6 — Verifying it worked

Icons cache aggressively. After changing them:

```
flutter clean
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

If the old icon persists, the **launcher** is caching it — reboot the device, or long-press the icon and remove
then reinstall. This is not a build problem and rebuilding again will not help.

To confirm what actually shipped:

```
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep -E 'mipmap|ic_notification'
```

You should see `ic_launcher`, `ic_launcher_foreground` and `ic_launcher_monochrome` across five densities, the
`mipmap-anydpi-v26` XML, and `ic_notification` in `drawable-*`.

---

## Checklist

- [ ] `android:label` in the manifest, ≤ 12 characters
- [ ] `appName` in `app_en.arb`, then `flutter gen-l10n`
- [ ] Three 1024 × 1024 sources: full, foreground, monochrome
- [ ] `dart run flutter_launcher_icons`
- [ ] `mipmap-anydpi-v26/ic_launcher.xml` has all three layers including `<monochrome>`
- [ ] Mark sits inside the centre 66% of the foreground
- [ ] `ic_notification` — white on transparency, five densities
- [ ] **`initialize()` wired in `LocalNotificationScheduler`** — see Part 3
- [ ] `launch_background.xml` branded, with a `values-night/` variant
- [ ] Play: 512 × 512 icon, 1024 × 500 feature graphic, ≥ 2 screenshots
- [ ] Verified on a device after `flutter clean`
- [ ] Checked the icon on a circular-mask launcher *and* a squircle one — they crop differently
