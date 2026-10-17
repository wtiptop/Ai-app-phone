plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pl.scalajaca.scalajaca"
    compileSdk = flutter.compileSdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pl.scalajaca.scalajaca"
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
        // Debug zależności JNI zawierają kilka ABI. Ograniczamy cały APK do
        // jawnie wybranego celu, aby instalator nie wybrał niepełnego ABI.
        val selectedPlatforms = providers.gradleProperty("target-platform").orNull
            ?.split(",")?.mapNotNull {
                when (it) {
                    "android-arm64" -> "arm64-v8a"
                    "android-arm" -> "armeabi-v7a"
                    "android-x64" -> "x86_64"
                    else -> null
                }
            }
        if (!selectedPlatforms.isNullOrEmpty()) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(selectedPlatforms)
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            // Release wymaga osobnej konfiguracji klucza właściciela.
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
