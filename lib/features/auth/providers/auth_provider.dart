import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final DriverAuthService _authService = DriverAuthService();

  User? get user => _authService.currentUser;

  void refreshUser() {
    notifyListeners();
  }

  // Wrapper para logout que notifica a la UI
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
    String? photoUrl;

    // 1. Subir imagen si existe
    if (imageFile != null) {
      photoUrl = await _authService.uploadProfileImage(imageFile.path);
    }

    // 2. Actualizar datos
    final success = await _authService.updateUserProfile(
      name: name,
      phone: phone,
      email: email,
      photoUrl: photoUrl,
    );

    if (success) {
      // 3. Forzar actualización local del usuario (MOCK o REAL)
      // Esto es crucial para que la UI se refresque sola
      // En una app real, harías un fetchUser() de nuevo, o actualizarías el objeto localmente:
      if (_authService.currentUser != null) {
        // NOTA: Como User es final, en teoría deberías hacer un fetch nuevo
        // O usar copyWith si lo tienes implementado.
        // Por simplicidad, simulamos refresco:
        notifyListeners();
      }
    } else {
      throw Exception("No se pudo actualizar el perfil");
    }
  }
}
