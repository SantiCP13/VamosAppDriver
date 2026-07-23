import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// --- NUEVOS IMPORTS REQUERIDOS ---
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vamos_driver/core/di/injection_container.dart';
import 'package:vamos_driver/core/services/storage_service.dart';

class RouteService {
  // Instancia para cálculos geométricos locales (Plan B)
  final Distance _distanceCalculator = const Distance();

  Future<RouteResult> getRoute(
    LatLng start,
    LatLng end, {
    List<Map<String, dynamic>>? paradas, // Parámetro opcional
  }) async {
    try {
      final storage = sl<StorageService>();
      final token = await storage.getToken();

      final baseUrl =
          dotenv.env['API_BASE_URL'] ?? 'https://api.vamosapp.com.co/api';
      final Uri url = Uri.parse('$baseUrl/maps/calcular-ruta');

      // 🟢 Construimos el cuerpo del payload de manera limpia y fuera del inline
      final Map<String, dynamic> bodyPayload = {
        'lat_origen': start.latitude,
        'lng_origen': start.longitude,
        'lat_destino': end.latitude,
        'lng_destino': end.longitude,
      };

      // Si vienen paradas, las inyectamos de forma segura
      if (paradas != null) {
        bodyPayload['paradas'] = paradas;
      }

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: json.encode(
              bodyPayload,
            ), // 🟢 Enviamos el payload estructurado
          )
          .timeout(const Duration(milliseconds: 10000));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['coordinates'] == null ||
            (data['coordinates'] as List).isEmpty) {
          throw Exception('Ruta vacía devuelta por el servidor');
        }

        final List<dynamic> coordinatesList = data['coordinates'];

        final List<LatLng> points = coordinatesList.map((coord) {
          return LatLng(
            (coord[1] as num).toDouble(),
            (coord[0] as num).toDouble(),
          );
        }).toList();

        return RouteResult(
          points: points,
          distanceMeters:
              ((data['distancia_km'] ?? 0.0) as num).toDouble() * 1000,
          durationSeconds:
              ((data['tiempo_minutos'] ?? 0.0) as num).toDouble() * 60,
          isFallback: false,
          // 🟢 MAPEO DE PEAJES DESDE LA API LOCAL
          totalTolls: ((data['total_peajes'] ?? 0.0) as num).toDouble(),
          tollsDetails: data['peajes_detalles'] ?? [],
        );
      } else {
        throw Exception(
          'Servidor respondió con código: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint("El servidor de rutas falló o tardó demasiado ($e).");

      final errString = e.toString().toLowerCase();

      // 🟢 Si es una caída genuina de internet (Modo Avión), propagamos el error al Provider
      // para que active el estado desconectado y NO dibuje líneas rectas erróneas.
      if (errString.contains('socketexception') ||
          errString.contains('failed host lookup') ||
          errString.contains('connection failed') ||
          errString.contains('network_error')) {
        rethrow;
      }

      // Si es un error menor del servidor (ej. un 500 temporal), aplica la contingencia
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
// DTO Actualizado
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final bool isFallback;
  // 🟢 NUEVOS CAMPOS PEAJES
  final double totalTolls;
  final List<dynamic> tollsDetails;

  RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.isFallback = false,
    this.totalTolls = 0.0, // 🟢 NUEVO
    this.tollsDetails = const [], // 🟢 NUEVO
  });
}
