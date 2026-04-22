import 'package:flutter/material.dart';
import '../../../core/enums/payment_enums.dart';
import '../../wallet/services/payment_socket_service.dart';
import '../../../core/di/injection_container.dart';
import '../repositories/trip_repository.dart';
import '../../../core/models/trip_model.dart'; // <--- 1. IMPORTACIÓN FALTANTE
import 'package:google_fonts/google_fonts.dart';

class PaymentWaitingSheet extends StatefulWidget {
  final String tripId;
  final double amount;
  final PaymentMethod paymentMethod;
  final Function(Trip) onPaymentConfirmed; // Callback que ahora exige un Trip

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

    if (!widget.paymentMethod.isManual) {
      // 2. CORRECCIÓN POSITIONAL ARGUMENT EN SOCKET
      _socketService.paymentStream.listen((status) async {
        if (status == PaymentStatus.APPROVED) {
          // Si el pago es por pasarela, pedimos al repo el viaje actualizado
          // para tener los datos financieros reales (ganancia/comisión).
          try {
            final finalTrip = await sl<TripRepository>().updateTripStatus(
              widget.tripId,
              "COMPLETED",
            );

            if (mounted) {
              Navigator.pop(context);
              widget.onPaymentConfirmed(finalTrip); // Pasamos el Trip obtenido
            }
          } catch (e) {
            debugPrint("Error obteniendo viaje final tras socket: $e");
          }
        }
      });

      _socketService.connectToTripPayment(
        widget.tripId,
        methodName: widget.paymentMethod.displayName,
      );
    }
  }

  @override
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }

  IconData _getPaymentIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.CASH:
        return Icons.payments_outlined;
      case PaymentMethod.NEQUI:
      case PaymentMethod.DAVIPLATA:
        return Icons.phone_android_outlined;
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
    final bool isManual = widget.paymentMethod.isManual;
    final String methodName = widget.paymentMethod.displayName;

    return Container(
      padding: const EdgeInsets.all(30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getPaymentIcon(widget.paymentMethod),
            size: 60,
            color: Colors.green,
          ),
          const SizedBox(height: 20),
          Text(
            "Cobro con $methodName",
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "\$${widget.amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}",
            style: GoogleFonts.poppins(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: Colors.green[700],
            ),
          ),
          const SizedBox(height: 30),

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
                  try {
                    // 3. CAPTURA DEL TRIP TRAS PAGO MANUAL
                    final freshTrip = await sl<TripRepository>()
                        .confirmCashPayment(
                          widget.tripId,
                          widget.paymentMethod,
                        );

                    if (!mounted) return;
                    // ignore: use_build_context_synchronously
                    Navigator.pop(context);
                    widget.onPaymentConfirmed(freshTrip);
                  } catch (e) {
                    debugPrint("Error reportando pago manual: $e");
                    if (!mounted) return;
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Error al confirmar: Verifica tu internet",
                        ),
                      ),
                    );
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
