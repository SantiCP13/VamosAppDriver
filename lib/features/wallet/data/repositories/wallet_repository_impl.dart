import '../../../../core/models/transaction_model.dart';
import '../../domain/repositories/wallet_repository.dart';

// --- IMPLEMENTACIÓN MOCK ---
class MockWalletRepository implements WalletRepository {
  @override
  Future<double> getBalance() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return 150000.00; // Saldo simulado
  }

  @override
  Future<List<TransactionModel>> getHistory() async {
    await Future.delayed(const Duration(milliseconds: 800));
    return [
      TransactionModel(
        id: '1',
        ledgerId: 'lg_100',
        title: 'Ganancia Viaje',
        description: 'Aeropuerto -> Centro',
        amount: 28000,
        date: DateTime.now().subtract(const Duration(hours: 2)),
        isCredit: true,
        type: TransactionType.TRIP_PAYMENT,
        referenceId: 'trip_888',
      ),
      TransactionModel(
        id: '2',
        ledgerId: 'lg_99',
        title: 'Recarga Saldo',
        description: 'PSE - Bancolombia',
        amount: 50000,
        date: DateTime.now().subtract(const Duration(days: 1)),
        isCredit: true,
        type: TransactionType.ADJUSTMENT,
      ),
    ];
  }
}

// --- IMPLEMENTACIÓN API (Real) ---
class ApiWalletRepository implements WalletRepository {
  // final Dio _dio; // Inyectar Dio aquí si fuera necesario
  // ApiWalletRepository(this._dio);

  @override
  Future<double> getBalance() async {
    // try { final res = await _dio.get('/wallet/balance'); return res.data['balance']; } ...
    throw UnimplementedError("API no conectada aún");
  }

  @override
  Future<List<TransactionModel>> getHistory() async {
    throw UnimplementedError("API no conectada aún");
  }
}
