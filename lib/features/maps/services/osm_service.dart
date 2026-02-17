import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class OsmService {
  Future<List<Map<String, dynamic>>> searchPlaces(
    String query, {
    LatLng? userLocation,
  }) async {
    if (query.length < 3) return [];

    // Base URL
    String urlString =
        'https://photon.komoot.io/api/?q=$query&limit=10&lang=es';

    if (userLocation != null) {
      urlString +=
          '&lat=${userLocation.latitude}&lon=${userLocation.longitude}';
    }

    final url = Uri.parse(urlString);

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;

        return features.map((feature) {
          final props = feature['properties'];
          final coords = feature['geometry']['coordinates'];

          String name = props['name'] ?? props['street'] ?? "Ubicación";
          String details = "";

          List<String> parts = [];

          // CORRECCIÓN 1: Agregadas las llaves {} a los condicionales
          if (props['housenumber'] != null) {
            parts.add("#${props['housenumber']}");
          }
          if (props['city'] != null) {
            parts.add(props['city']);
          }
          if (props['state'] != null) {
            parts.add(props['state']);
          }

          // Si el nombre es igual a la calle, intentamos no repetir info
          if (name == props['street']) {
            details = parts.join(", ");
          } else {
            if (props['street'] != null) parts.insert(0, props['street']);
            details = parts.join(", ");
          }

          return {
            "name": name,
            "address": details,
            "lat": coords[1].toDouble(),
            "lng": coords[0].toDouble(),
          };
        }).toList();
      }
    } catch (e) {
      // CORRECCIÓN 2: Uso de debugPrint en lugar de print
      debugPrint("Error buscando en OSM: $e");
    }
    return [];
  }

  // 2. OBTENER DIRECCIÓN DESDE EL MAPA (Coordenadas -> Texto)
  // Usa la API de Nominatim
  Future<String> getAddressFromCoordinates(LatLng point) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=18&addressdetails=1',
    );

    try {
      // User-Agent es OBLIGATORIO para que no te bloqueen
      final response = await http.get(
        url,
        headers: {'User-Agent': 'VamosApp_Dev/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'];

        // Construimos una dirección legible
        String road = address['road'] ?? "";
        String house = address['house_number'] ?? "";
        String city =
            address['city'] ?? address['town'] ?? address['village'] ?? "";

        String result = "$road $house";
        if (city.isNotEmpty) result += ", $city";

        return result.trim().isEmpty ? "Ubicación en mapa" : result;
      }
    } catch (e) {
      // CORRECCIÓN 3: Uso de debugPrint en lugar de print
      debugPrint("Error Reverse Geocoding: $e");
    }
    return "Ubicación seleccionada";
  }
}
