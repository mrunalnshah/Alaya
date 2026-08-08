// **No `allprojects { repositories { ... } }` block.**
//
// Gradle is configured to prefer repositories declared in `settings.gradle.kts`
// (`dependencyResolutionManagement`), and declaring them here as well is the error:
//
//     Build was configured to prefer settings repositories over project repositories
//     but repository 'Google' was added by build file 'build.gradle.kts'
//
// Modern Flutter templates declare `google()` and `mavenCentral()` once, in settings, precisely so
// that a subproject cannot introduce a different resolution order. Nothing needs adding here.

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}