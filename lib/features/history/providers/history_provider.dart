import 'package:flutter/material.dart';
import '../../../core/models/trip_model.dart';
import '../domain/repositories/history_repository.dart';

class HistoryProvider extends ChangeNotifier {
  final HistoryRepository repository;

  HistoryProvider({required this.repository});

  // CAMBIO: Ahora la lista es de tipo Trip
  List<Trip> _history = [];
  bool _isLoading = false;
  bool _dataLoaded = false;

  List<Trip> get history => _history;
  bool get isLoading => _isLoading;

  Future<void> loadHistory({bool forceRefresh = false}) async {
    if (_dataLoaded && !forceRefresh) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Ahora los tipos coinciden: List<Trip>
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
    // Simplemente insertamos el objeto Trip directamente
    _history.insert(0, trip);
    _dataLoaded = true;
    notifyListeners();
  }
}
