import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final DriverAuthService _authService = DriverAuthService();

  // Getter para obtener el usuario actual desde el servicio
  User? get user => _authService.currentUser;

  /// NUEVO MÉTODO: Verifica si el token es válido al arrancar la app
  /// Esto es lo que el main.dart necesita para no dar error.
  Future<bool> checkAuthStatus() async {
    // Llamamos al método que ya creaste en el servicio
    final status = await _authService.verifySessionAndGetStatus();

    // Si el status no es nulo, significa que el token es válido y el usuario existe
    if (status != null) {
      notifyListeners();
      return true;
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
