import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer'
    as developer; // Usaremos developer.log para logs más profesionales
import '../../main.dart'; // Para usar el navigatorKey
import '../di/injection_container.dart'; // Para usar sl
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/welcome_screen.dart';
import 'package:flutter/material.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late Dio _dio;
  final _storage = const FlutterSecureStorage();

  // --- CONFIGURACIÓN DE ENTORNO ---
  String get envType => dotenv.env['ENV_TYPE'] ?? 'MOCK';

  // Helpers booleanos para lógica limpia en Servicios
  bool get isMockOnly => envType == 'MOCK';
  bool get shouldAttemptRealConnection =>
      envType == 'HYBRID' || envType == 'PROD';

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: dotenv.env['API_URL'] ?? 'http://10.0.2.2:8000/api',
        // Tiempos de espera ajustados para redes móviles (3G/4G en Colombia)
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(
          seconds: 10,
        ), // Importante para subida de datos
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Log de salida para depuración visual
          developer.log(
            '🚀 [${options.method}] ${options.path}',
            name: 'API_REQ',
          );

          final token = await _storage.read(key: 'auth_token');
          if (token != null) {
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

          final String path = e.requestOptions.path.toLowerCase();
          // Detección mejorada: si es login o el error es de validación (422), NO EXPULSAR
          final bool isLoginRequest =
              path.endsWith('/login') || path.contains('login');
          final bool isValidationError = e.response?.statusCode == 422;

          if (isLoginRequest || isValidationError) {
            return handler.next(e); // Pasa el error directamente a la pantalla
          }

          // Solo expulsar si NO es login y es 401/403
          if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
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

  /// Método auxiliar para simular latencia de red realista en modo MOCK o Fallback.
  /// Ayuda a probar loaders y estados de carga en la UI.
  Future<void> simulateDelay([int milliseconds = 1500]) async {
    if (isMockOnly || envType == 'HYBRID') {
      await Future.delayed(Duration(milliseconds: milliseconds));
    }
  }
}
