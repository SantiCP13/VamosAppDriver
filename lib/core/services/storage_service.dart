import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_model.dart';

class StorageService {
  static const String _currentTripKey = 'current_trip_data';
  static const String _tokenKey = 'auth_token';

  // --- CORRECCIÓN DEFINITIVA: Sin usar '_storage' ---
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> saveCurrentTrip(Trip trip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentTripKey, trip.toJson());
  }

  Future<Trip?> getCurrentTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tripJson = prefs.getString(_currentTripKey);
    if (tripJson == null) return null;
    return Trip.fromJson(tripJson);
  }

  Future<void> clearCurrentTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentTripKey);
  }
}
