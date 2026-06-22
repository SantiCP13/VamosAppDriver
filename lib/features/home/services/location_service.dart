// lib/features/home/services/location_service.dart
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/services/storage_service.dart';

// 1. Definimos los perfiles de rastreo que usará la app de forma interna
enum TrackingProfile {
  offline, // Consumo mínimo, precisión por red (sin GPS satelital activo)
  onlineIdle, // Conectado esperando viaje, precisión moderada
  activeTrip, // Viaje en curso, precisión máxima y Foreground Service activo
}

class LocationService {
  // (Mantenemos checkPermissions y getCurrentLocation idénticos a como los tienes)
  Future<bool> checkPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }

    if (permission == LocationPermission.whileInUse) {
      final alwaysStatus = await Permission.locationAlways.status;
      if (alwaysStatus.isDenied) {
        await Permission.locationAlways.request();
      }
    }

    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    if (batteryStatus.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    return true;
  }

  Future<Position?> getCurrentLocation() async {
    try {
      debugPrint(
        "🛰️ [GPS CASCADE - NIVEL 1] Buscando posición satelital fresca...",
      );
      Position current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
      return current;
    } catch (e) {
      debugPrint(
        "⚠️ [GPS CASCADE - NIVEL 1 FALLO] Fallo GPS activo. Pasando a caché...",
      );
      try {
        Position? lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) return lastKnown;
      } catch (ex) {
        debugPrint("🚨 [GPS CASCADE - NIVEL 2 ERROR] $ex");
      }
      try {
        final storage = sl<StorageService>();
        final savedPos = await storage.getLastPosition();
        if (savedPos != null) {
          return Position(
            latitude: savedPos['lat']!,
            longitude: savedPos['lng']!,
            timestamp: DateTime.now(),
            accuracy: 15.0,
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
          );
        }
      } catch (ex) {
        debugPrint("🚨 [GPS CASCADE - NIVEL 3 ERROR] $ex");
      }
    }
    return null;
  }

  // 2. NUEVO: getPositionStream dinámico que acepta un perfil específico
  Stream<Position> getPositionStream({required TrackingProfile profile}) {
    late final LocationSettings locationSettings;

    // Mapeo dinámico de precisión y frecuencia según el estado actual
    LocationAccuracy accuracy;
    int distanceFilter;
    int intervalSeconds;
    bool useWakeLock;

    switch (profile) {
      case TrackingProfile.offline:
        accuracy = LocationAccuracy.low; // Evita usar hardware satelital puro
        distanceFilter = 25; // Ignora pequeñas fluctuaciones
        intervalSeconds = 45; // Actualiza cada 45 segundos
        useWakeLock = false;
        break;
      case TrackingProfile.onlineIdle:
        accuracy = LocationAccuracy.medium; // Precisión balanceada por red/GPS
        distanceFilter = 10;
        intervalSeconds = 12; // Actualiza cada 12 segundos
        useWakeLock = false;
        break;
      case TrackingProfile.activeTrip:
        accuracy = LocationAccuracy.high; // Precisión máxima para navegación
        distanceFilter = 2; // Sensibilidad fina
        intervalSeconds = 2; // Actualiza constantemente cada 2 segundos
        useWakeLock = true; // Previene suspensiones de CPU
        break;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        forceLocationManager: false,
        intervalDuration: Duration(seconds: intervalSeconds),
        foregroundNotificationConfig: useWakeLock
            ? const ForegroundNotificationConfig(
                notificationText:
                    "VAMOS está transmitiendo tu ubicación para guiar el viaje activo.",
                notificationTitle: "Servicio de Conducción Activo",
                enableWakeLock: true,
              )
            : null,
      );
    } else {
      locationSettings = AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: useWakeLock,
      );
    }

    debugPrint(
      "⚙️ [GPS CONFIG] Stream reiniciado. Perfil: ${profile.name} (Acc: ${accuracy.name}, Int: ${intervalSeconds}s, Filt: ${distanceFilter}m)",
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
