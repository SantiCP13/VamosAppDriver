import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/services/storage_service.dart';

class AuthProvider extends ChangeNotifier {
  final DriverAuthService _authService = DriverAuthService();
  AuthProvider() {
    // Intentamos cargar el usuario al arrancar la app
    _initializeUser();
  }

  // Nuevo método interno
  Future<void> _initializeUser() async {
    // Si ya existe en la memoria del servicio, no hacemos nada
    if (_authService.currentUser != null) return;

    // Esto asegura que el servicio tenga el usuario cargado lo antes posible
    await _authService.verifySessionAndGetStatus();
    notifyListeners();
  }

  // Getter para obtener el usuario actual desde el servicio
  User? get user => _authService.currentUser;

  Future<bool> checkAuthStatus() async {
    final storage = sl<StorageService>();

    // 1. ¿Existe un token guardado en la caja fuerte?
    final token = await storage.getToken();
    if (token == null || token.isEmpty) return false;

    // 2. Verificación silenciosa:
    // Intentamos validar el token con el servidor sin pedir huella ni PIN.
    try {
      final status = await _authService.verifySessionAndGetStatus();
      if (status != null) {
        notifyListeners();
        return true; // El token es válido, entra directo al Home.
      }
    } catch (e) {
      debugPrint("Sesión expirada o error de red: $e");
    }

    // 3. Si el token no es válido o hubo error, enviamos al Welcome
    return false;
  }

  void refreshUser() {
    notifyListeners();
  }

  Future<void> logout() async {
    await _authService.logout();
    notifyListeners();
  }

  // MÉTODO PARA ACTUALIZAR PERFIL
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
}
