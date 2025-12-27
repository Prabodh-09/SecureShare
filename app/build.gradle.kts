// android/app/build.gradle.kts

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_application_1" // change if you renamed package
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.example.flutter_application_1"
        // Use 21 so it works on older devices too
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        multiDexEnabled = true
    }

buildTypes {
        release {
            isMinifyEnabled = false    // no code shrinking
            // turn OFF resource shrinking
            isShrinkResources = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        // Warning about deprecation is fine for now in a student project
        jvmTarget = JavaVersion.VERSION_17.toString()
    }
}

// This connects the Flutter module to the Android app
flutter {
    source = "../.."
}
