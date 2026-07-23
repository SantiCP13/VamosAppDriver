import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart'; // <--- AGREGADA IMPORTACIÓN OFICIAL
import '../../../core/di/injection_container.dart';
import '../../../core/services/storage_service.dart';

// 1. Definimos los perfiles de rastreo que usará la app de forma interna
enum TrackingProfile {
  offline, // Consumo mínimo, precisión por red (sin GPS satelital activo)
  onlineIdle, // Conectado esperando viaje, precisión moderada con Foreground activo
  activeTrip, // Viaje en curso, precisión máxima y Foreground Service activo
}

class LocationService {
  // Variable de estado interna para autodetección de entorno
  bool _isEmulator = false;

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

    // Solicitar permisos de notificación en Android 13/14+
    if (defaultTargetPlatform == TargetPlatform.android) {
      final notificationStatus = await Permission.notification.status;
      if (notificationStatus.isDenied) {
        await Permission.notification.request();
      }
    }

    // 🟢 VALIDACIÓN ESTRICTA: Ubicación en segundo plano (Siempre permitir)
    if (permission == LocationPermission.whileInUse) {
      final alwaysStatus = await Permission.locationAlways.status;
      if (alwaysStatus.isDenied || alwaysStatus.isPermanentlyDenied) {
        final requestedAlways = await Permission.locationAlways.request();
        if (!requestedAlways.isGranted) return false;
      }
    }

    // 🟢 VALIDACIÓN ESTRICTA: Omitir optimización de batería
    final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
    if (batteryStatus.isDenied || batteryStatus.isPermanentlyDenied) {
      final requestedBattery = await Permission.ignoreBatteryOptimizations
          .request();
      if (!requestedBattery.isGranted) return false;
    }

    // Doble chequeo final de seguridad física
    LocationPermission finalPermission = await Geolocator.checkPermission();
    if (finalPermission != LocationPermission.always &&
        finalPermission != LocationPermission.whileInUse) {
      return false;
    }

    final finalBattery = await Permission.ignoreBatteryOptimizations.status;
    if (!finalBattery.isGranted) {
      return false;
    }

    // =====================================================================
    // DETECCIÓN DINÁMICA DE EMULADOR VS DISPOSITIVO FÍSICO
    // =====================================================================
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        _isEmulator = !androidInfo.isPhysicalDevice;
        debugPrint(
          "🤖 [GPS AUTO-CONFIG] Entorno detectado: ${_isEmulator ? 'EMULADOR (Forzar LocationManager)' : 'TELÉFONO FÍSICO (Fused Location Provider)'}",
        );
      }
    } catch (e) {
      debugPrint(
        "⚠️ [GPS AUTO-CONFIG ERROR] No se pudo determinar el tipo de dispositivo: $e",
      );
    }

    return true;
  }

  // --- CALIBRACIÓN DE TIEMPOS DE SINTONIZACIÓN SATECO (COLD START) ---
  Future<Position?> getCurrentLocation() async {
    try {
      debugPrint(
        "🛰️ [GPS CASCADE - NIVEL 1] Buscando posición satelital fresca (GPS)...",
      );

      // CORRECCIÓN: Usar los parámetros válidos de geolocator para un único fetch
      Position current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      return current;
    } catch (e) {
      debugPrint(
        "⚠️ [GPS CASCADE - NIVEL 1 FALLO] Fallo GPS activo. Pasando a Nivel 2 (Red/Wi-Fi)...",
      );
      try {
        // Intento secundario: Triangulación de antenas de celular/Wi-Fi rápida si falla el satélite
        Position networkFallback = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 5),
        );
        return networkFallback;
      } catch (ex) {
        debugPrint(
          "⚠️ [GPS CASCADE - NIVEL 2 FALLO] Fallo Red. Pasando a Nivel 3 (Última ubicación conocida)...",
        );
        try {
          Position? lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) return lastKnown;
        } catch (error) {
          debugPrint("🚨 [GPS CASCADE - NIVEL 3 ERROR] $error");
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
        } catch (error) {
          debugPrint("🚨 [GPS CASCADE - NIVEL 4 ERROR] $error");
        }
      }
    }
    return null;
  }

  // 2. getPositionStream dinámico con Hardware Nativo
  Stream<Position> getPositionStream({required TrackingProfile profile}) {
    late final LocationSettings locationSettings;

    LocationAccuracy accuracy;
    int distanceFilter;
    int intervalSeconds;
    bool enableForeground;
    String notificationTitle;
    String notificationText;

    switch (profile) {
      case TrackingProfile.offline:
        accuracy = LocationAccuracy.low;
        distanceFilter = 25;
        intervalSeconds = 45;
        enableForeground = false;
        notificationTitle = "";
        notificationText = "";
        break;

      case TrackingProfile.onlineIdle:
        accuracy = LocationAccuracy.medium;
        distanceFilter = 0;
        intervalSeconds = 10;
        enableForeground = true;
        notificationTitle = "Conductor en Línea";
        notificationText =
            "VAMOS está conectado esperando asignaciones de viaje.";
        break;

      case TrackingProfile.activeTrip:
        accuracy = LocationAccuracy.high;
        distanceFilter = 0;
        intervalSeconds = 4; // Intervalo óptimo de actualización en tránsito
        enableForeground = true;
        notificationTitle = "Servicio de Conducción Activo";
        notificationText =
            "Navegación en tiempo real activa para guiar tu viaje en curso.";
        break;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        // ESTABILIZADOR DINÁMICO: En emuladores utiliza el manager nativo; en celulares físicos usa Fused Location
        forceLocationManager: _isEmulator,
        intervalDuration: Duration(seconds: intervalSeconds),
        foregroundNotificationConfig: enableForeground
            ? ForegroundNotificationConfig(
                notificationText: notificationText,
                notificationTitle: notificationTitle,
                enableWakeLock: true,
              )
            : null,
      );
    } else {
      locationSettings = AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: enableForeground,
      );
    }

    debugPrint(
      "⚙️ [GPS CONFIG] Stream reiniciado. Perfil: ${profile.name} (Acc: ${accuracy.name}, Int: ${intervalSeconds}s, Filt: ${distanceFilter}m, ForceNativoManager: $_isEmulator)",
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
