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
  // 🟢 MODIFICADO: Suma de ganancias netas reales de hoy (Efectivo y Corporativos)
  double get todayEarnings {
    final now = DateTime.now();
    return _transactions
        .where((t) {
          return t.date.year == now.year &&
              t.date.month == now.month &&
              t.date.day == now.day;
        })
        .fold(0.0, (sum, t) {
          // 1. Si es un viaje, sumamos su ganancia neta (independiente de si fue cobro de comisión o depósito)
          if (t.originAddress != null) {
            return sum + (t.netEarnings ?? 0.0);
          }
          // 2. Si es una recarga directa o ajuste positivo de saldo de la app
          if (t.isCredit) {
            return sum + t.amount;
          }
          return sum;
        });
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
