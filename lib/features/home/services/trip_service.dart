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
      // Llamamos al servicio real de OSRM (o Google)
      final result = await _routeService.getRoute(start, end);
      return result.points;
    } catch (e) {
      // Fallback simple en caso de error extremo: Línea recta
      return [start, end];
    }
  }
}
