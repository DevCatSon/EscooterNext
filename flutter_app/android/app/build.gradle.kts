plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.devcat.escooter_control"
    // BLE and permission plugins require API 37; runtime targeting remains pinned by Flutter.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Keep the application ID stable so installed Flutter builds can update.
        applicationId = "com.devcat.escootercontrol.next"
        // Runtime compatibility follows the pinned Flutter SDK; see docs/BUILDING.md.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Flutter adds an ABI offset to this pubspec build number for split APKs.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Production signing is intentionally left to the owner. Local testing uses debug APKs.
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
