plugins {
    id("com.android.application") version "8.10.1" apply false
}

tasks.register("test") {
    dependsOn(":app:test")
}
