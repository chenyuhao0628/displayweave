import org.gradle.api.tasks.testing.logging.TestLogEvent

plugins {
    id("com.android.application")
}

val releaseKeystore = providers.environmentVariable("DISPLAYWEAVE_ANDROID_KEYSTORE")
val releaseStorePassword = providers.environmentVariable("DISPLAYWEAVE_ANDROID_STORE_PASSWORD")
val releaseKeyAlias = providers.environmentVariable("DISPLAYWEAVE_ANDROID_KEY_ALIAS")
val releaseKeyPassword = providers.environmentVariable("DISPLAYWEAVE_ANDROID_KEY_PASSWORD")
val displayWeaveBuildNumber = providers.environmentVariable("DISPLAYWEAVE_BUILD_NUMBER")
    .orElse("1")
val displayWeaveVersionName = providers.environmentVariable("DISPLAYWEAVE_VERSION_NAME")
    .orElse("0.1.0")
val hasReleaseSigning = listOf(
    releaseKeystore,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
).all { it.isPresent }

android {
    namespace = "app.opendisplay.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "app.opendisplay.android"
        minSdk = 26
        targetSdk = 36
        versionCode = displayWeaveBuildNumber.get().toInt()
        versionName = displayWeaveVersionName.get()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("previewRelease") {
                storeFile = file(releaseKeystore.get())
                storePassword = releaseStorePassword.get()
                keyAlias = releaseKeyAlias.get()
                keyPassword = releaseKeyPassword.get()
            }
        }
    }

    buildTypes {
        getByName("release") {
            signingConfigs.findByName("previewRelease")?.let { signingConfig = it }
        }
    }
}

val sdkRoot = providers.environmentVariable("ANDROID_SDK_ROOT")
    .orElse(providers.environmentVariable("ANDROID_HOME"))
    .orElse(providers.provider { "${System.getProperty("user.home")}/Library/Android/sdk" })

val selfTestClasses = layout.buildDirectory.dir("selfTest/classes")
val selfTestSourceRoots = files("src/main/java", "../tests/java")

fun androidJarFile() = file("${sdkRoot.get()}/platforms/android-36.1/android.jar")

val compileSelfTests by tasks.registering(JavaCompile::class) {
    description = "Compiles DisplayWeave Android plain Java self-tests."
    source(selfTestSourceRoots.asFileTree.matching { include("**/*.java") })
    classpath = files(androidJarFile())
    destinationDirectory.set(selfTestClasses)
    sourceCompatibility = JavaVersion.VERSION_17.toString()
    targetCompatibility = JavaVersion.VERSION_17.toString()
    options.compilerArgs.add("-Xlint:-options")
}

fun registerSelfTest(name: String, mainClassName: String) =
    tasks.register<JavaExec>(name) {
        group = "verification"
        description = "Runs $mainClassName."
        dependsOn(compileSelfTests)
        classpath(selfTestClasses, files(androidJarFile()))
        mainClass.set(mainClassName)
    }

val runProtocolSelfTest = registerSelfTest(
    "runProtocolSelfTest",
    "app.opendisplay.android.protocol.ProtocolSelfTest"
)

val runVideoStreamPolicySelfTest = registerSelfTest(
    "runVideoStreamPolicySelfTest",
    "app.opendisplay.android.VideoStreamPolicySelfTest"
)

val runReceiverLifecycleSelfTest = registerSelfTest(
    "runReceiverLifecycleSelfTest",
    "app.opendisplay.android.ReceiverLifecycleSelfTest"
)

val runReceiverConnectionSelfTest = registerSelfTest(
    "runReceiverConnectionSelfTest",
    "app.opendisplay.android.ReceiverConnectionSelfTest"
)

val runUpdatePolicySelfTest = registerSelfTest(
    "runUpdatePolicySelfTest",
    "app.opendisplay.android.update.UpdatePolicySelfTest"
)

val runUpdateVerifierSelfTest = registerSelfTest(
    "runUpdateVerifierSelfTest",
    "app.opendisplay.android.update.UpdateVerifierSelfTest"
)

tasks.withType<Test>().configureEach {
    testLogging {
        events = setOf(TestLogEvent.FAILED, TestLogEvent.SKIPPED)
    }
}

tasks.matching { it.name == "test" }.configureEach {
    dependsOn(
        runProtocolSelfTest,
        runVideoStreamPolicySelfTest,
        runReceiverLifecycleSelfTest,
        runReceiverConnectionSelfTest,
        runUpdatePolicySelfTest,
        runUpdateVerifierSelfTest,
    )
}
