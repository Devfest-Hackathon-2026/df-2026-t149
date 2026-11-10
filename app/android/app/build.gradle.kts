plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 地図のキーはapp/.env の MAPS_ANDROID_API_KEY から読む（CI では環境変数）。
// キーがなくてもビルドでき、アプリは簡易地図で動く
val rootEnvFile = rootProject.file("../.env")
val envValues: Map<String, String> =
    (if (rootEnvFile.exists()) rootEnvFile.readLines() else emptyList())
        .map { it.trim().removePrefix("export ").trim() }
        .filter { it.isNotEmpty() && !it.startsWith("#") && it.contains("=") }
        .associate { it.substringBefore("=").trim() to it.substringAfter("=").trim().trim('"', '\'') }
val mapsApiKey: String =
    envValues["MAPS_ANDROID_API_KEY"]?.takeIf { it.isNotEmpty() }
        ?: System.getenv("MAPS_ANDROID_API_KEY")
        ?: ""

val signingKeys = listOf(
    "ANDROID_SIGNING_STORE_FILE", "ANDROID_SIGNING_STORE_PASSWORD",
    "ANDROID_SIGNING_KEY_ALIAS", "ANDROID_SIGNING_KEY_PASSWORD"
)
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    require(signingKeys.all { !envValues[it].isNullOrBlank() }) {
        "配布用の署名設定がありません。app/.env の ANDROID_SIGNING_* を設定してください"
    }
}

// Firebase の設定を app/.env の FIREBASE_* から、アプリに同梱するファイル（Git に含めない）に書く。
// --dart-define-from-file を付け忘れて flutter build apk しても、ログインできるアプリにするため。
// Flutter がアセットを集めるより前に書く必要があるので、タスクではなく設定の読み込み時に書く
val firebaseValues = envValues.filter { it.key.startsWith("FIREBASE_") && it.value.isNotEmpty() }
if (firebaseValues.isNotEmpty()) {
    val json = firebaseValues.entries.joinToString(",", "{", "}") { (k, v) ->
        "\"$k\":\"" + v.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    }
    rootProject.file("../assets/config/firebase.local.json").apply {
        parentFile.mkdirs()
        if (!exists() || readText() != json) {
            writeText(json)
        }
    }
}

android {
    namespace = "com.example.uramichi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications が Java 8 以降の日付の API を使うため、古い Android でも動くように変換する
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.uramichi"
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
        manifestPlaceholders["mapsApiKey"] = mapsApiKey
    }

    signingConfigs {
        create("release") {
            storeFile = envValues["ANDROID_SIGNING_STORE_FILE"]?.takeIf { it.isNotEmpty() }
                ?.let { rootProject.file("../$it") }
            storePassword = envValues["ANDROID_SIGNING_STORE_PASSWORD"]
            keyAlias = envValues["ANDROID_SIGNING_KEY_ALIAS"]
            keyPassword = envValues["ANDROID_SIGNING_KEY_PASSWORD"]
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// flutter build apk で、全部入りの APK（app-release.apk）と一緒に、CPU の種類（ABI）ごとの小さな APK も作る。
// 分割の対象は、Android の既定（mips などを含む全種類）ではなく、Flutter が動く3種類に絞る。
// Flutter の Gradle プラグインが設定する ndk.abiFilters は残し、全部入りの APK に x86 のライブラリを入れない
androidComponents {
    finalizeDsl { extension ->
        extension.splits.abi.apply {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true
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

dependencies {
    // isCoreLibraryDesugaringEnabled で使う変換の部品
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
