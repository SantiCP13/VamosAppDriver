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

  // NUEVO: Bandera para saber si ya cargamos los datos iniciales
  bool _dataLoaded = false;

  double get balance => _balance;
  List<TransactionModel> get transactions => _transactions;
  bool get isLoading => _isLoading;

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
    // CORRECCIÓN CRÍTICA:
    // Si ya cargamos datos y tenemos transacciones en memoria, NO recargar del Mock.
    // Esto evita que se borre el dinero que acabamos de ganar en el viaje.
    if (_dataLoaded) return;

    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        repository.getBalance(),
        repository.getHistory(),
      ]);

      _balance = results[0] as double;
      _transactions = results[1] as List<TransactionModel>;
      _dataLoaded = true; // Marcamos como cargado
    } catch (e) {
      debugPrint("Error loading wallet: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void registerCompletedTrip(Trip completedTrip) {
    if (completedTrip.driverRevenue <= 0) {
      debugPrint("⚠️ Advertencia: Viaje finalizado con ganancia 0 o nula.");
    }

    // 1. En lugar de sumar mágicamente, forzamos la sincronización con Laravel
    _dataLoaded = false;

    // 2. Descargamos el saldo real del Ledger
    loadWalletData();

    // Nota: Aunque loadWalletData recarga la lista desde el server,
    // puedes dejar el SnackBar de la UI tranquilo, ya que ahora
    // dependemos de la verdad absoluta del Backend.
  }
}
