import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
//import 'package:shared_preferences/shared_preferences.dart'; // <--- Faltaba este

// IMPORTANTE: Asegúrate de que estas rutas sean las correctas en tu carpeta lib
import '../../../core/network/api_client.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/storage_service.dart'; // <--- Faltaba este
import '../../../core/di/injection_container.dart';

class DriverAuthService {
  static final DriverAuthService _instance = DriverAuthService._internal();
  factory DriverAuthService() => _instance;
  DriverAuthService._internal();

  final ApiClient _apiClient = ApiClient();

  User? _currentUser;
  User? get currentUser => _currentUser;

  // Ubicación: lib/features/auth/services/driver_auth_service.dart

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
          'device_name': deviceName, // Nombre real del cel (ej: Samsung S21)
          'device_id': deviceId,
          'app_type': 'DRIVER', // <--- ENVÍA ESTO AL BACKEND
        },
      );

      final userData = response.data['data']['user'];
      final String token = response.data['data']['token'];

      // 1. VALIDACIÓN DE ROL (DEBE SER 3)
      // En tu backend Laravel el id_role suele venir como 'role_id' o en el objeto 'role'
      // Buscamos en 'id_role' (como está en tu DB) o en 'role_id' por si Laravel lo renombra
      final int roleId =
          int.tryParse(
            (userData['id_role'] ?? userData['role_id'])?.toString() ?? '0',
          ) ??
          0;
      if (roleId != 3) {
        throw Exception('Esta cuenta no está registrada como Conductor.');
      }

      // 2. VALIDACIÓN DE CUENTA ACTIVA
      final bool isActive =
          userData['active'] == 1 || userData['active'] == true;
      if (!isActive && userData['status'] == 'VERIFIED') {
        throw Exception('Tu cuenta ha sido desactivada. Contacta a soporte.');
      }

      final user = User.fromMap(userData);

      // 3. GUARDADO SEGURO
      await _saveSession(user, token);

      return user;
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final data = e.response!.data;

        // --- SEGURIDAD PROACTIVA ---
        // Si el servidor rechaza las credenciales (422) o la cuenta (403/401)
        // significa que lo que tenemos guardado en el celular YA NO SIRVE.
        if (e.response!.statusCode == 422 ||
            e.response!.statusCode == 403 ||
            e.response!.statusCode == 401) {
          await sl<StorageService>()
              .deleteAll(); // Borramos huella y clave local de inmediato
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

  // --- VALIDAR SESIÓN AL INICIO ---
  Future<UserVerificationStatus?> verifySessionAndGetStatus() async {
    try {
      final storage = sl<StorageService>();
      final token = await storage.getToken();

      // SI NO HAY TOKEN, NO INTENTES IR AL SERVIDOR
      if (token == null || token.isEmpty) {
        return null;
      }

      final response = await _apiClient.dio.get('/me');

      if (response.data['data'] != null) {
        _currentUser = User.fromMap(response.data['data']);
        return _currentUser!.verificationStatus;
      }
      return null;
    } catch (e) {
      // Si el servidor da error (como el 401), devolvemos null
      // El ApiClient ya se encargará de limpiar el token
      return null;
    }
  }

  // --- NUEVO: VERIFICAR SI EL EMAIL EXISTE Y ES CONDUCTOR ---
  // --- ACTUALIZADO: Recibe email y deviceId ---
  Future<Map<String, dynamic>> checkAccount(
    String email,
    String deviceId,
  ) async {
    try {
      final response = await _apiClient.dio.post(
        '/check-account',
        data: {
          'email': email,
          'device_id': deviceId, // <--- Enviamos el ID al backend
        },
      );

      return response.data['data'];
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final data = e.response!.data;
        String msg = data is Map
            ? (data['message'] ?? 'Error de validación')
            : 'Error';
        throw Exception(msg);
      }
      throw Exception('Verifica tu conexión a internet.');
    }
  }

  // --- REGISTER (TODO EN UNO) ---
  Future<User> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String passwordConfirmation,
    required String documento,
    required String tipoDocumento, // <--- AGREGA ESTA LÍNEA

    required String fvLicencia,
    required File selfieFile,
    required File cedulaFile,
    required File licenciaFile, // <--- NUEVO
  }) async {
    await _apiClient.simulateDelay();

    try {
      String selfieName = selfieFile.path.split('/').last;
      String cedulaName = cedulaFile.path.split('/').last;
      String licenciaName = licenciaFile.path
          .split('/')
          .last; // <--- AGREGA ESTA LÍNEA

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
        'role': 3,
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
          filename: licenciaName, // <--- AHORA YA NO DARÁ ERROR
        ),
      });

      final response = await _apiClient.dio.post(
        '/register', // CORRECCIÓN: Antes era '/driver/register'
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      _currentUser = User.fromMap(response.data['data']['user']);
      return _currentUser!;
    } on DioException catch (e) {
      if (e.response != null) {
        if (e.response!.statusCode == 422) {
          final errors = e.response!.data['errors'] as Map<String, dynamic>;
          final errorMessages = errors.values.expand((x) => x).join('\n');
          throw Exception(errorMessages);
        } else if (e.response!.statusCode == 500) {
          throw Exception('Error Servidor/SQL: ${e.response!.data['message']}');
        }
      }
      throw Exception(e.message ?? 'Error en registro');
    }
  } // --- PERFIL DE USUARIO ---
  // --- RECUPERACIÓN DE CONTRASEÑA REAL ---

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
      debugPrint("MOCK UPLOAD PROFILE IMAGE: $path");
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
    File? imageFile, // Cambiamos photoUrl (String) por imageFile (File)
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
      // USAMOS FormData PARA ENVIAR ARCHIVOS (IGUAL QUE EN LA APP DE USUARIOS)
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

      // CAMBIO CLAVE: POST a /me/update (la ruta que sí existe en api.php)
      final response = await _apiClient.dio.post('/me/update', data: formData);

      // Sincronizamos con el formato de respuesta de tu backend
      if (response.data['success'] == true ||
          response.data['status'] == 'success') {
        // Actualizamos el usuario local con lo que devuelve el server
        if (response.data['user'] != null) {
          _currentUser = User.fromMap(response.data['user']);
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

  // --- MÉTODOS DE DOCUMENTOS ---

  Future<void> uploadDocument(String docType, File file) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      debugPrint("MOCK UPLOAD DOC: $docType - ${file.path}");
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
    return _currentUser!;
  }

  // --- HELPERS ---
  Future<void> _saveSession(User user, String token) async {
    // USAMOS StorageService para que el token se guarde donde el Socket lo busca
    await sl<StorageService>().saveToken(token);
    _currentUser = user;
  }

  Future<void> logout() async {
    try {
      // 1. Limpiamos la caja fuerte (Token, Pass y Biometría)
      await sl<StorageService>().deleteAll();

      // 2. Limpiamos datos temporales de SharedPreferences
      await sl<StorageService>().clearCurrentTrip();

      // 3. Limpiamos el usuario en memoria
      _currentUser = null;

      debugPrint("Sesión destruida completamente");
    } catch (e) {
      debugPrint("Error al cerrar sesión: $e");
    }
  }

  // --- MOCKS ---
}
