import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "app.nekodot.nativeclient"
    compileSdk = 36
    defaultConfig { minSdk = 29 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }
}
kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_1_8 } }
dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation(project(":tauri-android"))
    implementation(platform("com.google.firebase:firebase-bom:34.5.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("com.google.android.gms:play-services-base:18.9.0")
    implementation("androidx.core:core-ktx:1.17.0")
}
