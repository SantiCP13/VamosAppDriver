import 'package:flutter/material.dart';
import '../../../core/enums/payment_enums.dart'; // Asegúrate de que la ruta sea correcta
import '../../wallet/services/payment_socket_service.dart';
import '../../../core/di/injection_container.dart';
import '../repositories/trip_repository.dart';

class PaymentWaitingSheet extends StatefulWidget {
  final String tripId;
  final double amount;
  final PaymentMethod paymentMethod;
  final VoidCallback onPaymentConfirmed;

  const PaymentWaitingSheet({
    super.key,
    required this.tripId,
    required this.amount,
    required this.paymentMethod,
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

    // <--- CAMBIO LÓGICO: Usamos el getter 'isManual' de la extensión.
    // Solo conectamos al socket si el método requiere validación de pasarela o backend (NO es manual)
    if (!widget.paymentMethod.isManual) {
      // 1. Escuchar la respuesta del Socket
      _socketService.paymentStream.listen((status) {
        if (status == PaymentStatus.APPROVED) {
          if (mounted) {
            Navigator.pop(context); // Cerrar Sheet
            widget.onPaymentConfirmed(); // Ejecutar Callback (Finalizar viaje)
          }
        }
      });

      // 2. Conectar al canal
      _socketService.connectToTripPayment(
        widget.tripId,
        methodName: widget.paymentMethod.displayName,
      );
    }
  }

  @override
  void dispose() {
    // Es importante desconectar el socket al cerrar el modal
    _socketService.dispose();
    super.dispose();
  }

  // Helper para asignar un ícono visual según el método de pago
  IconData _getPaymentIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.CASH:
        return Icons.payments_outlined;
      case PaymentMethod.NEQUI:
      case PaymentMethod.DAVIPLATA:
        return Icons
            .phone_android_outlined; // Representa transferencia al celular
      case PaymentMethod.WALLET:
        return Icons.account_balance_wallet_outlined;
      case PaymentMethod.CREDIT_CARD:
      case PaymentMethod.WOMPI:
      case PaymentMethod.DIGITAL:
        return Icons.credit_card_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Variables auxiliares usando tu extensión
    final bool isManual = widget.paymentMethod.isManual;
    final String methodName = widget.paymentMethod.displayName;

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
          // Icono dinámico según el método de pago
          Icon(
            _getPaymentIcon(widget.paymentMethod),
            size: 60,
            color: Colors.green,
          ),
          const SizedBox(height: 20),

          // Texto dinámico: Informa al conductor qué está pasando o qué debe cobrar
          Text(
            isManual ? "Cobro con $methodName" : "Procesando $methodName...",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),

          // Monto a cobrar
          Text(
            "\$${widget.amount.toStringAsFixed(0)}",
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 30),

          // Lógica condicional de la UI:
          // Si es manual (Efectivo, Nequi, Daviplata), el conductor debe confirmar.
          // Si es automático, mostramos el loader esperando el socket.
          if (isManual)
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  // 1. Mostrar estado de carga (opcional, pero buena práctica)
                  // 2. Avisar al backend que recibimos el dinero físico
                  try {
                    await sl<TripRepository>().confirmCashPayment(
                      widget.tripId,
                    );
                  } catch (e) {
                    debugPrint("Error reportando pago manual al backend: $e");
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    widget.onPaymentConfirmed();
                  }
                },
                child: Text(
                  "Confirmar Recaudo ($methodName)",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 15),
                Text(
                  "Esperando confirmación de pago...",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
