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

  Future<void> logout() async {
    await _authService.logout();
    notifyListeners();
  }

  // MÉTODO SIMPLIFICADO Y SINCRONIZADO
  Future<void> updateProfileData({
    required String name,
    required String phone,
    required String email,
    File? imageFile,
  }) async {
    // Llamamos directamente al servicio enviando el archivo
    final success = await _authService.updateUserProfile(
      name: name,
      phone: phone,
      email: email,
      imageFile: imageFile,
    );

    if (success) {
      notifyListeners(); // Esto hará que el Side Menu y el Profile se refresquen
    } else {
      throw Exception("No se pudo actualizar el perfil");
    }
  }
}
