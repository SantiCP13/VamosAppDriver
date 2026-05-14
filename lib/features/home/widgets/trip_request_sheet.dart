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
    if (trip.id == '0' || trip.status == TripStatus.CANCELLED) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => Navigator.pop(context),
      );
      return const SizedBox.shrink();
    }
    final double totalPeajes = (trip.legalSnapshot?['total_peajes'] ?? 0)
        .toDouble();
    final bool tienePeajes = totalPeajes > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(25, 12, 25, 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 25, spreadRadius: 10),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 45,
            height: 5,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "OFERTA DISPONIBLE",
                        style: GoogleFonts.poppins(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      trip.passengerName,
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "\$${trip.price.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}",
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  if (tienePeajes)
                    Text(
                      "Con peajes",
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.amber[900],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 25),

          // --- LINEA DE TIEMPO DE DIRECCIONES ---
          _buildRouteTimeline(),

          const SizedBox(height: 30),

          Row(
            children: [
              // En la fila de botones (al final de TripRequestSheet)
              Expanded(
                child: TextButton(
                  onPressed: () {
                    // AQUÍ ESTÁ EL CAMBIO:
                    Provider.of<HomeProvider>(
                      context,
                      listen: false,
                    ).rejectIncomingTrip();
                    Navigator.pop(context); // Cerramos el modal de oferta
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: Text(
                    "RECHAZAR",
                    style: GoogleFonts.poppins(
                      color: Colors.red[400],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 5,
                    shadowColor: AppColors.primaryGreen.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    "ACEPTAR VIAJE",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteTimeline() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Column(
        children: [
          _addressRow(
            Icons.radio_button_checked,
            "Recogida",
            trip.originAddress,
            Colors.green,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 2, height: 20, color: Colors.grey[300]),
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
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                address,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
