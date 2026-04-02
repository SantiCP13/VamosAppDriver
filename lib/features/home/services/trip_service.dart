import 'package:latlong2/latlong.dart';
// Importa el RouteService y su DTO
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
}
