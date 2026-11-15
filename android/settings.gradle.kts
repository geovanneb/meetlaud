pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "Meetlaud"

// domain: pure Kotlin, the counterpart of ios/Packages/Core/Domain. No Android, no adapter.
// app: everything else, in packages that mirror the iOS modules. Tools/check-android keeps their boundaries.
// engines: whisper.cpp and llama.cpp, each built from pinned sources with its own copy of ggml. JNI bridges only.
include(":domain", ":app", ":engines:whisper", ":engines:llama")
