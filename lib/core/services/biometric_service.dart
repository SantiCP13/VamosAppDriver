import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;

class BiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  // 1. Verificar si el hardware está disponible y el usuario tiene huellas/rostro registrados
  Future<bool> isAvailable() async {
    try {
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate =
          canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (e) {
      developer.log("Error verificando disponibilidad biométrica: $e");
      return false;
    }
  }

  // 2. Ejecutar la autenticación
  Future<bool> authenticate() async {
    try {
      // 1. Verificamos si el dispositivo tiene algún método de seguridad (PIN o Bio)
      bool canAuthenticate =
          await _auth.isDeviceSupported() || await _auth.canCheckBiometrics;

      if (!canAuthenticate) {
        developer.log("El dispositivo no tiene PIN ni Biometría configurada.");
        return false;
      }

      return await _auth.authenticate(
        localizedReason: 'Usa tu PIN, Huella o Rostro para ingresar a VAMOS',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // <--- CAMBIO CLAVE: Permite usar PIN/Patrón
          useErrorDialogs: true, // Muestra diálogos del sistema si algo falla
        ),
      );
    } on PlatformException catch (e) {
      developer.log("Error en autenticación: ${e.code}");
      return false;
    }
  }
}
