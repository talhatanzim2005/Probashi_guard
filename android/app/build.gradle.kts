import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Firebase config loader, applied only when the config it reads is
// actually here. Applied unconditionally it fails the build outright with
// "File google-services.json is missing", which would break every checkout
// that has not been given the file — including CI and anyone who is not
// working on phone verification.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "[probashi] google-services.json not found in android/app — " +
            "Firebase is inactive and phone verification will report itself " +
            "as not configured."
    )
}

// Signing details for release builds. Kept out of the repo (and out of git)
// because they are the keys to publishing this app — see android/key.properties.
// Absent on a machine that only builds debug, which must still work.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.probashiguard.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Registered in the Firebase console; Phone Auth is bound to this exact
        // id plus the signing fingerprints, so renaming it means re-registering.
        applicationId = "com.probashiguard.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only declared when key.properties is present, so a checkout without
        // the keystore still builds debug rather than failing to configure.
        if (keystoreProperties.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key when the release keystore is not on
            // this machine. An APK signed that way is for local testing only —
            // Play rejects it, and its fingerprint is not the one registered
            // with Firebase, so Phone Auth would drop to the reCAPTCHA path.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
