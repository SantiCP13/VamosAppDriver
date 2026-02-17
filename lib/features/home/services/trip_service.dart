import 'dart:async';
import 'package:latlong2/latlong.dart';

class TripService {
  // Solo lógica de cálculo de rutas (Google Directions / OSRM)
  // La lógica de negocio (aceptar, rechazar, escuchar) se movió al Repository.

  Future<List<LatLng>> getRoutePolyline(LatLng start, LatLng end) async {
    // Simula latencia de red para calcular ruta
    await Future.delayed(const Duration(milliseconds: 300));

    // Retornamos 3 puntos para simular una línea curva
    // En producción esto conecta con Google Routes API o OSRM
    return [
      start,
      LatLng(
        (start.latitude + end.latitude) / 2,
        (start.longitude + end.longitude) / 2 + 0.001,
      ),
      end,
    ];
  }
}
