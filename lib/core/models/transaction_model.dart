// ignore_for_file: constant_identifier_names

enum TransactionType { TRIP_PAYMENT, COMMISSION_FEE, WITHDRAWAL, ADJUSTMENT }

class TransactionModel {
  final String id;
  final String ledgerId; // FK a MOVIMIENTOS_LEDGER
  final String title;
  final String description; // Puede contener "Viaje #123"
  final DateTime date;
  final double amount;
  final bool isCredit; // true = Entrada (+), false = Salida (-)
  final TransactionType type;
  final String? referenceId; // Trip ID o Withdrawal ID

  TransactionModel({
    required this.id,
    required this.ledgerId,
    required this.title,
    required this.description,
    required this.date,
    required this.amount,
    required this.isCredit,
    this.type = TransactionType.TRIP_PAYMENT,
    this.referenceId,
  });
}
