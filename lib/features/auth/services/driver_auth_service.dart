import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';
import '../../../core/models/user_model.dart';
import 'package:flutter/foundation.dart';

class DriverAuthService {
  static final DriverAuthService _instance = DriverAuthService._internal();
  factory DriverAuthService() => _instance;
  DriverAuthService._internal();

  final ApiClient _apiClient = ApiClient();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  User? _currentUser;
  User? get currentUser => _currentUser;

  // --- LOGIN ---
  // --- LOGIN ---
  Future<User> login(String email, String password) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      _currentUser = _mockLogin(email, password);
      return _currentUser!;
    }

    try {
      final response = await _apiClient.dio.post(
        '/login',
        data: {
          'email': email,
          'password': password,
          'device_name': 'driver_app_flutter',
        },
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      final user = User.fromMap(response.data['data']['user']);
      await _saveSession(user, response.data['data']['token']);
      return user;
    } on DioException catch (e) {
      if (e.response != null) {
        final responseData = e.response!.data;

        // Si el backend envió un mensaje directo (como hicimos en el paso 1)
        if (responseData != null && responseData['message'] != null) {
          throw Exception(responseData['message']);
        }

        // Fallback para errores de validación de Laravel (Validator)
        if (e.response!.statusCode == 422) {
          final errors = responseData['errors'];
          if (errors != null && errors is Map) {
            final errorMessages = errors.values.expand((x) => x).join('\n');
            throw Exception(errorMessages);
          }
        }

        if (e.response!.statusCode == 500) {
          throw Exception('Error en el servidor. Intente más tarde.');
        }
      }
      throw Exception('No se pudo conectar con el servidor.');
    }
  }

  // --- VALIDAR SESIÓN AL INICIO ---
  Future<UserVerificationStatus?> verifySessionAndGetStatus() async {
    if (_apiClient.isMockOnly) {
      return _currentUser?.verificationStatus ?? UserVerificationStatus.CREATED;
    }

    try {
      final token = await _storage.read(key: 'auth_token');

      if (token == null) {
        return null; // No hay sesión guardada, ir a Login
      }

      // Hacemos la petición a /me para validar si el token sigue vivo y el usuario activo
      final response = await _apiClient.dio.get(
        '/me',
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      if (response.data['data'] != null) {
        _currentUser = User.fromMap(response.data['data']);
        return _currentUser!.verificationStatus;
      }
      return null;
    } on DioException catch (e) {
      // Si el token expiró (401) o el usuario fue desactivado (403), borramos el token local
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await logout();
      }
      return null;
    } catch (e) {
      return null;
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
    required String fvLicencia,
    required File selfieFile,
    required File cedulaFile,
  }) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      _currentUser = _mockRegister(name, email);
      return _currentUser!;
    }

    try {
      String selfieName = selfieFile.path.split('/').last;
      String cedulaName = cedulaFile.path.split('/').last;

      final formData = FormData.fromMap({
        'nombre': name,
        'email': email,
        'telefono': phone,
        'documento': documento,
        'n_licencia': documento, // Enviamos la cédula como número de licencia
        'fv_licencia': fvLicencia,
        'password': password,
        'password_confirmation': passwordConfirmation,
        'role': 3, // Rol Conductor
        'selfie': await MultipartFile.fromFile(
          selfieFile.path,
          filename: selfieName,
        ),
        'cedula_pdf': await MultipartFile.fromFile(
          cedulaFile.path,
          filename: cedulaName,
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
    String? photoUrl,
  }) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      if (_currentUser == null) return false;

      // 1. Convertimos a mapa
      final Map<String, dynamic> userData = _currentUser!.toMap();

      // 2. Inyectamos los cambios
      userData['name'] = name;
      userData['phone'] = phone;
      userData['email'] = email;
      if (photoUrl != null) {
        userData['photo_url'] = photoUrl;
      }

      // 3. Reconstruimos el usuario
      _currentUser = User.fromMap(userData);

      debugPrint("MOCK UPDATE PROFILE: ${_currentUser!.name}");
      return true;
    }

    try {
      // CORRECCIÓN DEL ERROR AQUÍ:
      // Construimos el mapa fuera para evitar el lint "use_null_aware_elements" dentro del literal.
      final Map<String, dynamic> updateData = {
        'name': name,
        'phone': phone,
        'email': email,
      };

      if (photoUrl != null) {
        updateData['photo_url'] = photoUrl;
      }

      final response = await _apiClient.dio.put(
        '/driver/profile',
        data: updateData,
      );

      // Actualizamos el usuario local con la respuesta real del servidor
      if (response.data['user'] != null) {
        _currentUser = User.fromMap(response.data['user']);
        return true;
      }
      return false;
    } on DioException catch (e) {
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
    await _storage.write(key: 'auth_token', value: token);
    _currentUser = user;
  }

  Future<void> logout() async {
    await _storage.delete(key: 'auth_token');
    _currentUser = null;
  }

  // --- MOCKS ---

  User _mockLogin(String email, String password) {
    if (email.contains('ok')) {
      return User(
        id: 'driver-ok',
        email: email,
        name: 'Conductor Verificado',
        phone: '3001',
        role: UserRole.DRIVER,
        verificationStatus: UserVerificationStatus.VERIFIED,
        beneficiaries: [],
        appMode: AppMode.PERSONAL,
      );
    }
    if (email.contains('wait')) {
      return User(
        id: 'driver-wait',
        email: email,
        name: 'Conductor En Espera',
        phone: '3002',
        role: UserRole.DRIVER,
        verificationStatus: UserVerificationStatus.UNDER_REVIEW,
        beneficiaries: [],
        appMode: AppMode.PERSONAL,
      );
    }
    return User(
      id: 'driver-new',
      email: email,
      name: 'Conductor Nuevo',
      phone: '3003',
      role: UserRole.DRIVER,
      verificationStatus: UserVerificationStatus.CREATED,
      beneficiaries: [],
      appMode: AppMode.PERSONAL,
    );
  }

  User _mockRegister(String name, String email) {
    return User(
      id: 'new-driver-${DateTime.now().millisecondsSinceEpoch}',
      email: email,
      name: name,
      phone: '3000',
      role: UserRole.DRIVER,
      verificationStatus: UserVerificationStatus.CREATED,
      beneficiaries: [],
    );
  }
}
