import com.android.build.gradle.LibraryExtension
import org.gradle.kotlin.dsl.findByType

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
    if (name == "flutter_image_compress") {
        plugins.withId("com.android.library") {
            extensions.findByType<LibraryExtension>()?.let { androidExt ->
                // Define namespace to satisfy AGP 8+ requirements for the plugin module.
                if (androidExt.namespace.isNullOrBlank()) {
                    androidExt.namespace = "com.zhihu.flutter.image_compress"
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
