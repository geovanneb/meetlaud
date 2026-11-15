plugins {
    alias(libs.plugins.android.library)
}

// whisper.cpp, built from a pinned source release (see src/main/cpp/CMakeLists.txt). Transcription.
// Only the JNI bridge is here: the engines that the app uses live in app's infra.engines, behind domain ports.
android {
    namespace = "com.meetlaud.engines.whisper"
    compileSdk = 36
    ndkVersion = libs.versions.ndk.get()

    defaultConfig {
        minSdk = 29
        ndk { abiFilters += "arm64-v8a" }
        externalNativeBuild { cmake { arguments += listOf("-DANDROID_STL=c++_static", "-DCMAKE_BUILD_TYPE=Release") } }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = libs.versions.cmake.get()
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { jvmToolchain(17) }
