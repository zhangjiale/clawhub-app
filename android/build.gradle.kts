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

subprojects {
    // Force every Android subproject (plugins) to compile against API 36.
    // Several plugins hardcode a lower compileSdk (file_picker 8.3.7 → 34,
    // connectivity_plus/device_info_plus/flutter_local_notifications/
    // flutter_secure_storage → 34, workmanager → 33, jni* → 35), which is below
    // flutter_plugin_android_lifecycle 2.0.35's required minCompileSdk (36) and
    // breaks :checkDebugAarMetadata. flutter.compileSdkVersion is already 36; this
    // matches it for plugins that fail to use flutter.compileSdkVersion.
    // Bump if a transitive dependency ever requires > 36.
    //
    // evaluationDependsOn(":app") below forces :app to evaluate during root
    // configuration, so guard with state.executed — apply immediately for an
    // already-evaluated project, else defer to afterEvaluate so the plugin's own
    // (lower) compileSdk is overridden after its build script runs.
    if (state.executed) {
        extensions.findByType<com.android.build.api.dsl.CommonExtension>()?.compileSdk = 36
    } else {
        afterEvaluate {
            extensions.findByType<com.android.build.api.dsl.CommonExtension>()?.compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
