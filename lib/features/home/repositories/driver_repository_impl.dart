import 'dart:async';
import 'package:dio/dio.dart';
import '../../../core/models/document_model.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../core/network/api_client.dart';
import 'driver_repository.dart';

// --- MOCK ---
class MockDriverRepository implements DriverRepository {
  @override
  Future<List<DriverDocument>> getDocuments(String driverId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      DriverDocument(
        id: '1',
        name: 'SOAT',
        expirationDate: DateTime.now().add(const Duration(days: 300)),
        status: 'VIGENTE',
      ),
      DriverDocument(
        id: '2',
        name: 'Licencia de Conducción',
        expirationDate: DateTime.now().add(const Duration(days: 15)),
        status: 'VIGENTE',
      ),
    ];
  }

  @override
  Future<List<Vehicle>> getAssignedVehicles(String driverId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    // Retornamos la lista estática del modelo para probar
    return Vehicle.getMocks();
  }

  @override
  Future<bool> toggleStatus({
    required bool isOnline,
    required String driverId,
    String? vehicleId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1000));

    if (!isOnline) return true; // Desconectar siempre es gratis

    // VALIDACIÓN DE NEGOCIO CRÍTICA
    if (vehicleId == null) {
      throw Exception("Debes seleccionar un vehículo para operar legalmente.");
    }

    // Simulamos validación de documentos
    final docs = await getDocuments(driverId);
    if (docs.any((d) => !d.isValid)) {
      throw Exception("Documentación vencida. No se puede generar FUEC.");
    }

    return true;
  }
}

// --- REAL (LARAVEL) ---
class ApiDriverRepository implements DriverRepository {
  final ApiClient _apiClient = ApiClient();

  @override
  Future<List<DriverDocument>> getDocuments(String driverId) async {
    final response = await _apiClient.dio.get('/drivers/$driverId/documents');
    return (response.data['data'] as List)
        .map((e) => DriverDocument.fromJson(e))
        .toList();
  }

  @override
  Future<List<Vehicle>> getAssignedVehicles(String driverId) async {
    // Endpoint sugerido: GET /api/drivers/{id}/vehicles
    final response = await _apiClient.dio.get('/drivers/$driverId/vehicles');
    return (response.data['data'] as List)
        .map((e) => Vehicle.fromJson(e))
        .toList();
  }

  @override
  Future<bool> toggleStatus({
    required bool isOnline,
    required String driverId,
    String? vehicleId,
  }) async {
    try {
      // Enviamos el vehicle_id al backend para que asocie la sesión
      await _apiClient.dio.patch(
        '/drivers/$driverId/status',
        data: {
          'online': isOnline,
          'vehicle_id':
              vehicleId, // Laravel validará si este vehículo tiene tarjeta de operación vigente
        },
      );
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 || e.response?.statusCode == 422) {
        final data = e.response?.data;

        // 1. Intentar leer el arreglo de "errors" de Laravel (ej. errors: { soat: })
        if (data is Map && data.containsKey('errors')) {
          final Map errors = data;
          if (errors.isNotEmpty) {
            final firstError = errors.values.first;
            final errorMessage = firstError is List
                ? firstError.first
                : firstError.toString();
            throw Exception(errorMessage);
          }
        }

        // 2. Si no hay "errors", intentar leer un "message" directo, o poner el texto por defecto
        final String msg = (data is Map && data.containsKey('message'))
            ? data
                  .toString() // <--- AQUÍ ESTÁ LA CORRECCIÓN
            : "Error de validación legal (FUEC).";

        throw Exception(msg);
      }

      throw Exception("Error de conexión: ${e.message}");
    }
  }
}
