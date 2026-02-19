import '../../../../core/models/transaction_model.dart';
import '../../domain/repositories/history_repository.dart';

class ApiHistoryRepository implements HistoryRepository {
  @override
  Future<List<TransactionModel>> getTripHistory() async {
    // Por ahora vacío para no romper nada en producción
    return [];
  }
}
