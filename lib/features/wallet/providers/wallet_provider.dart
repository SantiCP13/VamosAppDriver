import 'package:flutter/material.dart';
// Importamos ÚNICAMENTE del core
import '../../../core/models/transaction_model.dart';
import '../services/wallet_service.dart';

class WalletProvider extends ChangeNotifier {
  final WalletService _service = WalletService();

  double _balance = 0.0;
  List<TransactionModel> _transactions = [];
  bool _isLoading = false;

  double get balance => _balance;
  List<TransactionModel> get transactions => _transactions;
  bool get isLoading => _isLoading;

  /// Calcula las ganancias de hoy (Getter calculado)
  double get todayEarnings {
    final now = DateTime.now();
    return _transactions
        .where(
          (t) =>
              t.isCredit &&
              t.date.year == now.year &&
              t.date.month == now.month &&
              t.date.day == now.day,
        )
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  Future<void> loadWalletData() async {
    _isLoading = true;
    notifyListeners();

    try {
      _balance = await _service.getBalance();
      _transactions = await _service.getHistory();
    } catch (e) {
      debugPrint("Error cargando wallet: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- LÓGICA DE PAGOS ---
  void processTripPayment(
    double totalPrice,
    String tripId,
    String destination,
  ) {
    const double platformFeePercent = 0.15;
    final double platformFee = totalPrice * platformFeePercent;
    final double driverNetIncome = totalPrice - platformFee;

    final incomeTx = TransactionModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      ledgerId: "ledger_${DateTime.now().microsecondsSinceEpoch}",
      title: "Pago Viaje Finalizado",
      description: "Destino: $destination",
      date: DateTime.now(),
      amount: totalPrice,
      isCredit: true,
      type: TransactionType.TRIP_PAYMENT,
      referenceId: tripId,
    );

    _balance += driverNetIncome;

    final displayTx = TransactionModel(
      id: incomeTx.id,
      ledgerId: incomeTx.ledgerId,
      title: "Ganancia Viaje",
      description: "Destino: $destination (Desc. 15% Fee)",
      date: DateTime.now(),
      amount: driverNetIncome,
      isCredit: true,
      type: TransactionType.TRIP_PAYMENT,
      referenceId: tripId,
    );

    _transactions.insert(0, displayTx);
    notifyListeners();
  }
}
