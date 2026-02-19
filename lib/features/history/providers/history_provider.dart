import 'package:flutter/material.dart';
import '../../../core/models/transaction_model.dart';
import '../../../core/models/trip_model.dart';
import '../domain/repositories/history_repository.dart';

class HistoryProvider extends ChangeNotifier {
  final HistoryRepository repository;

  HistoryProvider({required this.repository});

  List<TransactionModel> _history = [];
  bool _isLoading = false;
  bool _dataLoaded = false;

  List<TransactionModel> get history => _history;
  bool get isLoading => _isLoading;

  // Agregamos forceRefresh para permitir el "Pull to Refresh"
  Future<void> loadHistory({bool forceRefresh = false}) async {
    if (_dataLoaded && !forceRefresh) return;

    _isLoading = true;
    notifyListeners();

    try {
      _history = await repository.getTripHistory();
      _dataLoaded = true;
    } catch (e) {
      debugPrint("Error historial: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addFinishedTrip(Trip trip) {
    final newHistoryItem = TransactionModel(
      id: trip.id,
      ledgerId: "trip_${trip.id}",
      title: "Viaje Finalizado",
      description: "Destino: ${trip.destinationAddress}",
      date: DateTime.now(),
      amount: trip.price,
      isCredit: true,
      type: TransactionType.TRIP_PAYMENT,
      referenceId: trip.id,
    );

    _history.insert(0, newHistoryItem);
    _dataLoaded = true;
    notifyListeners();
  }
}
