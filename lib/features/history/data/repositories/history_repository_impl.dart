import '../../../../core/models/trip_model.dart';
import '../../domain/repositories/history_repository.dart';
import '../../../../core/network/api_client.dart';
import 'package:flutter/foundation.dart';

class HistoryRepositoryImpl implements HistoryRepository {
  final ApiClient _apiClient = ApiClient();

  @override
  Future<List<Trip>> getTripHistory() async {
    try {
      final response = await _apiClient.dio.get('/conductor/viajes');

      // DIFERENCIA CON USUARIOS:
      // Usuarios: response.data['data']['data'] (porque es paginado)
      // Conductores: response.data['data'] (porque es un get() directo)

      if (response.data['status'] == 'success') {
        final List rawData = response.data['data'] ?? [];
        return rawData.map((item) => Trip.fromMap(item)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("❌ Error en repositorio historial: $e");
      return [];
    }
  }
}
