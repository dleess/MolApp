plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.donghan.molapp"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Same id as the Kotlin app this replaces, so the Play listing carries over.
        applicationId = "com.donghan.molapp"
        // Matches the native app: Mol* wants a reasonably modern System WebView, and 26 is what
        // the shipped versionCode 3 already required.
        minSdk = 26
        // Play rejects targetSdk < 35.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Upload-key signing. Credentials live in ~/.gradle/gradle.properties, never in git — the same
    // keystore the Kotlin app used, since the applicationId is unchanged.
    signingConfigs {
        create("release") {
            if (project.hasProperty("MOLAPP_STORE_FILE")) {
                storeFile = file(project.property("MOLAPP_STORE_FILE") as String)
                storePassword = project.property("MOLAPP_STORE_PASSWORD") as String
                keyAlias = project.property("MOLAPP_KEY_ALIAS") as String
                keyPassword = project.property("MOLAPP_KEY_PASSWORD") as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (project.hasProperty("MOLAPP_STORE_FILE")) {
                signingConfigs.getByName("release")
            } else {
                // Debug keys keep `flutter run --release` working on a machine without the keystore.
                signingConfigs.getByName("debug")
            }
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
