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
    required String plate,
  }) async {
    await _apiClient.simulateDelay();

    if (_apiClient.isMockOnly) {
      _currentUser = _mockRegister(name, email, plate);
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
          'vehicle_plate': plate,
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

  // --- MÉTODOS DE PERFIL (SOLUCIONA ERRORES EN PROFILE SCREEN) ---

  Future<bool> updateUserProfile({
    required String name,
    required String phone,
    required String email,
    String? photoUrl,
  }) async {
    await _apiClient.simulateDelay();
    // Lógica Mock o Real para actualizar
    if (_currentUser != null) {
      // En un caso real, harías PUT /user/profile
      return true;
    }
    return false;
  }

  Future<String?> uploadProfileImage(String path) async {
    await _apiClient.simulateDelay();
    // Simula subida y retorno de URL
    return "https://i.pravatar.cc/300?u=updated_${DateTime.now().millisecondsSinceEpoch}";
  }

  // --- MÉTODOS DE DOCUMENTOS ---

  Future<void> uploadDocument(String docType, File file) async {
    await _apiClient.simulateDelay();

    // MOCK: Si es solo mock, retornamos éxito inmediatamente.
    // ESTO ES CLAVE: Evita que intente leer el archivo "fantasma" del emulador
    if (_apiClient.isMockOnly) {
      debugPrint("MOCK UPLOAD: $docType - ${file.path}");
      return;
    }

    // LÓGICA REAL (Para Laravel)
    try {
      String fileName = file.path.split('/').last;

      FormData formData = FormData.fromMap({
        "document_type": docType,
        // Dio detecta automáticamente si es PDF o JPG
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
        _currentUser!.verificationStatus = UserVerificationStatus.UNDER_REVIEW;
      }
      return _currentUser!;
    }
    // Lógica real...
    return _currentUser!;
  }

  Future<UserVerificationStatus> checkStatus() async {
    await _apiClient.simulateDelay();
    if (_apiClient.isMockOnly) {
      if (_currentUser?.verificationStatus ==
          UserVerificationStatus.UNDER_REVIEW) {
        _currentUser!.verificationStatus = UserVerificationStatus.VERIFIED;
      }
      return _currentUser!.verificationStatus;
    }
    // Lógica real...
    return _currentUser!.verificationStatus;
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
        name: 'Juan Verificado',
        phone: '3001',
        role: UserRole.NATURAL,
        verificationStatus: UserVerificationStatus.VERIFIED,
        beneficiaries: [],
        appMode: AppMode.PERSONAL,
      );
    }
    if (email.contains('wait')) {
      return User(
        id: 'driver-wait',
        email: email,
        name: 'Pedro Esperando',
        phone: '3002',
        role: UserRole.NATURAL,
        verificationStatus: UserVerificationStatus.UNDER_REVIEW,
        beneficiaries: [],
        appMode: AppMode.PERSONAL,
      );
    }
    return User(
      id: 'driver-new',
      email: email,
      name: 'Carlos Nuevo',
      phone: '3003',
      role: UserRole.NATURAL,
      verificationStatus: UserVerificationStatus.CREATED,
      beneficiaries: [],
      appMode: AppMode.PERSONAL,
    );
  }

  User _mockRegister(String name, String email, String plate) {
    return User(
      id: 'new-driver-000',
      email: email,
      name: name,
      phone: '3000',
      role: UserRole.NATURAL,
      verificationStatus: UserVerificationStatus.CREATED,
      beneficiaries: [],
    );
  }
}
