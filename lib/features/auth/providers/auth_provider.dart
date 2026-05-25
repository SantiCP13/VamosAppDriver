// auth_provider.dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/services/storage_service.dart';

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

    // 2. Verificación silenciosa (resiliente a fallos de conexión):
    try {
      final status = await _authService.verifySessionAndGetStatus();
      if (status != null) {
        notifyListeners();
        return true; // Acceso directo al Home de forma estable
      }
    } catch (e) {
      debugPrint("Fallo al validar estado silencioso de sesión: $e");
    }

    return false;
  }

  void refreshUser() {
    notifyListeners();
  }

  Future<void> logout() async {
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
}
