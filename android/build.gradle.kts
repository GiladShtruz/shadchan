allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// `android.builtInKotlin=false` (gradle.properties) keeps the plugins that
// still apply the Kotlin Gradle Plugin themselves working on AGP 9. But some
// FlutterFire releases (firebase_app_check 0.4.4+1, firebase_ai 3.12.1,
// firebase_storage 13.4.0) decide by AGP *version* alone: on AGP 9 they skip
// `kotlin-android` and expect AGP's built-in Kotlin — which is off — so their
// Kotlin sources were never compiled and GeneratedPluginRegistrant failed with
// "cannot find symbol FirebaseAppCheckPlugin". Apply KGP to every Android
// library plugin that has Kotlin sources (a no-op for those that apply it
// already), and keep each one's Kotlin JVM target equal to its Java target,
// since the plugins only set `kotlinOptions` on AGP < 9.
// Older plugins (file_picker 8.x builds against android-34) fail AGP 9's
// checkReleaseAarMetadata, because flutter_plugin_android_lifecycle now
// requires compileSdk 36 from everything that depends on it. Raise any
// plugin below that floor to it in finalizeDsl, the hook AGP provides for
// changing a project's DSL after its own build script has run. compileSdk
// only decides which API stubs a library compiles against; minSdk,
// targetSdk and runtime behaviour are untouched.
val pluginCompileSdkFloor = 36

subprojects {
    pluginManager.withPlugin("com.android.library") {
        if (file("src/main/kotlin").isDirectory) {
            pluginManager.apply("org.jetbrains.kotlin.android")
        }
        extensions
            .getByType(com.android.build.api.variant.LibraryAndroidComponentsExtension::class.java)
            .finalizeDsl { dsl ->
                val current = dsl.compileSdk
                if (current == null || current < pluginCompileSdkFloor) {
                    dsl.compileSdk = pluginCompileSdkFloor
                }
            }
    }
    pluginManager.withPlugin("org.jetbrains.kotlin.android") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            val android =
                project.extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)
            val target = android?.compileOptions?.targetCompatibility?.toString()
            if (target != null) {
                compilerOptions.jvmTarget.set(
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(target),
                )
            }
        }
    }
}

// Belt and braces for the lint-vital crash on Java 17 (see app/build.gradle.kts):
// no project, app or plugin, runs the release lint tasks.
subprojects {
    tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
