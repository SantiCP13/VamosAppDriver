import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Aquí NO pongas versión, se hereda de settings.gradle.kts
    id("dev.flutter.flutter-gradle-plugin") 
}

// Cargar las propiedades usando las clases importadas arriba
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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
    
    @Suppress("DEPRECATION")
    kotlinOptions {
        // Silenciamos la advertencia de obsolescencia de forma compatible
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

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            
            // Evitamos usar "it" con una estructura condicional clásica
            val storePath = keystoreProperties.getProperty("storeFile")
            storeFile = if (storePath != null) file(storePath) else null
            
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
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