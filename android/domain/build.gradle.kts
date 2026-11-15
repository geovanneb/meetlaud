// The counterpart of ios/Packages/Core/Domain: pure Kotlin. Tools/check-android rejects any Android or adapter import.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    // What java.text.BreakIterator is on Android, for the parity test. Tests only.
    testImplementation(libs.icu4j)
}

tasks.test {
    // The shared cases and the iOS Domain's answers to them.
    systemProperty("parity.dir", rootDir.parentFile.resolve("Tools/parity").path)
    inputs.dir(rootDir.parentFile.resolve("Tools/parity"))
}
