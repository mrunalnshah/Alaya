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