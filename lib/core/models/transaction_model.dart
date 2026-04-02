// ignore_for_file: constant_identifier_names

enum TransactionType { TRIP_PAYMENT, COMMISSION_FEE, WITHDRAWAL, ADJUSTMENT }

class TransactionModel {
  final String id;
  final String ledgerId; // FK a MOVIMIENTOS_LEDGER
  final String title;
  final String description;
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

  // --- NUEVO: MÉTODO PARA CONECTAR CON LARAVEL ---
  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    // Determinamos si es un ingreso o egreso según tu tabla movimientos_ledger
    final bool ingreso = map['tipo'] == 'ingreso';

    return TransactionModel(
      id: map['id']?.toString() ?? '',
      ledgerId: map['id_billetera']?.toString() ?? '',
      title: ingreso ? 'Ingreso de Dinero' : 'Cobro / Salida',
      description: map['descripcion'] ?? 'Movimiento de billetera',
      amount: double.tryParse(map['monto'].toString()) ?? 0.0,
      date: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      isCredit: ingreso,
      // Mapeamos al Enum según el tipo
      type: ingreso ? TransactionType.ADJUSTMENT : TransactionType.TRIP_PAYMENT,
      referenceId: map['id_pago']?.toString(),
    );
  }
}
