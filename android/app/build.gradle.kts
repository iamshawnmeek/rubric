import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.supposedlysam.rubric"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.supposedlysam.rubric"
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

    // The Play upload key. On Codemagic it comes from the environment
    // (CM_KEYSTORE_PATH and friends, see codemagic.yaml); on a dev machine
    // from .contrib/android/ (gitignored, docs/DEPLOY.md). Google Play App
    // Signing holds the real app-signing key, so a lost upload key can be
    // reset with Google.
    val repoRoot = rootProject.projectDir.parentFile
    val localKey = File(repoRoot, ".contrib/android/keystore.env")
    val localProps = Properties().apply {
        if (localKey.exists()) localKey.reader().use { load(it) }
    }
    val keystorePath = System.getenv("CM_KEYSTORE_PATH")
        ?: File(repoRoot, ".contrib/android/upload-keystore.jks").takeIf { it.exists() }?.path
    signingConfigs {
        create("upload") {
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD") ?: localProps.getProperty("STORE_PASSWORD")
                keyAlias = System.getenv("CM_KEY_ALIAS") ?: localProps.getProperty("KEY_ALIAS")
                keyPassword = System.getenv("CM_KEY_PASSWORD") ?: localProps.getProperty("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePath != null) {
                signingConfigs.getByName("upload")
            } else {
                // No upload key here: `flutter run --release` still works on
                // a dev machine, but this build can never go to Google Play.
                logger.warn("Rubric: no upload key found; release is DEBUG-signed and Play will reject it.")
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
