// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/models/trip_model.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../providers/home_provider.dart';

class TripRequestSheet extends StatefulWidget {
  final Trip trip;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const TripRequestSheet({
    super.key,
    required this.trip,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<TripRequestSheet> createState() => _TripRequestSheetState();
}

class _TripRequestSheetState extends State<TripRequestSheet> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    // 🟢 OPTIMIZACIÓN: Solo conservamos la variable en uso para evitar warnings
    final double totalPeajes =
        (widget.trip.desglosePrecio?['total_peajes'] ?? 0.0).toDouble();

    if (widget.trip.id == '0' || widget.trip.status == TripStatus.CANCELLED) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Navigator.pop(context),
      );
      return const SizedBox.shrink();
    }

    final provider = context.watch<HomeProvider>();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF161B2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: Colors.white10, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "NUEVA SOLICITUD",
                    style: GoogleFonts.montserrat(
                      fontSize: 10,
                      color: Colors.white54,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.trip.passengerName, // 👈 Cambiado a 'widget.trip'
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  Text(
                    "TIEMPO HACIA LA RECOGIDA",
                    style: GoogleFonts.montserrat(
                      fontSize: 8,
                      color: Colors.white30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    provider.incomingTripEta,
                    style: GoogleFonts.montserrat(
                      fontSize: 18,
                      color: AppColors.primaryGreen,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 15),

          // Distancia
          Row(
            children: [
              const Icon(Icons.near_me, color: Colors.white30, size: 16),
              const SizedBox(width: 8),
              Text(
                "A ${(provider.incomingDistance / 1000).toStringAsFixed(1)} km de distancia",
                style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
              ),
            ],
          ),

          const SizedBox(height: 15),

          // Tarjeta de Detalles del Viaje
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              // ignore: duplicate_ignore
              // ignore: deprecated_member_use
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _priceColumn(
                      "Ganancia Neta",
                      _formatCurrency(
                        widget
                            .trip
                            .driverRevenue, // Mostrará la ganancia neta recalculada sobre el neto cobrado
                      ),
                    ),
                    Container(width: 1, height: 30, color: Colors.white10),
                    _priceColumn(
                      "Total Viaje",
                      _formatCurrency(
                        widget
                            .trip
                            .passengerCashToPay, // 🟢 SOLUCIÓN: Muestra la tarifa real con descuento cobrada en efectivo
                      ),
                    ),
                  ],
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.white10),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.toll_rounded,
                          color: Colors.orangeAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "ANÁLISIS DE PEAJES EN RUTA",
                          style: GoogleFonts.montserrat(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.orangeAccent,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 1. Peajes de aproximación
                    Row(
                      children: [
                        const Icon(
                          Icons.arrow_circle_right_outlined,
                          color: Colors.redAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Hacia el origen (Aproximación):",
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                provider.incomingTollsTotal > 0
                                    ? "Se cargará al pasajero y se te reembolsará al 100%"
                                    : "Sin peajes en el trayecto de recogida",
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          provider.incomingTollsTotal > 0
                              ? _formatCurrency(provider.incomingTollsTotal)
                              : "NO APLICA",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: provider.incomingTollsTotal > 0
                                ? Colors.redAccent
                                : Colors.white30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 2. Peajes del viaje
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          color: AppColors.primaryGreen,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Durante el viaje (Hacia el destino):",
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                totalPeajes > 0
                                    ? "✅ Reembolsado 100% en tu ganancia neta"
                                    : "Sin peajes en la ruta de viaje",
                                style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          totalPeajes > 0
                              ? _formatCurrency(totalPeajes)
                              : "NO APLICA",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: totalPeajes > 0
                                ? AppColors.primaryGreen
                                : Colors.white30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Divider(color: Colors.white10),
                ),
                _infoRow(
                  "Distancia Total:",
                  "${widget.trip.distanceKm.toStringAsFixed(1)} km", // 👈 Cambiado a 'widget.trip'
                  Icons.straighten,
                ),
                _infoRow(
                  "Tiempo Estimado:",
                  "${widget.trip.duration.toStringAsFixed(0)} min", // 👈 Cambiado a 'widget.trip'
                  Icons.timer_outlined,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          _buildRouteTimeline(),

          const SizedBox(height: 30),

          // Botones de respuesta
          Consumer<HomeProvider>(
            builder: (context, provider, _) {
              return Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      "RECHAZAR",
                      const Color.fromARGB(255, 153, 11, 11),
                      const Color.fromARGB(255, 255, 255, 255),
                      widget.onReject, // 👈 Cambiado a 'widget.onReject'
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: _actionButton(
                      "ACEPTAR VIAJE",
                      AppColors.primaryGreen,
                      const Color.fromARGB(255, 255, 255, 255),
                      widget.onAccept, // 👈 Cambiado a 'widget.onAccept'
                      isLoading: provider.isLoading,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 14, color: const Color.fromARGB(255, 255, 255, 255)),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: const Color.fromARGB(255, 255, 255, 255),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.primaryGreen,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _priceColumn(String title, String value) => Column(
    children: [
      Text(
        title.toUpperCase(),
        style: GoogleFonts.montserrat(
          fontSize: 9,
          color: Colors.white38,
          letterSpacing: 1.2,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        value,
        style: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ],
  );

  Widget _actionButton(
    String text,
    Color bg,
    Color txt,
    VoidCallback onTap, {
    bool isLoading = false,
  }) => ElevatedButton(
    onPressed: isLoading ? null : onTap,
    style: ElevatedButton.styleFrom(
      backgroundColor: bg,
      elevation: 0,
      padding: const EdgeInsets.symmetric(vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
    ),
    child: isLoading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          )
        : Text(
            text,
            style: GoogleFonts.montserrat(
              color: txt,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
  );

  Widget _buildRouteTimeline() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _addressRow(
            Icons.radio_button_checked,
            "Recogida",
            widget.trip.originAddress, // 👈 Cambiado a 'widget.trip'
            Colors.green,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 7, top: 4, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Icon(Icons.more_vert, size: 16, color: Colors.white24),
            ),
          ),
          _addressRow(
            Icons.location_on,
            "Destino",
            widget.trip.destinationAddress, // 👈 Cambiado a 'widget.trip'
            Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _addressRow(IconData icon, String label, String address, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white30),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            address,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _formatCurrency(double amount) {
    return "\$${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}";
  }
}
