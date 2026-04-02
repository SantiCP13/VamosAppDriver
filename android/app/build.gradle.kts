plugins {
    id("com.android.application")
    id("kotlin-android")
    // Aquí NO pongas versión, se hereda de settings.gradle.kts
    id("dev.flutter.flutter-gradle-plugin") 
}

android {
    namespace = "com.vamos.driver.vamos_driver"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID
        applicationId = "com.vamos.driver.vamos_driver"
        minSdk = flutter.minSdkVersion // Cambia flutter.minSdkVersion por 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
