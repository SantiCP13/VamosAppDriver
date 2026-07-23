// lib/features/auth/providers/auth_provider.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/services/storage_service.dart';
import '../../home/providers/home_provider.dart';

class AuthProvider extends ChangeNotifier {
  final DriverAuthService _authService = DriverAuthService();
  AuthProvider() {
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    if (_authService.currentUser != null) return;
    await _authService.verifySessionAndGetStatus();
    notifyListeners();
  }

  User? get user => _authService.currentUser;

  Future<bool> checkAuthStatus() async {
    final storage = sl<StorageService>();

    // 1. ¿Existe un token guardado en el dispositivo?
    final token = await storage.getToken();
    if (token == null || token.isEmpty) return false;

    // 2. Verificación silenciosa:
    try {
      final status = await _authService.verifySessionAndGetStatus();
      if (status != null) {
        notifyListeners();
        return true; // Acceso exitoso (ya sea online o mediante caché)
      } else {
        // Si el estado regresó null, analizamos si el token fue destruido localmente.
        // Esto pasa si el servidor respondió con un 401/403 explícito.
        final tokenAft = await storage.getToken();
        if (tokenAft == null || tokenAft.isEmpty) {
          return false; // El token ya no existe, forzar login.
        }

        // Si el token aún sigue en el storage seguro, significa que no fue invalidado
        // por credenciales erróneas (fue un fallo de red o lectura de caché transitoria).
        // En este caso, por resiliencia de la app de conducción, mantenemos al usuario logueado en Home.
        return true;
      }
    } catch (e) {
      debugPrint("Excepción no controlada al validar sesión: $e");
      // Si hay una excepción imprevista pero el token existe, no lo deslogueamos.
      return true;
    }
  }

  void refreshUser() {
    notifyListeners();
  }

  Future<void> logout() async {
    // 🟢 FALLBACK DE SEGURIDAD: Asegurar que el GPS se detenga físicamente a través de GetIt
    // en caso de cierres de sesión forzados por el servidor o tokens expirados.
    try {
      sl<HomeProvider>().stopTracking();
    } catch (e) {
      debugPrint("Error deteniendo GPS en logout fallback: $e");
    }

    await _authService.logout();
    notifyListeners();
  }

  Future<void> updateProfileData({
    required String name,
    required String phone,
    required String email,
    File? imageFile,
  }) async {
    final success = await _authService.updateUserProfile(
      name: name,
      phone: phone,
      email: email,
      imageFile: imageFile,
    );

    if (success) {
      notifyListeners();
    } else {
      throw Exception("No se pudo actualizar el perfil");
    }
  }

  // 🟢 NUEVO MÉTODO: Delegación del cambio de contraseña
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    return await _authService.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
  }

  // 🟢 NUEVO MÉTODO: Delegación de la eliminación definitiva
  Future<bool> deleteUserAccount() async {
    final success = await _authService.deleteUserAccount();
    if (success) {
      notifyListeners();
    }
    return success;
  }
}
