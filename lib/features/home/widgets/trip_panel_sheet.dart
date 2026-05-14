import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/trip_model.dart';
import '../providers/home_provider.dart';
import '../../../core/theme/app_colors.dart';

class TripPanelSheet extends StatelessWidget {
  const TripPanelSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HomeProvider>(context);
    final trip = provider.activeTrip;

    // Si no hay viaje, no dibujamos nada
    if (trip == null) return const SizedBox.shrink();

    // Definimos las variables necesarias aquí para que estén disponibles en todo el build
    final bool isStarted = trip.status == TripStatus.STARTED;
    final primaryColor = isStarted
        ? const Color(0xFF2E7D32)
        : AppColors.primaryGreen;

    return Container(
      width: double.infinity, // Asegura que el ancho sea el de la pantalla
      constraints: BoxConstraints(
        minHeight: 100, // Altura mínima para que Flutter no se queje
        maxHeight: MediaQuery.of(context).size.height * 0.85, // Altura máxima
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize
              .min, // El contenido se adapta, pero con el Container padre tiene un límite
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 15),

            // CABECERA: ESTADO + ETA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _statusBadge(trip.status, provider.distanceToTarget),
                if (isStarted) _fuecButton(trip, context),
              ],
            ),
            const SizedBox(height: 20),

            // CLIENTE + CONTACTO
            _buildClientSection(trip, provider),
            const SizedBox(height: 15),

            // MANIFIESTO DE PASAJEROS (FUEC)
            _buildPassengerManifest(trip.passengers),
            const SizedBox(height: 20),

            // DIRECCIONES (Timeline)
            _buildTimelineAddresses(trip),
            const SizedBox(height: 25),

            // ACCIONES
            _buildActionButtons(
              context,
              provider,
              trip,
              primaryColor,
              isStarted,
            ),
          ],
        ),
      ),
    );
  }

  // --- MÉTODOS AUXILIARES ---

  Widget _statusBadge(TripStatus status, String distance) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Icon(Icons.directions_car, size: 14, color: AppColors.primaryGreen),
          const SizedBox(width: 6),
          Text(
            "${_getStatusText(status)} • $distance",
            style: GoogleFonts.poppins(
              color: AppColors.primaryGreen,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fuecButton(Trip trip, BuildContext context) {
    return InkWell(
      onTap: () => _openFuec(trip.fuecUrl, context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blueGrey[800],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              "FUEC",
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClientSection(Trip trip, HomeProvider provider) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 25,
          backgroundColor: Colors.blueGrey,
          child: Icon(Icons.person, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trip.passengerName,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "Cliente Principal",
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        _roundIconButton(
          Icons.chat_bubble,
          Colors.green,
          () => provider.launchWhatsApp(trip.passengers.first.phone ?? ""),
        ),
        const SizedBox(width: 10),
        _roundIconButton(Icons.sos, Colors.red, () => provider.launchSOS()),
      ],
    );
  }

  Widget _buildPassengerManifest(List<Passenger> passengers) {
    if (passengers.length <= 1) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "MANIFIESTO LEGAL",
            style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: passengers
                  .skip(1)
                  .map(
                    (p) => Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        children: [
                          Text(
                            p.name,
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "${p.documentType}: ${p.nationalId}",
                            style: GoogleFonts.poppins(fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineAddresses(Trip trip) {
    return Column(
      children: [
        _timelineRow(
          Icons.radio_button_checked,
          trip.originAddress,
          Colors.green,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(width: 1, height: 15, color: Colors.grey[300]),
          ),
        ),
        _timelineRow(
          Icons.location_on,
          trip.destinationAddress,
          Colors.redAccent,
        ),
      ],
    );
  }

  Widget _timelineRow(IconData icon, String address, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            address,
            style: GoogleFonts.poppins(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    HomeProvider provider,
    Trip trip,
    Color primaryColor,
    bool isStarted,
  ) {
    return Column(
      children: [
        // Usamos un Row con MainAxisSize.min para que no intente ocupar infinito
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isStarted)
              _actionBtn(
                Icons.close,
                "CANCELAR",
                Colors.red[50]!,
                Colors.red,
                () => _confirmCancel(context, provider),
              ),
            if (!isStarted) const SizedBox(width: 12),
            // En lugar de Expanded, usamos Flexible para que se adapte al espacio disponible
            Flexible(
              child: _actionBtn(
                null,
                _getActionText(trip.status).toUpperCase(),
                primaryColor,
                Colors.white,
                () => provider.handleTripAction(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _roundIconButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _actionBtn(
    IconData? icon,
    String text,
    Color bg,
    Color txt,
    VoidCallback onTap,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 100,
        maxWidth: 250,
        minHeight: 50,
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10), // Padding menor
        ),
        child: FittedBox(
          // <--- ESTO EVITA EL OVERFLOW
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) Icon(icon, color: txt, size: 18),
              if (icon != null) const SizedBox(width: 6),
              Text(
                text,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: txt,
                  fontSize: 13, // Reducimos levemente el tamaño
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFuec(String? url, BuildContext context) async {
    if (url == null || url.isEmpty) return;
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(const SnackBar(content: Text('Error al abrir PDF')));
    }
  }

  String _getStatusText(TripStatus status) => status == TripStatus.ACCEPTED
      ? "En camino"
      : (status == TripStatus.ARRIVED ? "En el sitio" : "En viaje");
  String _getActionText(TripStatus status) => status == TripStatus.ACCEPTED
      ? "Llegué al sitio"
      : (status == TripStatus.ARRIVED ? "Iniciar carrera" : "Finalizar viaje");

  void _confirmCancel(BuildContext context, HomeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("¿Cancelar viaje?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("VOLVER"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.cancelCurrentTrip(context);
            },
            child: const Text(
              "SÍ, CANCELAR",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
