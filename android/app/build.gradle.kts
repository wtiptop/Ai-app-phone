plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    ndkVersion = "28.2.13676358"
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
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        externalNativeBuild {
            cmake { arguments += listOf("-DANDROID_STL=c++_static", "-DCMAKE_BUILD_TYPE=Release") }
        }
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
    externalNativeBuild {
        cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" }
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

dependencies {
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}

tasks.withType<org.gradle.api.tasks.testing.Test>().configureEach {
    providers.environmentVariable("SCALAJACA_TEST_MODEL").orNull?.let {
        systemProperty("scalajaca.testModel", it)
    }
}
