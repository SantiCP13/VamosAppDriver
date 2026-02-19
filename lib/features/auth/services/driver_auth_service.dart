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
  Future<User> login(String email, String password) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      _currentUser = _mockLogin(email, password);
      return _currentUser!;
    }

    try {
      final response = await _apiClient.dio.post(
        '/driver/login',
        data: {
          'email': email,
          'password': password,
          'device_name': 'driver_app_flutter',
        },
      );
      final user = User.fromMap(response.data['user']);
      await _saveSession(user, response.data['token']);
      return user;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Error al iniciar sesión');
    }
  }

  // --- REGISTER ---
  Future<User> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      _currentUser = _mockRegister(name, email);
      return _currentUser!;
    }

    try {
      final response = await _apiClient.dio.post(
        '/driver/register',
        data: {
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
          'role': 'DRIVER',
        },
      );
      final user = User.fromMap(response.data['user']);
      await _saveSession(user, response.data['token']);
      return user;
    } on DioException catch (e) {
      throw Exception(e.response?.data['message'] ?? 'Error en registro');
    }
  }

  // --- PERFIL DE USUARIO ---

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

  Future<UserVerificationStatus> checkStatus() async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      return _currentUser?.verificationStatus ?? UserVerificationStatus.CREATED;
    }

    try {
      final response = await _apiClient.dio.get('/driver/status');
      if (response.data['user'] != null) {
        _currentUser = User.fromMap(response.data['user']);
      }
      return _currentUser!.verificationStatus;
    } catch (e) {
      return _currentUser?.verificationStatus ?? UserVerificationStatus.CREATED;
    }
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
