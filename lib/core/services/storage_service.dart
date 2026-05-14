import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/trip_model.dart';

class StorageService {
  // Llaves de almacenamiento
  static const String _currentTripKey = 'current_trip_data';
  static const String _tokenKey = 'auth_token';
  static const String _biometricEnabledKey = 'use_biometrics';
  static const String _passwordKey = 'auth_password';
  static const String _biometricEmailKey =
      'biometric_user_email'; // <--- NUEVA LLAVE

  // Instancia de almacenamiento encriptado
  final _secureStorage = const FlutterSecureStorage();

  // --- MÉTODOS DE ENROLAMIENTO BIOMÉTRICO (LÓGICA NEQUI) ---

  // Este es el método que te marcaba error en la línea 129 del login
  Future<void> saveBiometricEmail(String email) async {
    await _secureStorage.write(key: _biometricEmailKey, value: email);
  }

  // Este es el método que te marcaba error en la línea 91 del login
  Future<String?> getBiometricEmail() async {
    return await _secureStorage.read(key: _biometricEmailKey);
  }

  static const String _deviceIdKey = 'unique_device_id';

  Future<void> saveDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, id);
  }

  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceIdKey);
  }

  // --- MANEJO DE CONTRASEÑA ---
  Future<void> savePassword(String password) async {
    await _secureStorage.write(key: _passwordKey, value: password);
  }

  Future<String?> getPassword() async {
    return await _secureStorage.read(key: _passwordKey);
  }

  // --- MANEJO DEL TOKEN ---
  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  // --- CONFIGURACIÓN DE BIOMETRÍA ---
  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, enabled);
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  // --- LIMPIEZA TOTAL ---
  // Modifica este método en StorageService
  Future<void> deleteAll() async {
    // 1. Borramos el token (la sesión activa)
    await _secureStorage.delete(key: _tokenKey);

    // 2. NO BORRAMOS ni la contraseña ni el email biométrico.
    // Esto es lo que permite que la huella siga apareciendo después de cerrar sesión.

    // 3. Mantenemos el estado de "biometría habilitada" en true
    // para que el dispositivo siga siendo considerado "Seguro".
  }

  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  // --- DATOS DE VIAJE ---
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
