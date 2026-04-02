import '../../../../core/models/transaction_model.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../../../../core/network/api_client.dart';
import 'package:flutter/foundation.dart';

class MockWalletRepository implements WalletRepository {
  @override
  Future<double> getBalance() async => 0.0;
  @override
  Future<List<TransactionModel>> getHistory() async => [];
}

class ApiWalletRepository implements WalletRepository {
  final ApiClient _apiClient = ApiClient();

  @override
  Future<double> getBalance() async {
    try {
      // Usamos el endpoint de historial que ya devuelve el saldo_actual
      final response = await _apiClient.dio.get('/billetera/historial');

      // Según tu BilleteraController: 'saldo_actual' => $billetera->saldo
      final saldo = response.data['saldo_actual'];

      debugPrint("💰 Saldo recibido del server: $saldo");
      return double.tryParse(saldo.toString()) ?? 0.0;
    } catch (e) {
      debugPrint("❌ Error en getBalance: $e");
      return 0.0;
    }
  }

  @override
  Future<List<TransactionModel>> getHistory() async {
    try {
      final response = await _apiClient.dio.get('/billetera/historial');

      // IMPORTANTE: Laravel Paginate envuelve los items en ['historial']['data']
      // Según tu controlador: return response()->json(['historial' => $movimientos, ...])
      final List rawData = response.data['historial']['data'] ?? [];

      return rawData.map((item) => TransactionModel.fromMap(item)).toList();
    } catch (e) {
      debugPrint("❌ Error obteniendo historial: $e");
      return [];
    }
  }
}
