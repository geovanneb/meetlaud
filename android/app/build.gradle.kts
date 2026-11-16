plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.meetlaud.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.meetlaud.app"
        minSdk = 29
        targetSdk = 36
        // A release sets both from its tag (docs/releasing.md): v1.2.3 gives 1.2.3, and the run number counts up.
        versionCode = (findProperty("meetlaud.versionCode") as String?)?.toInt() ?: 1
        versionName = (findProperty("meetlaud.versionName") as String?) ?: "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // The engines are built for 64-bit ARM only, which every supported phone has.
        ndk { abiFilters += "arm64-v8a" }
    }

    // The release key lives in CI secrets, never in the repository. Without it, a release build stays unsigned.
    val keystore = System.getenv("MEETLAUD_KEYSTORE_FILE")?.let(::file)?.takeIf { it.exists() }
    signingConfigs {
        if (keystore != null) {
            create("release") {
                storeFile = keystore
                storePassword = System.getenv("MEETLAUD_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("MEETLAUD_KEY_ALIAS")
                keyPassword = System.getenv("MEETLAUD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // No shrinking: JNI and ONNX Runtime reach classes by name, and the APK's size is mostly native code.
            isMinifyEnabled = false
            if (keystore != null) signingConfig = signingConfigs.getByName("release")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { jvmToolchain(17) }

// Text comes from the iOS String Catalogs, so both apps always say the same thing (D-084).
val repoRoot = rootDir.parentFile
val generatedStrings = layout.buildDirectory.dir("generated/l10n")
val generateStrings by tasks.registering(Exec::class) {
    inputs.files(fileTree(repoRoot) { include("ios/**/*.xcstrings", "android/l10n/*.xcstrings", "ios/Packages/UI/Localization/Sources/*.swift") }
        .matching { exclude("**/.build/**", "**/build/**") })
    inputs.file(repoRoot.resolve("Tools/android-strings"))
    outputs.dir(generatedStrings)
    commandLine("python3", repoRoot.resolve("Tools/android-strings").path, repoRoot.path,
        generatedStrings.get().dir("res").asFile.path, generatedStrings.get().dir("kotlin").asFile.path)
}
android.sourceSets["main"].res.directories.add(generatedStrings.get().dir("res").asFile.path)
android.sourceSets["main"].kotlin.directories.add(generatedStrings.get().dir("kotlin").asFile.path)
// The licenses screen shows the same notices file as iOS, from the repository root.
val generatedNotices = layout.buildDirectory.dir("generated/notices")
val copyNotices by tasks.registering(Copy::class) {
    from(repoRoot.resolve("THIRD_PARTY_NOTICES.md"))
    // The speed test clip, the same 30 seconds iOS uses (public domain, see the notices).
    from(repoRoot.resolve("ios/App/Resources/speed-test.m4a"))
    into(generatedNotices)
}
android.sourceSets["main"].assets.directories.add(generatedNotices.get().asFile.path)
tasks.named("preBuild") { dependsOn(generateStrings, copyNotices) }

dependencies {
    implementation(project(":domain"))
    implementation(project(":engines:whisper"))
    implementation(project(":engines:llama"))
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.androidx.sqlite.bundled)
    implementation(libs.onnxruntime.android)

    testImplementation(libs.junit)
    testImplementation(libs.onnxruntime.jvm)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext)
    androidTestImplementation(libs.uiautomator)
    debugImplementation(libs.compose.ui.test.manifest)
}
