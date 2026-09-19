import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningPropertiesFile = rootProject.file("key.properties")
if (releaseSigningPropertiesFile.isFile) {
    FileInputStream(releaseSigningPropertiesFile).use { input ->
        releaseSigningProperties.load(input)
    }
}

fun signingValue(environmentName: String, propertyName: String): String? {
    return System.getenv(environmentName)?.takeIf { it.isNotEmpty() }
        ?: releaseSigningProperties.getProperty(propertyName)?.takeIf { it.isNotEmpty() }
}

val releaseStoreFilePath = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
val releaseSigningConfigured = listOf(
    releaseStoreFilePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { !it.isNullOrEmpty() }

android {
    namespace = "vn.hoadoninsight.hoadon_insight"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "vn.hoadoninsight.hoadon_insight"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
        }
        create("production") {
            dimension = "environment"
        }
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningConfigured) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

val verifyReleaseSigning = tasks.register("verifyReleaseSigning") {
    doLast {
        if (!releaseSigningConfigured) {
            throw GradleException(
                "Release signing is not configured. Set ANDROID_KEYSTORE_PATH, " +
                    "ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS and " +
                    "ANDROID_KEY_PASSWORD, or create android/key.properties.",
            )
        }
        val keystore = file(releaseStoreFilePath!!)
        if (!keystore.isFile) {
            throw GradleException("Android keystore does not exist: ${keystore.path}")
        }
    }
}

tasks.configureEach {
    if (name != verifyReleaseSigning.name && name.contains("Release", ignoreCase = true)) {
        dependsOn(verifyReleaseSigning)
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
