import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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

    // 2. Verificar permisos
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      await openAppSettings();
      return false;
    }

    return true;
  }

  /// CORRECCIÓN CRÍTICA:
  /// Obtiene la posición actual con Timeout y Fallback.
  /// Esto evita el ANR (App Not Responding).
  Future<Position?> getCurrentLocation() async {
    try {
      // 1. Intentar obtener la última ubicación conocida (es instantáneo)
      // Esto ayuda a que el mapa cargue rápido aunque sea con un dato de hace 1 minuto.
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return lastKnown;
      }

      // 2. Si no hay última conocida, pedir la actual pero con TIMEOUT
      // Si en 5 segundos no responde, lanza excepción y no congela la app.
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      // Si falla o hay timeout, retornamos null y dejamos que el Stream se encargue luego
      return null;
    }
  }

  Stream<Position> getPositionStream() {
    // Ajuste de settings para Android
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }
}
