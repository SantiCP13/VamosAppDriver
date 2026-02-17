import 'package:flutter/material.dart';
import '../../../core/enums/payment_enums.dart';
import '../../wallet/services/payment_socket_service.dart';

class PaymentWaitingSheet extends StatefulWidget {
  final double amount;
  final VoidCallback onPaymentConfirmed;

  const PaymentWaitingSheet({
    super.key,
    required this.amount,
    required this.onPaymentConfirmed,
  });

  @override
  State<PaymentWaitingSheet> createState() => _PaymentWaitingSheetState();
}

class _PaymentWaitingSheetState extends State<PaymentWaitingSheet> {
  final PaymentSocketService _socketService = PaymentSocketService();

  @override
  void initState() {
    super.initState();
    // Escuchar Socket
    _socketService.paymentStream.listen((status) {
      if (status == PaymentStatus.APPROVED) {
        if (mounted) {
          Navigator.pop(context); // Cerrar Sheet
          widget.onPaymentConfirmed(); // Ejecutar Callback
        }
      }
    });
    // Iniciar simulación backend
    _socketService.simulateWaitingForPayment();
  }

  @override
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(30),
      height: 400,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          const CircularProgressIndicator(strokeWidth: 2),
          const SizedBox(height: 20),
          const Icon(Icons.phonelink_ring, size: 50, color: Colors.blueAccent),
          const SizedBox(height: 20),
          const Text(
            "Esperando confirmación de pago...",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            "Cobro: \$${widget.amount.toStringAsFixed(0)}",
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const Spacer(),
          const Text(
            "El pasajero está realizando el pago en su app.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
