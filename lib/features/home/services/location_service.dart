// lib/features/home/services/location_service.dart
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import '../../../core/di/injection_container.dart'; // Inyector de dependencias (sl)
import '../../../core/services/storage_service.dart'; // Import del servicio de persistencia

class LocationService {
  /// Solicita permisos y verifica si el GPS está encendido
  Future<bool> checkPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint(
        "📡 [LocationService] El hardware de ubicación (GPS) está desactivado.",
      );
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }

    if (permission == LocationPermission.whileInUse) {
      final alwaysStatus = await Permission.locationAlways.status;
      if (alwaysStatus.isDenied) {
        final result = await Permission.locationAlways.request();
        if (!result.isGranted) {
          debugPrint(
            "⚠️ [LocationService] Permiso de segundo plano (locationAlways) denegado.",
          );
        }
      }
    }

    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    if (batteryStatus.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    return true;
  }

  /// Obtiene la posición actual con un sistema de cascada resiliente de 3 niveles
  Future<Position?> getCurrentLocation() async {
    try {
      debugPrint(
        "🛰️ [GPS CASCADE - NIVEL 1] Intentando obtener ubicación GPS satelital activa...",
      );
      // Intentar obtener la posición actual con un timeout estricto de 4 segundos para evitar ANR
      Position current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );

      debugPrint(
        "✅ [GPS CASCADE - NIVEL 1 ÉXITO] Posición fresca del sensor: (${current.latitude}, ${current.longitude})",
      );
      return current;
    } catch (e) {
      debugPrint(
        "⚠️ [GPS CASCADE - NIVEL 1 FALLO] No se pudo obtener GPS en tiempo real (Timeout o falta de señal/red).",
      );

      // NIVEL 2: Intentar obtener la caché de ubicación del sistema operativo
      try {
        debugPrint(
          "🛰️ [GPS CASCADE - NIVEL 2] Buscando última ubicación registrada en la caché del OS...",
        );
        Position? lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          debugPrint(
            "✅ [GPS CASCADE - NIVEL 2 ÉXITO] Recuperada del OS: (${lastKnown.latitude}, ${lastKnown.longitude})",
          );
          return lastKnown;
        }
        debugPrint(
          "⚠️ [GPS CASCADE - NIVEL 2 FALLO] La caché del sistema operativo retornó nulo.",
        );
      } catch (ex) {
        debugPrint(
          "🚨 [GPS CASCADE - NIVEL 2 ERROR] Fallo al consultar caché del OS: $ex",
        );
      }

      // NIVEL 3: Leer la ubicación persistida en la base de datos local de la App (StorageService)
      try {
        debugPrint(
          "💾 [GPS CASCADE - NIVEL 3] Intentando recuperar la última ubicación registrada por VAMOS...",
        );
        final storage = sl<StorageService>();
        final savedPos = await storage.getLastPosition();

        if (savedPos != null) {
          final double lat = savedPos['lat']!;
          final double lng = savedPos['lng']!;
          debugPrint(
            "✅ [GPS CASCADE - NIVEL 3 ÉXITO] Ubicación recuperada del disco persistente de la aplicación: ($lat, $lng)",
          );

          // Retornamos un objeto Position simulado para mantener compatibilidad con toda la app sin romper firmas
          return Position(
            latitude: lat,
            longitude: lng,
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
        debugPrint(
          "❌ [GPS CASCADE - NIVEL 3 FALLO] No se encontraron registros de ubicación previos guardados por esta app.",
        );
      } catch (ex) {
        debugPrint(
          "🚨 [GPS CASCADE - NIVEL 3 ERROR] Error de lectura en disco persistente local: $ex",
        );
      }
    }
    return null;
  }

  Stream<Position> getPositionStream() {
    late final LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter:
            0, // 🔴 MODIFICADO: 0 metros para capturar cualquier micro-movimiento constantemente
        forceLocationManager: false,
        intervalDuration: const Duration(
          seconds: 2,
        ), // 🔴 MODIFICADO: Solicitar ubicación constantemente cada 2 segundos
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText:
              "VAMOS está transmitiendo tu ubicación para recibir viajes.",
          notificationTitle: "Servicio de Conducción Activo",
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0, // 🔴 MODIFICADO: 0 metros para iOS
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
