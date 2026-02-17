import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_model.dart';

class StorageService {
  static const String _currentTripKey = 'current_trip_data';

  // Guardar viaje
  Future<void> saveCurrentTrip(Trip trip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentTripKey, trip.toJson());
  }

  // Recuperar viaje (si existe)
  Future<Trip?> getCurrentTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tripJson = prefs.getString(_currentTripKey);
    if (tripJson == null) return null;
    try {
      return Trip.fromJson(tripJson);
    } catch (e) {
      return null;
    }
  }

  // Borrar viaje (al finalizar)
  Future<void> clearCurrentTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentTripKey);
  }
}
