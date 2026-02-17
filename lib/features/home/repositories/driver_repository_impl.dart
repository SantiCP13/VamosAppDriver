import 'dart:async';
import 'package:dio/dio.dart';
import '../../../core/models/document_model.dart';
import '../../../core/network/api_client.dart';
import 'driver_repository.dart';

// --- MOCK (Para desarrollo y pruebas de bloqueo) ---
class MockDriverRepository implements DriverRepository {
  @override
  Future<List<DriverDocument>> getDocuments(String driverId) async {
    await Future.delayed(const Duration(seconds: 1)); // Simula red

    // CAMBIA ESTAS FECHAS PARA PROBAR EL BLOQUEO:
    // Si pones 'days: -1', el documento estará vencido.
    return [
      DriverDocument(
        id: '1',
        name: 'SOAT',
        expirationDate: DateTime.now().add(const Duration(days: 300)),
        status: 'VIGENTE',
      ),
      DriverDocument(
        id: '2',
        name: 'Tecnomecánica',
        expirationDate: DateTime.now().add(const Duration(days: 15)),
        status: 'VIGENTE',
      ),
    ];
  }

  @override
  Future<bool> toggleStatus({
    required bool isOnline,
    required String driverId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    // Si quiere desconectarse, siempre puede hacerlo.
    if (!isOnline) return true;

    // Si quiere conectarse (ONLINE), validamos reglas de negocio:
    final docs = await getDocuments(driverId);

    // Regla: Ningún documento puede estar vencido o rechazado
    final hasInvalidDocs = docs.any((doc) => !doc.isValid);

    if (hasInvalidDocs) {
      // Buscamos cuál falló para dar un mensaje claro
      final badDoc = docs.firstWhere((doc) => !doc.isValid);
      throw Exception(
        "No puedes operar. Tu ${badDoc.name} está vencido o pendiente.",
      );
    }

    return true; // Todo en orden, pase
  }
}

// --- REAL (Conexión Laravel) ---
class ApiDriverRepository implements DriverRepository {
  final ApiClient _apiClient = ApiClient();

  @override
  Future<List<DriverDocument>> getDocuments(String driverId) async {
    try {
      final response = await _apiClient.dio.get('/drivers/$driverId/documents');
      return (response.data['data'] as List)
          .map((e) => DriverDocument.fromJson(e))
          .toList();
    } catch (e) {
      throw Exception("Error obteniendo documentos: $e");
    }
  }

  @override
  Future<bool> toggleStatus({
    required bool isOnline,
    required String driverId,
  }) async {
    try {
      // El Backend (Laravel) ejecutará middleware de validación
      await _apiClient.dio.patch(
        '/drivers/$driverId/status',
        data: {'online': isOnline},
      );
      return true;
    } on DioException catch (e) {
      // Manejo de error específico del Backend (403 Forbidden)
      if (e.response?.statusCode == 403) {
        // Ejemplo de respuesta Laravel: { "message": "Tu SOAT ha vencido." }
        final msg = e.response?.data['message'] ?? "Requisitos incumplidos.";
        throw Exception(msg);
      }
      throw Exception("Error de conexión con el servidor.");
    }
  }
}
