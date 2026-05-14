import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/enums/payment_enums.dart';
import '../../wallet/services/payment_socket_service.dart';
import '../../../core/di/injection_container.dart';
import '../repositories/trip_repository.dart';
import '../../../core/models/trip_model.dart';
import '../../../core/theme/app_colors.dart';

class PaymentWaitingSheet extends StatefulWidget {
  final String tripId;
  final double amount;
  final PaymentMethod paymentMethod;
  final Function(Trip) onPaymentConfirmed;

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
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    if (!widget.paymentMethod.isManual) {
      _socketService.paymentStream.listen((status) async {
        if (status == PaymentStatus.APPROVED) {
          try {
            final finalTrip = await sl<TripRepository>().updateTripStatus(
              widget.tripId,
              "COMPLETED",
            );
            if (mounted) {
              Navigator.pop(context);
              widget.onPaymentConfirmed(finalTrip);
            }
          } catch (e) {
            debugPrint("Error socket payment: $e");
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Bloquea gestos de retroceso
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: const BoxDecoration(
            color: Color(0xFF161B2E), // Azul oscuro premium
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 30),
              Icon(
                widget.paymentMethod.isManual
                    ? Icons.payments_rounded
                    : Icons.sync_rounded,
                size: 50,
                color: AppColors.primaryGreen,
              ),
              const SizedBox(height: 20),
              Text(
                "Cobro con ${widget.paymentMethod.displayName}",
                style: GoogleFonts.poppins(fontSize: 16, color: Colors.white70),
              ),
              Text(
                "\$${widget.amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}",
                style: GoogleFonts.montserrat(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 30),

              if (widget.paymentMethod.isManual)
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: _isConfirming ? null : _handleManualPayment,
                    child: _isConfirming
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            "CONFIRMAR RECAUDO",
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                )
              else
                Column(
                  children: [
                    const CircularProgressIndicator(
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "Esperando confirmación bancaria...",
                      style: GoogleFonts.poppins(color: Colors.white30),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleManualPayment() async {
    setState(() => _isConfirming = true);
    try {
      final freshTrip = await sl<TripRepository>().confirmCashPayment(
        widget.tripId,
        widget.paymentMethod,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onPaymentConfirmed(freshTrip);
    } catch (e) {
      setState(() => _isConfirming = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error al confirmar recaudo"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}
