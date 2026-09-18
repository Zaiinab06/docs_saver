allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            freeCompilerArgs.add("-Xjvm-target-validation-mode=warning")
        }
    }
}

subprojects {
    val configureAndroid: Project.() -> Unit = {
        val android = extensions.findByName("android")
        if (android != null) {
            for (method in android.javaClass.methods) {
                if ((method.name == "compileSdkVersion" || method.name == "setCompileSdkVersion" || method.name == "setCompileSdk") && method.parameterTypes.size == 1) {
                    try {
                        val paramType = method.parameterTypes[0]
                        if (paramType == Int::class.javaPrimitiveType || paramType == java.lang.Integer::class.java) {
                            method.invoke(android, 36)
                        }
                    } catch (_: Exception) {}
                }
            }
        }
    }

    if (state.executed) {
        configureAndroid()
    } else {
        afterEvaluate {
            configureAndroid()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
