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
  final String? paymentMethod; // Agregado
  final double? netEarnings; // Agregado

  // Campos relacionales del viaje
  final String? originAddress;
  final String? destinationAddress;
  final double? durationMinutes;
  final double? grossAmount;
  final double? commission;
  final String? tripPaymentMethod;

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
    this.paymentMethod,
    this.netEarnings,
    this.originAddress,
    this.destinationAddress,
    this.durationMinutes,
    this.grossAmount,
    this.commission,
    this.tripPaymentMethod,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    final bool ingreso = map['tipo'] == 'ingreso';

    final Map<String, dynamic>? pagoMap = map['pago'] != null
        ? Map<String, dynamic>.from(map['pago'])
        : null;
    final Map<String, dynamic>? viajeMap =
        pagoMap != null && pagoMap['viaje'] != null
        ? Map<String, dynamic>.from(pagoMap['viaje'])
        : null;

    String? origin;
    String? destination;
    double? durationMin;
    double? gross;
    double? comm;
    double? net;
    String? method;

    if (viajeMap != null) {
      origin = viajeMap['origen']?.toString();
      destination = viajeMap['destino']?.toString();

      final desglose = viajeMap['desglose_precio'];
      if (desglose != null) {
        durationMin = double.tryParse(
          desglose['duracion_minutos']?.toString() ?? '',
        );
      }

      method = pagoMap?['metodo_pago'] ?? viajeMap['metodo_pago_preferido'];
      final double movementAmount =
          double.tryParse(map['monto'].toString()) ?? 0.0;

      // 🟢 DETECCIÓN DE MULTA: Si es una sanción por cancelación, anulamos los valores de viaje realizado
      if (method?.toString().toUpperCase() == 'MULTA') {
        gross = 0.0;
        comm = 0.0;
        net = -movementAmount; // Es una pérdida/descuento neto
      } else if (method?.toString().toUpperCase() == 'CORPORATIVO') {
        gross = double.tryParse(viajeMap['precio_estimado']?.toString() ?? '0');
        net = movementAmount;
        comm = (gross ?? 0.0) - net;
      } else {
        // EFECTIVO / TARJETA
        gross = double.tryParse(viajeMap['precio_estimado']?.toString() ?? '0');
        comm = movementAmount;
        net = (gross ?? 0.0) - comm;
      }
    }

    return TransactionModel(
      id: map['id']?.toString() ?? '',
      ledgerId: map['id_billetera']?.toString() ?? '',
      title: ingreso ? 'Ingreso de Dinero' : 'Cobro / Salida',
      description: map['descripcion'] ?? 'Movimiento de billetera',
      amount: double.tryParse(map['monto'].toString()) ?? 0.0,
      date: map['created_at'] != null
          ? DateTime.parse(map['created_at']).toLocal()
          : DateTime.now(),
      isCredit: ingreso,
      type: ingreso ? TransactionType.ADJUSTMENT : TransactionType.TRIP_PAYMENT,
      referenceId: map['id_pago']?.toString(),
      paymentMethod: method ?? map['payment_method'] ?? 'N/A',
      netEarnings:
          net ?? double.tryParse(map['net_earnings']?.toString() ?? '0'),
      originAddress: origin,
      destinationAddress: destination,
      durationMinutes: durationMin,
      grossAmount: gross,
      commission: comm,
      tripPaymentMethod: method,
    );
  }
}
