import 'package:flutter/material.dart';
import '../../../core/models/transaction_model.dart';
import '../domain/repositories/wallet_repository.dart';
import '../../../core/models/trip_model.dart';

class WalletProvider extends ChangeNotifier {
  final WalletRepository repository;

  WalletProvider({required this.repository});

  double _balance = 0.0;
  List<TransactionModel> _transactions = [];
  bool _isLoading = false;

  double get balance => _balance;
  List<TransactionModel> get transactions => _transactions;
  bool get isLoading => _isLoading;

  // Tu lógica original de filtrado local se mantiene
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

  Future<void> loadWalletData({bool force = false}) async {
    if (_isLoading) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Traemos saldo e historial en paralelo
      final results = await Future.wait([
        repository.getBalance(),
        repository.getHistory(),
      ]);

      _balance = results[0] as double;
      _transactions = results[1] as List<TransactionModel>;

      debugPrint(
        "💰 Billetera actualizada: $_balance con ${_transactions.length} movimientos",
      );
    } catch (e) {
      debugPrint("❌ Error cargando billetera: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void registerCompletedTrip(Trip completedTrip) {
    loadWalletData();
  }
}
