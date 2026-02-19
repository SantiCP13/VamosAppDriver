import '../../../../core/models/transaction_model.dart';

abstract class WalletRepository {
  Future<double> getBalance();
  Future<List<TransactionModel>> getHistory();
}
