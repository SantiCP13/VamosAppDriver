// lib/features/home/services/trip_service.dart

import 'package:flutter/foundation.dart'; // Para debugPrint
import 'package:latlong2/latlong.dart';
import '../../../core/network/api_client.dart'; // Para 'ApiClient'
import '../../maps/services/route_service.dart';

class TripService {
  final RouteService _routeService;

  // Inyección por constructor
  TripService(this._routeService);

  /// Obtiene la Polyline real entre dos puntos
  Future<List<LatLng>> getRoutePolyline(LatLng start, LatLng end) async {
    try {
      // 1. Llamamos al servicio de rutas (puedes usar el mismo RouteService que creamos para el usuario)
      final result = await _routeService.getRoute(start, end);
      return result.points;
    } catch (e) {
      return [start, end]; // Fallback
    }
  }

  /// 🟢 NUEVO: Envía el PIN ingresado por el conductor al backend para activar el servicio programado
  Future<Map<String, dynamic>?> activarViajeProgramado({
    required String pin,
    required double lat,
    required double lng,
  }) async {
    try {
      // Reutiliza el cliente de red oficial con sus interceptores de token Bearer
      final dio = ApiClient().dio;

      final response = await dio.post(
        '/conductor/viajes/activar-programado',
        data: {'codigo_activacion': pin, 'lat': lat, 'lng': lng},
      );

      if (response.statusCode == 200) {
        return response.data;
      }
    } catch (e) {
      debugPrint("🚨 Error de API al activar viaje programado: $e");
      rethrow;
    }
    return null;
  }
}
