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
        onError: (DioException e, handler) async {
          developer.log('❌ ERROR: ${e.requestOptions.path}', name: 'API_DEBUG');

          // OBTENEMOS EL PATH COMPLETO PARA ASEGURAR QUE NO HAYA CONFUSIONES
          final path = e.requestOptions.path;

          // Blindaje mejorado: usamos una lista para ser más ordenados
          final protectedPaths = [
            '/responder',
            '/cancelar',
            '/iniciar',
            '/viajes/',
            '/asignaciones/', // <--- AGREGADO: Es fundamental para el rechazo
          ];

          // Si el path contiene alguno de los protegidos, NO hagas logout
          if (protectedPaths.any((p) => path.contains(p))) {
            return handler.next(e);
          }

          // Solo hacer logout si es un 401 real y NO es una ruta protegida
          if (e.response?.statusCode == 401) {
            await sl<StorageService>().deleteAll();
            NavigationService.navigatorKey.currentState
                ?.pushNamedAndRemoveUntil('/', (route) => false);
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
