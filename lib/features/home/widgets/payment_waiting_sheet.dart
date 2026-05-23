// ignore_for_file: deprecated_member_use

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

  // Comisión oficial del backend (14% exacto)
  static const double _commissionRate = 0.14;

  double get _commissionAmount => widget.amount * _commissionRate;
  double get _netRevenue => widget.amount - _commissionAmount;

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

  String _formatCurrency(double amount) => amount
      .toStringAsFixed(0)
      .replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]}.',
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Bloquea gestos de retroceso
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(30, 20, 30, 36),
          decoration: const BoxDecoration(
            color: Color(0xFF111827), // Fondo pizarra profunda elegante
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Barra superior táctil
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 24),
              Icon(
                widget.paymentMethod.isManual
                    ? Icons.payments_rounded
                    : Icons.sync_rounded,
                size: 52,
                color: AppColors.primaryGreen,
              ),
              const SizedBox(height: 16),
              Text(
                "Cobro con ${widget.paymentMethod.displayName}".toUpperCase(),
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[400],
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "\$ ${_formatCurrency(widget.amount)}",
                style: GoogleFonts.montserrat(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),

              // TARJETA DE DESGLOSE DE RECAUDO Y COMISIONES (Alineado al 14% oficial de la base de datos)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 24),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937).withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.05),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    _buildDesgloseRow(
                      "Efectivo a recibir:",
                      "\$ ${_formatCurrency(widget.amount)}",
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(color: Colors.white10, height: 1),
                    ),
                    _buildDesgloseRow(
                      "Comisión de servicio (14%):",
                      "-\$ ${_formatCurrency(_commissionAmount)}",
                      valueColor: Colors.redAccent,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(color: Colors.white10, height: 1),
                    ),
                    _buildDesgloseRow(
                      "Monto neto a tu billetera:",
                      "\$ ${_formatCurrency(_netRevenue)}",
                      valueColor: AppColors.primaryGreen,
                      isBold: true,
                    ),
                  ],
                ),
              ),

              if (widget.paymentMethod.isManual)
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: AppColors.primaryGreen.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: _isConfirming ? null : _handleManualPayment,
                    child: _isConfirming
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "CONFIRMAR RECAUDO",
                                style: GoogleFonts.montserrat(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                  ),
                )
              else
                Column(
                  children: [
                    const CircularProgressIndicator(
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Esperando confirmación bancaria...",
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesgloseRow(
    String label,
    String value, {
    Color valueColor = Colors.white,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            color: isBold ? Colors.white : Colors.grey[400],
          ),
        ),
        Text(
          value,
          style: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
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
