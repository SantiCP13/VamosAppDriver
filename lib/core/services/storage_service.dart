// lib/core/services/storage_service.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart'; // Para debugPrint
import '../models/trip_model.dart';
import 'package:package_info_plus/package_info_plus.dart';

class StorageService {
  // Llaves de almacenamiento persistente
  static const String _currentTripKey = 'current_trip_data';
  static const String _tokenKey = 'auth_token';
  static const String _deviceIdKey = 'unique_device_id';
  static const String _biometricEmailKey = 'biometric_user_email';

  // LLAVES AUXILIARES DE GPS
  static const String _lastDriverLatKey = 'last_known_driver_lat';
  static const String _lastDriverLngKey = 'last_known_driver_lng';

  // 🟢 SIN la palabra 'const' al inicio
  final _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  // --- PERSISTENCIA LOCAL DE GPS ---
  Future<void> saveLastPosition(double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_lastDriverLatKey, lat);
      await prefs.setDouble(_lastDriverLngKey, lng);
    } catch (e) {
      debugPrint("Error al escribir posición en caché local: $e");
    }
  }

  Future<Map<String, double>?> getLastPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final double? lat = prefs.getDouble(_lastDriverLatKey);
      final double? lng = prefs.getDouble(_lastDriverLngKey);
      if (lat != null && lng != null) {
        return {'lat': lat, 'lng': lng};
      }
    } catch (e) {
      debugPrint("Error al leer posición de caché local: $e");
    }
    return null;
  }

  // --- BIOMETRÍA Y SEGURIDAD INDEXADA POR CUENTA ---

  // Guarda la contraseña indexada por correo electrónico
  Future<void> saveAccountPassword(String email, String password) async {
    final key = 'bio_pass_${email.toLowerCase().trim()}';
    await _secureStorage.write(key: key, value: password);
  }

  // Recupera la contraseña de un correo específico
  Future<String?> getAccountPassword(String email) async {
    final key = 'bio_pass_${email.toLowerCase().trim()}';
    return await _secureStorage.read(key: key);
  }

  // Elimina la contraseña de un correo específico
  Future<void> deleteAccountPassword(String email) async {
    final key = 'bio_pass_${email.toLowerCase().trim()}';
    await _secureStorage.delete(key: key);
  }

  // Habilita la biometría por cuenta específica
  Future<void> setBiometricEnabledForAccount(String email, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'bio_enabled_${email.toLowerCase().trim()}';
    await prefs.setBool(key, enabled);
  }

  // Consulta si la biometría está habilitada para una cuenta específica
  Future<bool> isBiometricEnabledForAccount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'bio_enabled_${email.toLowerCase().trim()}';
    return prefs.getBool(key) ?? false;
  }

  // --- MÉTODOS GENERALES ---
  Future<void> saveBiometricEmail(String email) async {
    await _secureStorage.write(key: _biometricEmailKey, value: email);
  }

  Future<String?> getBiometricEmail() async {
    return await _secureStorage.read(key: _biometricEmailKey);
  }

  Future<void> saveDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceIdKey, id);
  }

  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceIdKey);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: _tokenKey);
  }

  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<void> deleteToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  // 🟢 CORREGIDO: Limpieza masiva de colas de viajes y ubicaciones locales al cerrar sesión
  Future<void> deleteAll() async {
    // 🟢 CORREGIDO: Solo eliminamos el token de la sesión activa
    // para preservar las credenciales indexadas y estados biométricos locales de otras cuentas.
    await _secureStorage.delete(key: _tokenKey);
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

  // --- LIMPIEZA CONTRA CONFLICTOS DE ACTUALIZACIÓN ---
  // --- LIMPIEZA CONTRA CONFLICTOS DE ACTUALIZACIÓN ---
  Future<void> checkAndClearCacheOnUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // package_info_plus lee la versión nativa del pubspec
      final packageInfo = await PackageInfo.fromPlatform();

      final int currentVersion = int.tryParse(packageInfo.buildNumber) ?? 0;
      final int savedVersion = prefs.getInt('app_version_code') ?? 0;

      if (currentVersion > savedVersion) {
        // 🟢 LIMPIEZA ABSOLUTA: Borra todo el SecureStorage de raíz (tokens, contraseñas biométricas, emails)
        await _secureStorage.deleteAll();

        // 🟢 LIMPIEZA ABSOLUTA: Limpia por completo SharedPreferences (datos de viaje, estados biométricos)
        await prefs.clear();

        // Guardamos la versión actual para no volver a limpiar en futuros inicios normales
        // (Se hace después de prefs.clear() para que no se pierda el registro de control)
        await prefs.setInt('app_version_code', currentVersion);

        debugPrint(
          "🧹 CACHÉ Y VIAJE ACTIVO LIMPIADOS POR ACTUALIZACIÓN A LA VERSIÓN $currentVersion",
        );
      }
    } catch (e) {
      debugPrint("Error verificando versión en StorageService: $e");
    }
  }
}
