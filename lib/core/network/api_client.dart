import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer' as developer;
import '../../main.dart';
import '../di/injection_container.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import '../services/storage_service.dart'; // <--- IMPORTANTE

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late Dio _dio;
  // Borramos la variable _storage de aquí

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'http://10.0.2.2:8000/api',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          developer.log(
            '🚀 [${options.method}] ${options.path}',
            name: 'API_REQ',
          );

          // 🔥 CORRECCIÓN CRÍTICA: Leemos desde el StorageService (SharedPreferences)
          final storage = sl<StorageService>();
          final token = await storage.getToken();

          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          developer.log(
            '✅ [${response.statusCode}] ${response.requestOptions.path}',
            name: 'API_RES',
          );
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          developer.log(
            '❌ ERROR EN: ${e.requestOptions.path} | STATUS: ${e.response?.statusCode}',
            name: 'API_DEBUG',
          );

          if (e.response?.statusCode == 401) {
            // Si falla el token, cerramos sesión
            sl<AuthProvider>().logout();
            if (navigatorKey.currentState != null) {
              navigatorKey.currentState!.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            }
          }
          return handler.next(e);
        },
      ),
    );
  }

  Dio get dio => _dio;

  String get envType => dotenv.env['ENV_TYPE'] ?? 'MOCK';
  bool get isMockOnly => envType == 'MOCK';

  Future<void> simulateDelay([int milliseconds = 1500]) async {
    if (isMockOnly || envType == 'HYBRID') {
      await Future.delayed(Duration(milliseconds: milliseconds));
    }
  }
}
