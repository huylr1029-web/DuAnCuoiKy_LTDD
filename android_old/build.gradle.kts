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

// Nâng compileSdk cho các plugin cũ (vd: agora_rtc_engine đang dùng 31).
subprojects {
    if (project.name != "app" && !project.state.executed) {
        afterEvaluate {
            val androidExt = extensions.findByName("android")
            if (androidExt != null) {
                try {
                    val current = androidExt.javaClass
                        .getMethod("getCompileSdk")
                        .invoke(androidExt) as? Int
                    if (current == null || current < 36) {
                        androidExt.javaClass
                            .getMethod("setCompileSdk", Integer::class.javaObjectType)
                            .invoke(androidExt, 36)
                    }
                } catch (e: Exception) {
                    println("Không thể nâng compileSdk cho ${project.name}: ${e.message}")
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}