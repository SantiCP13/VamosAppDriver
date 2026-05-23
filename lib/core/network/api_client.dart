import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer' as developer;

// Imports necesarios para la lógica
import '../di/injection_container.dart';
import '../services/storage_service.dart';
import '../navigation/navigation_service.dart'; // <--- ESTE TE FALTABA

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late Dio _dio;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: dotenv.env['API_URL'] ?? 'https://api.vamosapp.com.co/api',
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final storage = sl<StorageService>();
          final token = await storage.getToken();

          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            // --- MODIFICACIÓN AQUÍ ---
            // Definimos las rutas públicas (las que no requieren token)
            final publicPaths = [
              '/login',
              '/register',
              '/check-account',
              '/password/email', // <--- AGREGADO
              '/password/code/check', // <--- AGREGADO
              '/password/reset', // <--- AGREGADO
            ];

            if (!publicPaths.contains(options.path)) {
              return handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'No hay token disponible',
                  type: DioExceptionType.cancel,
                ),
              );
            }
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
        // En lib/core/network/api_client.dart
        onError: (DioException e, handler) async {
          final statusCode = e.response?.statusCode;
          final path = e.requestOptions.path;

          developer.log(
            '❌ ERROR: $path | STATUS: $statusCode',
            name: 'API_DEBUG',
          );

          // 1. RUTAS INTOCABLES: Bajo ninguna circunstancia cerramos sesión.
          final whiteList = [
            '/responder',
            '/asignaciones',
            '/login',
            '/register',
            '/tracking',
            '/iniciar',
            '/finalizar',
            '/viaje-activo', // <--- IMPORTANTE: Agregamos esto
            '/viajes/activo', // <--- IMPORTANTE: Agregamos esto
          ];

          if (whiteList.any((p) => path.contains(p))) {
            return handler.next(e);
          }

          // 2. LOGOUT SOLO SI ES UNA PETICIÓN DE "ME" (Perfil) Y ES 401
          // Si falla el perfil, es que el token realmente murió.
          if (statusCode == 401 && path.contains('/me')) {
            final storage = sl<StorageService>();
            final token = await storage.getToken();

            if (token != null) {
              developer.log(
                "⚠️ Token inválido en /me. Cerrando sesión...",
                name: 'API_DEBUG',
              );
              await storage.deleteAll();
              NavigationService.navigatorKey.currentState
                  ?.pushNamedAndRemoveUntil('/', (route) => false);
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
