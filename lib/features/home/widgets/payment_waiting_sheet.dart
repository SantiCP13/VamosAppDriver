// lib/features/home/widgets/payment_waiting_sheet.dart
// ignore_for_file: deprecated_member_use

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/enums/payment_enums.dart';
import '../../wallet/services/payment_socket_service.dart';
import '../../../core/di/injection_container.dart';
import '../repositories/trip_repository.dart';
import '../../../core/models/trip_model.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/home_provider.dart';

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
              // 🟢 Sincronizado: Enviamos el viaje directo sin alterar la pila del HomeScreen
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
    // 🟢 EXTRACCIÓN DINÁMICA DEL VIAJE ACTIVO DESDE EL PROVIDER
    final homeProvider = Provider.of<HomeProvider>(context, listen: false);
    final trip = homeProvider.activeTrip;

    // Mapeo seguro con variables desglosadas reales de espera
    // 🟢 SOLUCIÓN: El total a cobrar en efectivo lee la tarifa neta real con descuento
    final double efectivoACobrar = trip?.passengerCashToPay ?? widget.amount;
    final double recargoEspera = trip?.waitingFee ?? 0.0;
    final double tarifaOriginal = (trip != null && trip.basePrice > 0)
        ? trip.basePrice
        : (efectivoACobrar - recargoEspera);

    final double comisionApp = (trip != null && trip.platformFee > 0)
        ? trip.platformFee
        : (tarifaOriginal * 0.14);
    final double gananciaNetaConductor =
        (trip != null && trip.driverRevenue > 0)
        ? trip.driverRevenue
        : (tarifaOriginal - comisionApp);

    final bool tieneEspera = recargoEspera > 0.0;

    return PopScope(
      canPop: false, // Bloquea gestos de retroceso físicos
      child: Stack(
        children: [
          // 1. NEONES RADIALES DE FONDO (Le dan brillo y contraste al cristal)
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryGreen.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withOpacity(0.05),
              ),
            ),
          ),

          // 2. CONTENIDO RESPONSIVO Y TOTALMENTE CENTRADO
          Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 18,
                      sigmaY: 18,
                    ), // Filtro de cristal esmerilado
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFF161B2E,
                        ).withOpacity(0.65), // Cristal semi-transparente
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(
                            0.08,
                          ), // Borde brillante de cristal
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Icono de recaudo con aura brillante
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withOpacity(0.12),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primaryGreen.withOpacity(
                                    0.2,
                                  ),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.payments_rounded,
                                size: 40,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          Text(
                            "COBRAR EN EFECTIVO AL PASAJERO".toUpperCase(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.montserrat(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.grey[400],
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),

                          Text(
                            "\$ ${_formatCurrency(efectivoACobrar)}",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.montserrat(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Desglose financiero con diseño Liquid Glass interno de contraste
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0F172A,
                              ).withOpacity(0.5), // Cristal interno oscuro
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.04),
                                width: 1,
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildDesgloseRow(
                                  "Tarifa base del viaje:",
                                  "\$ ${_formatCurrency(tarifaOriginal)}",
                                ),
                                if (tieneEspera) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Divider(
                                      color: Colors.white10,
                                      height: 1,
                                    ),
                                  ),
                                  _buildDesgloseRow(
                                    "Recargo por espera extra:",
                                    "+\$ ${_formatCurrency(recargoEspera)}",
                                    valueColor: Colors.amberAccent,
                                  ),
                                ],
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Divider(
                                    color: Colors.white10,
                                    height: 1,
                                  ),
                                ),
                                _buildDesgloseRow(
                                  "Comisión de Vamos (14%):",
                                  "-\$ ${_formatCurrency(comisionApp)}",
                                  valueColor: Colors.redAccent,
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 10),
                                  child: Divider(
                                    color: Colors.white10,
                                    height: 1,
                                  ),
                                ),
                                _buildDesgloseRow(
                                  "Ganancia del viaje (86%):",
                                  "\$ ${_formatCurrency(gananciaNetaConductor)}",
                                  valueColor: const Color(
                                    0xFFFBBF24,
                                  ), // Dorado cálido
                                  isBold: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),

                          if (widget.paymentMethod.isManual)
                            SizedBox(
                              height: 60,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryGreen,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                onPressed: _isConfirming
                                    ? null
                                    : _handleManualPayment,
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
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
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
                ),
              ),
            ),
          ),
        ],
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

      // 🟢 CORREGIDO: Eliminado 'Navigator.pop(context)' para evitar que cierre la pantalla principal (HomeScreen)
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
