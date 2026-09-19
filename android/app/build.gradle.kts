plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.toollab.warrant_book"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.toollab.warrant_book"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        multiDexEnabled = true
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Preview/distribution signing for this repo (issue #7). The
        // keystore is committed deliberately: it is a tool-lab preview
        // key, NOT a Play upload key. See docs/releases.md for how to
        // swap in a private release keystore via CI secrets.
        create("preview") {
            // CI (or a local override) can point WB_KEYSTORE_FILE at a
            // private keystore; the committed preview key is the default.
            storeFile = System.getenv("WB_KEYSTORE_FILE")?.let { file(it) }
                ?: file("warrant_book_preview.jks")
            storePassword = System.getenv("WB_KEYSTORE_PASSWORD")
                ?: "warrant-book-preview"
            keyAlias = "warrant-book-preview"
            keyPassword = System.getenv("WB_KEY_PASSWORD")
                ?: "warrant-book-preview"
        }
    }

    buildTypes {
        release {
            // Signed with the repo preview key so CI can publish a
            // verifiable release APK; replace via docs/releases.md
            // before any real distribution.
            signingConfig = signingConfigs.getByName("preview")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
