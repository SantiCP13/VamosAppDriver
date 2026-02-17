import 'dart:async';
// Importamos ÚNICAMENTE del core
import '../../../core/models/transaction_model.dart';

class WalletService {
  Future<double> getBalance() async {
    await Future.delayed(const Duration(seconds: 1));
    return 150000.00;
  }

  Future<List<TransactionModel>> getHistory() async {
    await Future.delayed(const Duration(seconds: 1));

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
        title: 'Recarga de Saldo',
        description: 'PSE - Bancolombia',
        amount: 50000,
        date: DateTime.now().subtract(const Duration(days: 1)),
        isCredit: true,
        type: TransactionType.ADJUSTMENT,
      ),
    ];
  }
}
