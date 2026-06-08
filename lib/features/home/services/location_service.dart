import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

class LocationService {
  /// Solicita permisos y verifica si el GPS está encendido
  Future<bool> checkPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Verificar hardware
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    // 2. Verificar permisos en primer plano (Mientras la app está en uso)
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings(); // Se utiliza Geolocator de forma explícita
      return false;
    }

    // =========================================================================
    // CORRECCIÓN PARA SEGUNDO PLANO (Permitir todo el tiempo / ACCESS_BACKGROUND_LOCATION)
    // Obligatorio para Android 10+ (Note 9) y Android 14 (Moto G34)
    // =========================================================================
    if (permission == LocationPermission.whileInUse) {
      final alwaysStatus = await Permission.locationAlways.status;
      if (alwaysStatus.isDenied) {
        // En Android 11+ esto abrirá los ajustes de ubicación de la app automáticamente
        // para que el conductor seleccione manualmente la opción "Permitir todo el tiempo".
        final result = await Permission.locationAlways.request();
        if (!result.isGranted) {
          debugPrint(
            "⚠️ El conductor denegó la ubicación todo el tiempo (segundo plano).",
          );
          // Puedes retornar false si tu lógica de negocio exige este permiso de fondo
          // para poder recibir asignaciones de viajes en segundo plano.
        }
      }
    }

    // 3. Solicitar exención de optimización de batería (Crucial en Moto G34 con Android 14)
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    if (batteryStatus.isDenied) {
      await Permission.ignoreBatteryOptimizations.request();
    }

    return true;
  }

  /// Obtiene la posición actual con Timeout y Fallback.
  /// Esto evita el ANR (App Not Responding).
  Future<Position?> getCurrentLocation() async {
    try {
      // 1. Intentar obtener la última ubicación conocida (es instantáneo)
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }

      // 2. Si no hay última conocida, pedir la actual pero con TIMEOUT
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      return null;
    }
  }

  Stream<Position> getPositionStream() {
    late final LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 10),
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
        distanceFilter: 10,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    }

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
