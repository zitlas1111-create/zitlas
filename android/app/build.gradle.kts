plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Reads android/app/google-services.json and generates the native
    // Firebase config Firebase.initializeApp() picks up at runtime — see
    // docs/MIGRATION_INVENTORY.md §4.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.zitlas.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time on API levels that
        // predate it; required by its AAR metadata.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.zitlas.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // androidx.health.connect:connect-client requires API 26+. Flutter's
        // default (24) can't compile it. API 26 = Android 8.0 (2017), so this
        // is a safe floor; the hardware step-counter fallback below would work
        // on 24 too, but Health Connect is the preferred source of truth.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Health Connect — the step source of truth when the device has it. Used
    // ONLY for its aggregate API (StepsRecord COUNT_TOTAL), which is what
    // deduplicates overlapping records from multiple providers on the
    // platform's own terms rather than us summing raw records ourselves.
    implementation("androidx.health.connect:connect-client:1.1.0-rc02")
    // runBlocking/coroutine bridge for the suspend-only Health Connect API.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
