plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.File

// Upload key for Google Play (kept in ~/.config/chordpro, never in the project;
// CHORDPRO_KEYSTORE / CHORDPRO_KEYSTORE_PASS override). Back it up: Play needs it for every update.
val ks = File(System.getenv("CHORDPRO_KEYSTORE") ?: "${System.getProperty("user.home")}/.config/chordpro/upload.jks")
val ksPass = System.getenv("CHORDPRO_KEYSTORE_PASS") ?: File(ks.path.removeSuffix(".jks") + ".pass").takeIf { it.exists() }?.readText()?.trim()

android {
    // fvp (video on the desktop apps) isn't used on Android: leave out its
    // video engine (~32 MB). Its plugin copes with the libraries missing.
    packaging {
        jniLibs {
            excludes += listOf("**/libmdk.so", "**/libffmpeg.so", "**/libfvp.so")
        }
    }
    namespace = "com.bilingualprojector.bilingual_projector"
    // 37: required by the permission_handler plugin (via the Cast / media plugins).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Google Play's package name (permanent there). The Kotlin code keeps its old package
        // (namespace above); AppIcon.kt builds alias names from the code's package, not this id.
        applicationId = "app.chordpropresenter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (ks.exists() && ksPass != null) {
            create("upload") {
                storeFile = ks
                storePassword = ksPass
                keyAlias = "upload"
                keyPassword = ksPass
            }
        }
    }

    buildTypes {
        release {
            // Google Play upload key; falls back to the debug key where the key isn't present.
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
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
