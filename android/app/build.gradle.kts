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
        isCoreLibraryDesugaringEnabled = true
        
        // Cambiar de VERSION_1_8 a VERSION_11
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    
    kotlinOptions {
        // Cambiar de "1.8" a "11"
        jvmTarget = "11"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID
        applicationId = "com.vamos.driver.vamos_driver"
        minSdk = flutter.minSdkVersion  
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

// Bloque de dependencias requerido para descargar la librería de desugaring
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
}