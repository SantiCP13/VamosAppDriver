import 'dart:async';
import 'package:flutter/foundation.dart'; // <-- Necesario para debugPrint
import '../../../core/enums/payment_enums.dart';

class PaymentSocketService {
  final _paymentController = StreamController<PaymentStatus>.broadcast();
  Stream<PaymentStatus> get paymentStream => _paymentController.stream;

  void simulateWaitingForPayment() {
    debugPrint(
      "🔌 SOCKET: Conectado al canal del conductor...",
    ); // Usa debugPrint
    debugPrint("⏳ SOCKET: Esperando confirmación de pasarela...");

    Future.delayed(const Duration(seconds: 4), () {
      debugPrint("✅ SOCKET: ¡Evento PAYMENT_APPROVED recibido!");
      _paymentController.add(PaymentStatus.APPROVED);
    });
  }

  void dispose() {
    _paymentController.close();
  }
}
