import 'package:flutter/material.dart';
import '../../../core/models/trip_model.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import 'package:provider/provider.dart'; // <--- ESTE TE FALTA
import '../providers/home_provider.dart';

class TripRequestSheet extends StatelessWidget {
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
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().calculateIncomingTripRoute();
    });

    if (trip.id == '0' || trip.status == TripStatus.CANCELLED) {
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
              color: Colors.white10,
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
                    trip.passengerName,
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

          const SizedBox(height: 20),

          // Precios
          // Detalles del Viaje - REEMPLAZA ESTE BLOQUE EXACTO
          // Precios
          // Detalles del Viaje
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _priceColumn(
                      "Ganancia Neta",
                      _formatCurrency(trip.driverRevenue),
                    ),
                    Container(width: 1, height: 30, color: Colors.white10),
                    _priceColumn("Total Viaje", _formatCurrency(trip.price)),
                  ],
                ),

                // 🟢 INSIGNIA TRANSPARENTE DE SUBSIDIO VAMOS APP
                if (trip.hasDiscount) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      // ignore: deprecated_member_use
                      color: AppColors.primaryGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.stars_rounded,
                          size: 14,
                          color: AppColors.primaryGreen,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "CON SUBSIDIO: PASAJERO PAGARÁ \$ ${_formatCurrency(trip.passengerCashToPay)}",
                          style: GoogleFonts.montserrat(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryGreen,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Divider(color: Colors.white10),
                ),
                _infoRow(
                  "Distancia Total:",
                  "${trip.distanceKm.toStringAsFixed(1)} km",
                  Icons.straighten,
                ),
                _infoRow(
                  "Tiempo Estimado:",
                  "${trip.duration.toStringAsFixed(0)} min",
                  Icons.timer_outlined,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          _buildRouteTimeline(),

          const SizedBox(height: 30),

          // Botones
          Consumer<HomeProvider>(
            builder: (context, provider, _) {
              return Row(
                children: [
                  Expanded(
                    child: _actionButton(
                      "RECHAZAR",
                      // ignore: deprecated_member_use
                      const Color.fromARGB(255, 153, 11, 11),
                      const Color.fromARGB(255, 255, 255, 255),
                      onReject,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    flex: 2,
                    child: _actionButton(
                      "ACEPTAR VIAJE",
                      AppColors.primaryGreen,
                      const Color.fromARGB(255, 255, 255, 255),
                      onAccept,
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
  // Helpers Premium
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
        // ignore: deprecated_member_use
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _addressRow(
            Icons.radio_button_checked,
            "Recogida",
            trip.originAddress,
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
            trip.destinationAddress,
            Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _addressRow(IconData icon, String label, String address, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white30), // Icono más discreto
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

  // Pégalo justo antes del último } de la clase TripRequestSheet
  String _formatCurrency(double amount) {
    return "\$${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}";
  }
}
