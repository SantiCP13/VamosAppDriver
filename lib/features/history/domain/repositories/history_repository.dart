import '../../../../core/models/transaction_model.dart';

abstract class HistoryRepository {
  /// Obtiene el historial de viajes finalizados
  Future<List<TransactionModel>> getTripHistory();
}
