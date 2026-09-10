# B8_ANDROID

MainActivity, the SAF platform channel, and the manifest.

**21 files · 716 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `android/android/app/src/main/res/xml/data_extraction_rules.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- API 31+ backup controls. Excludes everything from both cloud backup and device-to-device
     transfer, because the app's database is plaintext (ARCH_1 §2.1) and must never leave the
     device except through the user's own explicit export (ARCH_3 §3). See anomaly A42. -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" path="." />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" path="." />
    </device-transfer>
</data-extraction-rules>
```

### `android/app/build.gradle.kts`

```kotlin
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from a file that is never committed. `android/key.properties` holds the keystore path
// and passwords; `.gitignore` excludes it and every `*.jks`. When absent, the release build falls back to debug
// keys so a fresh clone still builds — verify before uploading with:
//
//     keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
//
// The owner must be the name given to `keytool`, not "Android Debug".
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val hasUploadKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.wildewulf.alaya"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by `flutter_local_notifications`, which uses `java.time` APIs absent below API 26.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.wildewulf.alaya"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Google's public test App ID, in debug builds only. A debug build serving live adverts is how an
            // AdMob account gets flagged for invalid traffic, and splitting the value per build type means the
            // live ID cannot reach a debug build by accident.
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
        }
        release {
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3214315776823567~4403362558"

            // **Phase 9: R8 on, resources shrunk.** Both default to off for the release type in a Flutter
            // template, which is why an unconfigured release AAB is larger than it needs to be. `shrinkResources`
            // requires `minifyEnabled`, so the two travel together.
            //
            // Dart code is *not* affected by either: `--obfuscate` handles that, and it is a build-command flag
            // rather than a Gradle setting — see the release commands in PHASE_09_POLISH.md.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // The desugaring runtime. A Gradle coordinate, so it needs an explicit version — ARCH_1 §7.4 governs `pub`,
    // which has `flutter pub add`; Gradle has no equivalent.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // `play-services-ads` is deliberately NOT declared: `google_mobile_ads` brings the version it is tested
    // against, and a second hand-pinned one produces a runtime `NoSuchMethodError` rather than a build error.
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
```

### `android/app/proguard-rules.pro`

```text
# Alaya — R8 keep rules.
#
# Phase 9 turned on `isMinifyEnabled` and `isShrinkResources`. Flutter, drift and the Play Billing library all
# ship their own consumer rules, so this file is deliberately short: a long keep list is usually a sign that
# somebody silenced a warning rather than understanding it, and every unnecessary `-keep` gives back the size
# that shrinking was turned on to save.

# ── Play Core, referenced by Flutter's deferred-components support ─────────────────────────────
#
# Flutter's engine references `com.google.android.play.core.*` whether or not the app uses deferred components.
# Alaya does not, so the classes are absent and R8 warns about the dangling references. Warning suppressed rather
# than the classes kept: keeping absent classes is impossible, and the reference is never reached at runtime.
-dontwarn com.google.android.play.core.**

# ── Reflection-free by design ─────────────────────────────────────────────────────────────────
#
# No `-keep` for the app's own classes. Nothing in Alaya is looked up by name at runtime: there is no JSON
# reflection, no service loader and no dynamic instantiation. drift generates concrete Dart, and the platform
# channel resolves by string on the *Kotlin* side, which R8 does not touch.
#
# If a future release crashes with a `ClassNotFoundException`, the cause is a new dependency doing reflection —
# add its rule here with a comment naming the dependency, rather than a blanket keep.
```

### `android/app/src/debug/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- The INTERNET permission is required for development. Specifically,
         the Flutter tool needs it to communicate with the running application
         to allow setting breakpoints, to provide hot reload, etc.
    -->
    <uses-permission android:name="android.permission.INTERNET"/>
</manifest>
```

### `android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- android:allowBackup="false" is MANDATORY (ARCH_3 §2.4, anomaly A42).
         The database is plaintext. Android's auto-backup defaults to ON, which would silently upload the
         complete financial database to the user's Google Drive — outside the app's control and outside
         anything the Play data-safety form declares. This also blocks `adb backup` extraction.
         Do not remove either attribute.

         allowBackup="false" disables backup on API 30 and below; dataExtractionRules covers API 31+, where
         cloud-backup and device-transfer are controlled separately.

         PHASE 9 GATE: verify this in the BUILT artefact, not here. A manifest merger, or any library
         shipping allowBackup="true", can flip it silently, so the source is not evidence.
         The command is in PHASE_09_POLISH.md, not here: an XML comment may not contain a double hyphen,
         and every aapt2 invocation needs one. -->

    <!-- Phase 9. Declared explicitly rather than left to the manifest merger.
         `google_mobile_ads` adds AD_ID on its own, which means the permission appears in the built artefact
         while appearing nowhere in this project — and a permission nobody can find in source is one nobody
         remembers to declare on the Play data-safety form. Alaya *does* need it: the Support screen requests
         adverts, and Play requires the declaration for any app that reads the advertising ID.

         Removing it would mean non-personalised ads only. That is a revenue decision, not a technical one; if
         it is ever taken, replace this with tools:node="remove" and update the data-safety form. -->
    <uses-permission android:name="com.google.android.gms.permission.AD_ID" />

    <!-- Phase 9. Declared explicitly for the same reason as AD_ID above: `flutter_local_notifications` adds it
         through the manifest merger, which means it exists in the built artefact and nowhere in this project,
         and a permission nobody can find in source is one nobody reasons about.

         Required from Android 13 (API 33). Without it `requestNotificationsPermission()` returns false without
         ever showing a dialog, which looks exactly like a user declining. ARCH_3 §7 requests it on the first
         reminder switch-on and never on launch.

         SCHEDULE_EXACT_ALARM is deliberately NOT declared: the digest uses
         AndroidScheduleMode.inexactAllowWhileIdle, Android 14 restricts the exact permission, and Play asks
         apps to justify it. A digest arriving at 9:07 instead of 9:00 has lost nothing. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <!-- Phase 9. Declared explicitly for the same reason as AD_ID and POST_NOTIFICATIONS above:
         flutter_local_notifications does NOT contribute this through the merger — verified against the
         built artefact, where both this and the receiver were absent while the plugin was present.
         Android clears every AlarmManager alarm on reboot AND on app update, so without the receiver
         below the daily digest stops until somebody next opens the app. An update is far more frequent
         than a reboot. -->
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

    <application
        android:label="Alaya"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:dataExtractionRules="@xml/data_extraction_rules">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme"
                />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <!-- The Mobile Ads SDK reads this at initialisation and throws if absent, so without it the Support
             screen would crash the first time somebody opened it. The value comes from `manifestPlaceholders`,
             set per build type in app/build.gradle.kts: Google's test App ID for debug, the real one for
             release. -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="${admobAppId}"/>

        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />

        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>

    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

### `android/app/src/main/kotlin/com/alaya/saf/SafPlugin.kt`

```kotlin
package com.alaya.saf

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * A minimal Storage Access Framework bridge: open a document, create a document, write to one.
 *
 * Written because `file_picker` cannot be used in this project. ARCH_1 §7.4 records why: the resolvable
 * version here is 3.0.4 from 2020, whose `android/build.gradle` calls `jcenter()` — shut down in 2021 —
 * so `pub get` succeeds and `assembleDebug` fails. ARCH_1 §7 anticipated this and said to "evaluate
 * whether a small SAF platform channel is preferable to the whole plugin". It is: this file replaces a
 * dependency that also dragged in `dbus`, `ffi`, `win32`, `web` and `flutter_web_plugins` — desktop and
 * web surface an Android-only app never uses.
 *
 * **No permissions are declared or needed.** That is the point of SAF: the user chooses the document in
 * the system's own picker, and the grant is scoped to what they chose. There is no
 * `WRITE_EXTERNAL_STORAGE` and no `MANAGE_EXTERNAL_STORAGE` anywhere in this app (ARCH_3 §3.3).
 *
 * Registered from `MainActivity.configureFlutterEngine`, using the v2 embedding's `ActivityAware`
 * contract, so the host activity's base class is untouched.
 */
class SafPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var pending: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        val host = activity
        if (host == null) {
            result.error("no_activity", "The picker needs a foreground activity.", null)
            return
        }
        when (call.method) {
            // Opens a document and copies it into the app's cache, returning that path.
            //
            // **A copy, not the URI.** `RestoreService` runs `ATTACH DATABASE` on a filesystem path, and
            // SQLite cannot open a `content://` URI. The grant is also scoped to this activity result, so a
            // URI held past it would be unreadable exactly when the restore needed it.
            "openDocument" -> {
                if (!claim(result)) return
                @Suppress("UNCHECKED_CAST")
                val types = (call.argument<List<String>>("mimeTypes") ?: listOf("*/*")).toTypedArray()
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (types.size == 1) types[0] else "*/*"
                    if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types)
                }
                host.startActivityForResult(intent, REQUEST_OPEN)
            }

            // Raises the create-document sheet and writes an existing file into whatever the user chose.
            //
            // One round trip rather than two: the source path is held until the result arrives, so Dart
            // never has to hold a URI it cannot use.
            "createDocument" -> {
                if (!claim(result)) return
                pendingSourcePath = call.argument<String>("sourcePath")
                if (pendingSourcePath == null) {
                    finish(null, "no_source", "No file was given to save.")
                    return
                }
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mimeType") ?: "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("fileName") ?: "alaya.db")
                }
                host.startActivityForResult(intent, REQUEST_CREATE)
            }

            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_OPEN && requestCode != REQUEST_CREATE) return false
        val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        // Dismissing the sheet returns null rather than an error: cancelling is the commonest outcome of a
        // file chooser, and reporting it as a failure would put a red message under a deliberate action.
        if (uri == null) {
            finish(null, null, null)
            return true
        }
        return when (requestCode) {
            REQUEST_OPEN -> { copyIn(uri); true }
            else -> { copyOut(uri); true }
        }
    }

    private fun copyIn(uri: Uri) {
        val host = activity ?: return finish(null, "no_activity", "The activity went away.")
        try {
            val name = "saf_${System.currentTimeMillis()}"
            val target = File(host.cacheDir, name)
            host.contentResolver.openInputStream(uri).use { input ->
                if (input == null) return finish(null, "unreadable", "That file could not be read.")
                target.outputStream().use { output -> input.copyTo(output) }
            }
            finish(target.absolutePath, null, null)
        } catch (error: Exception) {
            finish(null, "copy_failed", error.message)
        }
    }

    private fun copyOut(uri: Uri) {
        val host = activity ?: return finish(null, "no_activity", "The activity went away.")
        val source = pendingSourcePath
        if (source == null) return finish(null, "no_source", "No file was given to save.")
        try {
            host.contentResolver.openOutputStream(uri).use { output ->
                if (output == null) return finish(null, "unwritable", "That location could not be written to.")
                File(source).inputStream().use { input -> input.copyTo(output) }
            }
            finish(uri.toString(), null, null)
        } catch (error: Exception) {
            finish(null, "write_failed", error.message)
        }
    }

    /** Takes the pending slot, refusing a second concurrent picker. */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("busy", "A file chooser is already open.", null)
            return false
        }
        pending = result
        return true
    }

    private fun finish(value: String?, code: String?, message: String?) {
        val result = pending
        pending = null
        pendingSourcePath = null
        if (result == null) return
        if (code != null) result.error(code, message, null) else result.success(value)
    }

    companion object {
        /** The channel name, matched by `saf_channel.dart`. */
        const val CHANNEL = "com.alaya/saf"
        private const val REQUEST_OPEN = 0x5AF0
        private const val REQUEST_CREATE = 0x5AF1
    }
}
```

### `android/app/src/main/kotlin/com/wildewulf/alaya/MainActivity.kt`

```kotlin
package com.wildewulf.alaya

import com.alaya.saf.SafPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The host activity.
 *
 * **The base class is deliberately unchanged.** `SafPlugin` registers through the v2 embedding's
 * `ActivityAware` contract, so it works against whatever `MainActivity` already extends — which matters
 * because `local_auth` would eventually want `FlutterFragmentActivity`, and that is a separate decision
 * with its own dependency consequences. Nothing here forecloses it.
 *
 * The only addition is `configureFlutterEngine`. If your file already overrides it, add the one
 * `add(SafPlugin())` line to what is there rather than replacing the method.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SafPlugin())
    }
}
```

### `android/app/src/main/res/drawable-night/launch_background.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
    The dark-mode window background. Without this file a dark-mode user gets a
    white flash before the first frame, which is the most visible rough edge a
    Flutter app has on launch.
-->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <color android:color="#FF0E1116"/>
    </item>

    <!-- <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/ic_launcher_foreground"/>
    </item> -->
</layer-list>
```

### `android/app/src/main/res/drawable-v21/launch_background.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Modify this file to customize your launch splash screen -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="?android:colorBackground" />

    <!-- You can insert your own image assets here -->
    <!-- <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/launch_image" />
    </item> -->
</layer-list>
```

### `android/app/src/main/res/drawable/ic_notification.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
    Alaya's status-bar icon.

    **Only the alpha channel survives.** Android flattens a notification small icon to a white silhouette on
    API 21 and above — colour, gradients and detail are all discarded. Pointing this at `@mipmap/ic_launcher`,
    the Flutter default, renders a solid white square for exactly that reason.

    **A silhouette needs empty space to be a silhouette.** The previous mark was a rounded rectangle filling
    18 of the 24dp canvas, with a circular hole punched by `evenOdd`. It rendered precisely as drawn — a white
    block with a dark dot — and read as a rendering fault rather than a glyph, because at ~18dp in a row
    beside wifi, battery and signal, a filled block has no outline to recognise. Every icon it sits next to
    is a distinctive shape with generous margins.

    So: a house, which is what *Alaya* means, drawn as an outline. The roof and walls are one stroke and the
    door is a second, both closed shapes rather than a fill, so most of the canvas stays transparent and the
    form survives at small sizes.

    **`android:strokeColor` rather than a hole punched with `evenOdd`.** A stroke produces alpha just as a
    fill does, and it is far easier to keep correct: an outline drawn as two nested subpaths depends on
    winding order, and getting it backwards yields a solid shape that looks deliberate.

    Two rules if you replace this with your own mark: **white only**, and **leave the canvas mostly empty**.
    Anything with fine detail becomes a smudge; anything that fills the frame becomes a box.

    Referenced from Dart as the bare name `ic_notification` — never `@drawable/ic_notification`, which is XML
    syntax and resolves to nothing through `getIdentifier`. And kept from the release shrinker by
    `res/raw/keep.xml`, because a resource named only by a runtime string looks unused to it.
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">

    <!-- Roof and walls. Apex at the top centre, eaves at 3 and 21, base at 20. -->
    <path
        android:strokeColor="#FFFFFFFF"
        android:strokeWidth="1.9"
        android:strokeLineJoin="round"
        android:strokeLineCap="round"
        android:fillColor="#00000000"
        android:pathData="M3,11 L12,3.5 L21,11 M5,10 V20 H19 V10" />

    <!-- The door: the negative space that makes it read as a house rather than a pentagon. -->
    <path
        android:strokeColor="#FFFFFFFF"
        android:strokeWidth="1.9"
        android:strokeLineJoin="round"
        android:fillColor="#00000000"
        android:pathData="M10,20 V14.5 H14 V20" />
</vector>
```

### `android/app/src/main/res/drawable/launch_background.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
    The window background shown before Flutter's first frame.

    This is a DRAWABLE and must live in res/drawable/. It is referenced from
    values/styles.xml as @drawable/launch_background. Putting a layer-list inside
    styles.xml is what produced "Unrecognized child element" at build time.

    The colour is written literally rather than as @color/... so this file cannot
    fail on a resource that does not exist yet. To add the logo, uncomment the
    bitmap item below and set src to whatever your icon generator produced.
-->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <color android:color="#FFFFFFFF"/>
    </item>

    <!-- <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/ic_launcher_foreground"/>
    </item> -->
</layer-list>
```

### `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`

```xml
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
```

### `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`

```xml
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
```

### `android/app/src/main/res/raw/keep.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
    android/app/src/main/res/raw/keep.xml

    Resources the shrinker cannot see a reference to, and must keep anyway.

    **`isShrinkResources = true` removes any resource nothing references**, and it decides that by reading
    compiled code and XML. It finds `R.drawable.foo` and it finds `@drawable/foo` inside another resource. It
    cannot find a resource named by a string at runtime — and that is exactly how
    `flutter_local_notifications` resolves a notification icon:

        context.getResources().getIdentifier("ic_notification", "drawable", packageName)

    The only place `ic_notification` appears in this project is a Dart constant. aapt2 does not read Dart,
    R8 does not read Dart, so nothing static points at the drawable and the shrinker strips it. The file is
    merged — it survives as far as `intermediates/packaged_res/release/` — and is then dropped before the
    APK is written.

    The failure is release-only and total: `initialize` throws `PlatformException(invalid_icon, ...)`, so
    every call that touches the plugin fails. Reminder switches will not stay on, the daily digest never
    fires, and a test notification never arrives. In debug, with shrinking off, all three work.

    **This file is the documented remedy**, not a workaround. `tools:keep` is the shrinker's own escape hatch
    for exactly this case: a resource reached dynamically.

    Anything else resolved by name later — a channel icon, a custom sound, a per-kind glyph — must be added
    to the list below at the same time, because nothing will fail until release and nothing will name the
    cause.
-->
<resources
    xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_notification" />
```

### `android/app/src/main/res/values-night/styles.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the
         OS's Dark Mode setting is on. -->
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>

    <!-- Theme applied to the Android Window as soon as the process has started. -->
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

### `android/app/src/main/res/values/ic_launcher_background.xml`

```xml
<resources>
  <color name="ic_launcher_background">#000000</color>
</resources>
```

### `android/app/src/main/res/values/styles.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Theme applied to the Android Window while the process is starting when the
         OS's Dark Mode setting is off. -->
    <style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>

    <!-- Theme applied to the Android Window as soon as the process has started.
         This theme determines the color of the Android Window while your Flutter UI
         initializes, as well as behind your Flutter UI while its running. -->
    <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">?android:colorBackground</item>
    </style>
</resources>
```

### `android/app/src/main/res/xml/data_extraction_rules.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- API 31+ backup controls. Excludes everything from both cloud backup and device-to-device
     transfer, because the app's database is plaintext (ARCH_1 §2.1) and must never leave the
     device except through the user's own explicit export (ARCH_3 §3). See anomaly A42. -->
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" path="." />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" path="." />
    </device-transfer>
</data-extraction-rules>
```

### `android/app/src/profile/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- The INTERNET permission is required for development. Specifically,
         the Flutter tool needs it to communicate with the running application
         to allow setting breakpoints, to provide hot reload, etc.
    -->
    <uses-permission android:name="android.permission.INTERNET"/>
</manifest>
```

### `android/build.gradle.kts`

```kotlin
// **No `allprojects { repositories { ... } }` block.**
//
// Gradle is configured to prefer repositories declared in `settings.gradle.kts`
// (`dependencyResolutionManagement`), and declaring them here as well is the error:
//
//     Build was configured to prefer settings repositories over project repositories
//     but repository 'Google' was added by build file 'build.gradle.kts'
//
// Modern Flutter templates declare `google()` and `mavenCentral()` once, in settings, precisely so
// that a subproject cannot introduce a different resolution order. Nothing needs adding here.

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
```

### `android/settings.gradle.kts`

```kotlin
pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    // PREFER_SETTINGS keeps these authoritative, but it also *discards* the repository
    // Flutter's Gradle plugin adds at project level — which is where the engine artifacts
    // (io.flutter:flutter_embedding_debug, io.flutter:arm64_v8a_debug) live. Declaring it
    // here is what makes them resolvable: settings-level repositories are the ones honoured.
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

rootProject.name = "Alaya"
include(":app")
```
