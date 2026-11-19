import java.util.Base64
import java.util.Properties
import java.net.URI

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Public Dart defines are the single source for Play identity and API settings.
// Debug keeps its existing ID so installed development data is not migrated.
val releaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true) || it in listOf("assemble", "bundle", "build")
}
val publicDefines = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(',').filter { it.isNotEmpty() }.mapNotNull {
        val decoded = runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrNull()
        decoded?.split('=', limit = 2)?.takeIf { parts -> parts.size == 2 }
            ?.let { parts -> parts[0] to parts[1] }
    }.toMap()
val playId = publicDefines["PLAY_APPLICATION_ID"].orEmpty()
val playName = publicDefines["PLAY_APP_NAME"].orEmpty()
val signingProperties = Properties().apply {
    val source = rootProject.file("key.properties")
    if (source.exists()) source.inputStream().use { load(it) }
}
fun signingValue(property: String, environment: String): String =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(property).orEmpty()
val uploadStore = signingValue("storeFile", "GYM_UPLOAD_KEYSTORE")
val uploadAlias = signingValue("keyAlias", "GYM_UPLOAD_KEY_ALIAS")
val uploadStorePassword = signingValue("storePassword", "GYM_UPLOAD_STORE_PASSWORD")
val uploadKeyPassword = signingValue("keyPassword", "GYM_UPLOAD_KEY_PASSWORD")
val signingReady = listOf(uploadStore, uploadAlias, uploadStorePassword, uploadKeyPassword)
    .all { it.isNotBlank() } && rootProject.file(uploadStore).isFile

if (releaseBuild) {
    require(playId.matches(Regex("[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*){2,}")) &&
        !playId.startsWith("com.example.") && !playId.contains("placeholder")) {
        "Release requires the permanent PLAY_APPLICATION_ID. See docs/play-release.md."
    }
    require(playName == "MuscleDesk" && publicDefines["APP_ENV"] == "production" &&
        publicDefines["API_BASE_URL"] == "https://gym-api.semgroup.in/api/v1/") {
        "Release requires PLAY_APP_NAME=MuscleDesk, APP_ENV=production and the approved production API_BASE_URL."
    }
    val publicFields = listOf("PLAY_APP_NAME", "PUBLISHER_NAME", "SUPPORT_EMAIL",
        "PRIVACY_POLICY_URL", "ACCOUNT_DELETION_URL")
    require(publicFields.all { key ->
        val value = publicDefines[key].orEmpty()
        value.isNotBlank() && !Regex("replace|placeholder|example\\.|\\.invalid|\\.test", RegexOption.IGNORE_CASE)
            .containsMatchIn(value)
    } && publicDefines["SUPPORT_EMAIL"].orEmpty().matches(Regex("[^\\s@]+@[^\\s@]+\\.[^\\s@]+"))) {
        "Release requires final publisher/support information and public privacy/deletion URLs."
    }
    require(listOf("API_BASE_URL", "PRIVACY_POLICY_URL", "ACCOUNT_DELETION_URL").all { key ->
        val uri = runCatching { URI(publicDefines[key].orEmpty()) }.getOrNull()
        uri != null && uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null &&
            uri.query == null && uri.fragment == null &&
            uri.host !in listOf("localhost", "127.0.0.1", "[::1]")
    }) {
        "Release API and policy URLs must be public HTTPS URLs without credentials, query or fragment."
    }
    require(signingReady && uploadAlias != "androiddebugkey") {
        "Release requires a private upload keystore; debug signing is forbidden. See android/key.properties.example."
    }
}

android {
    namespace = "com.example.gym_management_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = if (releaseBuild) playId else "com.example.gym_management_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (signingReady) {
                storeFile = rootProject.file(uploadStore)
                storePassword = uploadStorePassword
                keyAlias = uploadAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            resValue("string", "app_name", "MuscleDesk · Dev")
        }
        getByName("profile") {
            resValue("string", "app_name", "MuscleDesk · Profile")
        }
        release {
            resValue("string", "app_name", playName.ifBlank { "MuscleDesk" })
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
