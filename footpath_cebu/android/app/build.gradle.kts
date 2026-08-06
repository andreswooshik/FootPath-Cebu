plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.footpath_cebu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.footpath_cebu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseStoreFile = System.getenv("ANDROID_RELEASE_STORE_FILE")
    val releaseStorePassword = System.getenv("ANDROID_RELEASE_STORE_PASSWORD")
    val releaseKeyAlias = System.getenv("ANDROID_RELEASE_KEY_ALIAS")
    val releaseKeyPassword = System.getenv("ANDROID_RELEASE_KEY_PASSWORD")

    signingConfigs {
        create("release") {
            if (releaseStoreFile.isNullOrBlank() ||
                releaseStorePassword.isNullOrBlank() ||
                releaseKeyAlias.isNullOrBlank() ||
                releaseKeyPassword.isNullOrBlank()
            ) {
                throw GradleException(
                    "Release signing variables are required; never ship a debug-signed APK."
                )
            }
            storeFile = file(releaseStoreFile)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
