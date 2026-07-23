// lib/features/auth/services/driver_auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// IMPORTANTE: Rutas de importación del núcleo de tu aplicación
import '../../../core/network/api_client.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/di/injection_container.dart';

class DriverAuthService {
  static final DriverAuthService _instance = DriverAuthService._internal();
  factory DriverAuthService() => _instance;
  DriverAuthService._internal();

  final ApiClient _apiClient = ApiClient();

  User? _currentUser;
  User? get currentUser => _currentUser;

  Future<User> login(
    String email,
    String password,
    String deviceId,
    String deviceName,
  ) async {
    try {
      final response = await _apiClient.dio.post(
        '/login',
        data: {
          'email': email,
          'password': password,
          'device_name': deviceName,
          'device_id': deviceId,
          'app_type': 'DRIVER',
        },
      );

      final userData = response.data['data']['user'];
      final String token = response.data['data']['token'];

      final int roleId =
          int.tryParse(
            (userData['id_role'] ?? userData['role_id'])?.toString() ?? '0',
          ) ??
          0;

      if (roleId != 6) {
        throw Exception('Esta cuenta no está registrada como Conductor.');
      }

      final bool isActive =
          userData['active'] == 1 || userData['active'] == true;
      if (!isActive && userData['status'] == 'VERIFIED') {
        throw Exception('Tu cuenta ha sido desactivada. Contacta a soporte.');
      }

      final user = User.fromMap(userData);
      await _saveSession(user, token);

      return user;
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final data = e.response!.data;

        // 🟢 NUEVO: Cálculo dinámico del tiempo de espera para el conductor
        // Reemplaza la sección del error 429 dentro de tu catch en login por:
        if (e.response!.statusCode == 429) {
          final retryAfterHeader = e.response?.headers.value('retry-after');
          final int secondsToWait = int.tryParse(retryAfterHeader ?? '') ?? 60;

          String timeMessage = "$secondsToWait segundos";
          if (secondsToWait >= 60) {
            final int minutes = (secondsToWait / 60).ceil();
            timeMessage = "$minutes ${minutes == 1 ? 'minuto' : 'minutos'}";
          }

          throw Exception(
            "Muchos intentos fallidos. Tu acceso estará bloqueado por $timeMessage hasta poder intentarlo de nuevo.",
          );
        }

        if (e.response!.statusCode == 422 ||
            e.response!.statusCode == 403 ||
            e.response!.statusCode == 401) {
          await sl<StorageService>().deleteAll();
          await const FlutterSecureStorage().delete(key: 'cached_driver');
          debugPrint("Credenciales locales invalidadas por el servidor.");
        }

        String serverMessage = data is Map && data.containsKey('message')
            ? data['message']
            : 'Error de acceso.';
        throw Exception(serverMessage);
      }
      debugPrint("❌ ERROR DE CONEXIÓN: ${e.type}");
      throw Exception('Sin conexión con VAMOS. Verifica tu internet.');
    }
  }

  Future<UserVerificationStatus?> verifySessionAndGetStatus() async {
    try {
      final storage = sl<StorageService>();
      final token = await storage.getToken();

      if (token == null || token.isEmpty) {
        return null;
      }

      final response = await _apiClient.dio.get('/me');

      if (response.data['data'] != null) {
        _currentUser = User.fromMap(response.data['data']);

        await const FlutterSecureStorage().write(
          key: 'cached_driver',
          value: jsonEncode(response.data['data']),
        );

        return _currentUser!.verificationStatus;
      }
      return null;
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
          debugPrint("Sesión invalidada por el servidor (401/403).");
          return null;
        }
      }

      debugPrint(
        "Fallo de red al validar sesión. Intentando recuperar caché local del conductor.",
      );
      try {
        final cachedDriverStr = await const FlutterSecureStorage().read(
          key: 'cached_driver',
        );
        if (cachedDriverStr != null) {
          final Map<String, dynamic> userData = jsonDecode(cachedDriverStr);
          _currentUser = User.fromMap(userData);
          return _currentUser!.verificationStatus;
        }
      } catch (err) {
        debugPrint("Error cargando caché local: $err");
      }

      return null;
    }
  }

  Future<Map<String, dynamic>> checkAccount(
    String email,
    String deviceId,
  ) async {
    try {
      final response = await _apiClient.dio.post(
        '/check-account',
        data: {'email': email, 'device_id': deviceId},
      );

      return response.data['data'];
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final data = e.response!.data;

        // 🟢 NUEVO: Control defensivo de Rate Limiting (Error 429) en español
        if (e.response!.statusCode == 429) {
          throw Exception(
            'Demasiados intentos de acceso. Por favor, inténtalo más tarde.',
          );
        }

        String msg = data is Map
            ? (data['message'] ?? 'Error de validación')
            : 'Error';
        throw Exception(msg);
      }
      throw Exception('Verifica tu conexión a internet.');
    }
  }

  Future<User> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String passwordConfirmation,
    required String documento,
    required String tipoDocumento,
    required String fvLicencia,
    required File selfieFile,
    required File cedulaFile,
    required File licenciaFile,
  }) async {
    await _apiClient.simulateDelay();

    try {
      String selfieName = selfieFile.path.split('/').last;
      String cedulaName = cedulaFile.path.split('/').last;
      String licenciaName = licenciaFile.path.split('/').last;

      final formData = FormData.fromMap({
        'nombre': name,
        'email': email,
        'telefono': phone,
        'documento': documento,
        'tipo_documento': tipoDocumento,
        'n_licencia': documento,
        'fv_licencia': fvLicencia,
        'password': password,
        'password_confirmation': passwordConfirmation,
        'role': 6,
        'selfie': await MultipartFile.fromFile(
          selfieFile.path,
          filename: selfieName,
        ),
        'cedula_pdf': await MultipartFile.fromFile(
          cedulaFile.path,
          filename: cedulaName,
        ),
        'licencia_pdf': await MultipartFile.fromFile(
          licenciaFile.path,
          filename: licenciaName,
        ),
      });

      final response = await _apiClient.dio.post(
        '/register',
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      final userData = response.data['data']['user'];
      _currentUser = User.fromMap(userData);

      await const FlutterSecureStorage().write(
        key: 'cached_driver',
        value: jsonEncode(userData),
      );

      return _currentUser!;
    } on DioException catch (e) {
      if (e.response != null) {
        if (e.response!.statusCode == 422) {
          final data = e.response!.data;

          if (data is Map &&
              data.containsKey('errors') &&
              data['errors'] is Map) {
            final errors = data['errors'] as Map<String, dynamic>;
            final errorMessages = errors.values.expand((x) => x).join('\n');
            throw Exception(errorMessages);
          } else if (data is Map && data.containsKey('message')) {
            throw Exception(data['message']);
          }
          throw Exception('Datos de validación incorrectos.');
        } else if (e.response!.statusCode == 500) {
          throw Exception('Error Servidor/SQL: ${e.response!.data['message']}');
        }
      }
      throw Exception(e.message ?? 'Error en registro');
    }
  }

  Future<void> sendPasswordResetCode(String email) async {
    try {
      await _apiClient.dio.post('/password/email', data: {'email': email});
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Error al enviar código');
    }
  }

  Future<void> verifyPasswordResetCode(String email, String code) async {
    try {
      await _apiClient.dio.post(
        '/password/code/check',
        data: {'email': email, 'code': code},
      );
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Código inválido');
    }
  }

  Future<void> resetPassword(String email, String code, String password) async {
    try {
      await _apiClient.dio.post(
        '/password/reset',
        data: {
          'email': email,
          'code': code,
          'password': password,
          'password_confirmation': password,
        },
      );
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['message'] ?? 'Error al restablecer contraseña',
      );
    }
  }

  Future<String?> uploadProfileImage(String path) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      return "https://i.pravatar.cc/300?u=${DateTime.now().millisecondsSinceEpoch}";
    }

    try {
      String fileName = path.split('/').last;
      FormData formData = FormData.fromMap({
        "image": await MultipartFile.fromFile(path, filename: fileName),
      });

      final response = await _apiClient.dio.post(
        '/driver/profile/image',
        data: formData,
      );

      return response.data['photo_url'];
    } on DioException catch (e) {
      throw Exception('Error subiendo imagen: ${e.message}');
    }
  }

  Future<bool> updateUserProfile({
    required String name,
    required String phone,
    required String email,
    File? imageFile,
  }) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      if (_currentUser == null) return false;
      final Map<String, dynamic> userData = _currentUser!.toMap();
      userData['name'] = name;
      userData['phone'] = phone;
      userData['email'] = email;
      _currentUser = User.fromMap(userData);
      return true;
    }

    try {
      FormData formData = FormData.fromMap({
        'name': name,
        'phone': phone,
        'email': email,
        if (imageFile != null)
          'photo': await MultipartFile.fromFile(
            imageFile.path,
            filename: 'profile_driver.jpg',
          ),
      });

      final response = await _apiClient.dio.post('/me/update', data: formData);

      if (response.data['success'] == true ||
          response.data['status'] == 'success') {
        if (response.data['user'] != null) {
          _currentUser = User.fromMap(response.data['user']);

          await const FlutterSecureStorage().write(
            key: 'cached_driver',
            value: jsonEncode(response.data['user']),
          );
        }
        return true;
      }
      return false;
    } on DioException catch (e) {
      debugPrint("Error en DriverAuthService: ${e.response?.data}");
      throw Exception(
        e.response?.data['message'] ?? 'Error actualizando perfil',
      );
    }
  }

  // 🟢 NUEVO MÉTODO: Petición para actualizar contraseña de conductor
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      return {
        'success': true,
        'message': 'Contraseña actualizada correctamente (Simulado).',
      };
    }

    try {
      final response = await _apiClient.dio.post(
        '/me/change-password',
        data: {
          'current_password': currentPassword,
          'password': newPassword,
          'password_confirmation': confirmPassword,
        },
      );

      if (response.data['success'] == true ||
          response.data['status'] == 'success') {
        return {
          'success': true,
          'message':
              response.data['message'] ??
              'Contraseña actualizada correctamente.',
        };
      }
      return {
        'success': false,
        'message':
            response.data['message'] ?? 'No se pudo actualizar la contraseña.',
      };
    } on DioException catch (e) {
      debugPrint("Error actualizando contraseña: ${e.response?.data}");
      String msg = 'Error al actualizar contraseña';
      if (e.response?.data is Map) {
        msg = e.response?.data['message'] ?? msg;
      }
      return {'success': false, 'message': msg};
    }
  }

  // 🟢 NUEVO MÉTODO: Petición para eliminar definitivamente la cuenta
  Future<bool> deleteUserAccount() async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      await logout();
      return true;
    }

    try {
      final response = await _apiClient.dio.post('/me/delete');

      if (response.data['success'] == true ||
          response.data['status'] == 'success') {
        await logout();
        return true;
      }
      return false;
    } on DioException catch (e) {
      debugPrint("Error eliminando cuenta (me/delete): ${e.response?.data}");

      // Fallback defensivo usando verbo DELETE
      try {
        final response = await _apiClient.dio.delete('/me');
        if (response.data['success'] == true ||
            response.data['status'] == 'success') {
          await logout();
          return true;
        }
      } catch (e2) {
        debugPrint("Error fallback DELETE /me: $e2");
      }
      throw Exception(
        e.response?.data['message'] ?? 'Error al eliminar la cuenta',
      );
    }
  }

  Future<void> uploadDocument(String docType, File file) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      return;
    }

    try {
      String fileName = file.path.split('/').last;

      FormData formData = FormData.fromMap({
        "document_type": docType,
        "file": await MultipartFile.fromFile(file.path, filename: fileName),
      });

      await _apiClient.dio.post('/driver/documents/upload', data: formData);
    } on DioException catch (e) {
      throw Exception('Error subiendo $docType: ${e.message}');
    }
  }

  Future<User> submitDocumentsForReview() async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      if (_currentUser != null) {
        final data = _currentUser!.toMap();
        data['status'] = 'UNDER_REVIEW';
        _currentUser = User.fromMap(data);
      }
      return _currentUser!;
    }

    final response = await _apiClient.dio.post('/driver/submit-review');
    _currentUser = User.fromMap(response.data['user']);

    await const FlutterSecureStorage().write(
      key: 'cached_driver',
      value: jsonEncode(response.data['user']),
    );

    return _currentUser!;
  }

  Future<void> _saveSession(User user, String token) async {
    await sl<StorageService>().saveToken(token);
    _currentUser = user;

    try {
      await const FlutterSecureStorage().write(
        key: 'cached_driver',
        value: jsonEncode(user.toMap()),
      );
    } catch (e) {
      debugPrint("Error guardando sesión de conductor en caché: $e");
    }
  }

  Future<void> logout() async {
    try {
      await sl<StorageService>().deleteAll();
      await sl<StorageService>().clearCurrentTrip();
      await const FlutterSecureStorage().delete(key: 'cached_driver');
      _currentUser = null;
      debugPrint("Sesión destruida completamente");
    } catch (e) {
      debugPrint("Error al cerrar sesión: $e");
    }
  }
}
