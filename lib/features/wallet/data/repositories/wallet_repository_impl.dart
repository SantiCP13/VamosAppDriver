import '../../../../core/models/transaction_model.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../../../../core/network/api_client.dart';
import 'package:flutter/foundation.dart';

class ApiWalletRepository implements WalletRepository {
  final ApiClient _apiClient = ApiClient();

  @override
  Future<double> getBalance() async {
    try {
      final response = await _apiClient.dio.get('/billetera/historial');

      // Seguridad: Verificamos si la respuesta tiene 'saldo_actual'
      final dynamic saldo = response.data['saldo_actual'];

      return (saldo != null) ? double.tryParse(saldo.toString()) ?? 0.0 : 0.0;
    } catch (e) {
      debugPrint("❌ Error en getBalance: $e");
      return 0.0;
    }
  }

  @override
  Future<List<TransactionModel>> getHistory() async {
    try {
      final response = await _apiClient.dio.get('/billetera/historial');

      // Seguridad: Laravel usa 'historial' -> 'data' al usar paginate().
      // Si la respuesta no trae 'historial', retornamos lista vacía.
      final dynamic historial = response.data['historial'];

      if (historial == null || historial['data'] == null) {
        return [];
      }

      final List rawData = historial['data'] as List;

      return rawData
          .map((item) {
            // Blindaje extra: Intentamos convertir cada item
            try {
              return TransactionModel.fromMap(item);
            } catch (e) {
              debugPrint("⚠️ Error mapeando transacción individual: $e");
              return null; // Omitimos este item corrupto
            }
          })
          .whereType<TransactionModel>() // Filtramos los nulos
          .toList();
    } catch (e) {
      debugPrint("❌ Error obteniendo historial: $e");
      return [];
    }
  }
}
