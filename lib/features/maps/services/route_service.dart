import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteService {
  // URL pública de OSRM
  final String _baseUrl = 'https://router.project-osrm.org/route/v1/driving';

  // Instancia para cálculos geométricos locales (Plan B)
  final Distance _distanceCalculator = const Distance();

  Future<RouteResult> getRoute(LatLng start, LatLng end) async {
    // 1. Intentar obtener la ruta real
    try {
      final String coordinates =
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';

      final Uri url = Uri.parse(
        '$_baseUrl/$coordinates?steps=true&overview=full&geometries=geojson',
      );

      // Agregamos un TIMEOUT de 3.5 segundos.
      // Si OSRM está lento, mejor pasamos al fallback rápido.
      final response = await http
          .get(url)
          .timeout(
            const Duration(milliseconds: 3500),
            onTimeout: () {
              throw Exception('Timeout esperando a OSRM');
            },
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] == null || (data['routes'] as List).isEmpty) {
          throw Exception('Ruta vacía devuelta por API');
        }

        final route = data['routes'][0];

        // Mapeo exitoso
        final geometry = route['geometry'];
        final List<dynamic> coordinatesList = geometry['coordinates'];

        final List<LatLng> points = coordinatesList.map((coord) {
          return LatLng(
            (coord[1] as num).toDouble(),
            (coord[0] as num).toDouble(),
          );
        }).toList();

        return RouteResult(
          points: points,
          distanceMeters: (route['distance'] as num).toDouble(),
          durationSeconds: (route['duration'] as num).toDouble(),
          isFallback: false, // Indicamos que es una ruta real
        );
      } else {
        throw Exception('Error API: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint(
        "⚠️ OSRM falló o tardó demasiado ($e). Usando Fallback Línea Recta.",
      );
      // 2. Si algo falla, ejecutamos el Plan B (Fallback)
      return _calculateFallbackRoute(start, end);
    }
  }

  /// PLAN B: Calcula una línea recta si el servidor de mapas falla.
  RouteResult _calculateFallbackRoute(LatLng start, LatLng end) {
    // Calcular distancia en metros usando latlong2
    final double distMeters = _distanceCalculator.as(
      LengthUnit.Meter,
      start,
      end,
    );

    // Estimación básica: Asumimos una velocidad promedio de 30km/h (8.33 m/s) en ciudad
    // para dar un tiempo estimado "creíble".
    final double durationEstSeconds = distMeters / 8.33;

    return RouteResult(
      points: [start, end], // Solo dos puntos: Inicio y Fin (Línea recta)
      distanceMeters: distMeters,
      durationSeconds: durationEstSeconds,
      isFallback: true, // Útil si la UI quiere mostrar una advertencia
    );
  }
}

// DTO Actualizado
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool isFallback; // Nuevo campo para saber si es ruta real o simulada

  RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.isFallback = false,
  });
}
