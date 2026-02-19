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

    if (trip == null) return const SizedBox.shrink();

    // Colores semánticos
    final bool isStarted = trip.status == TripStatus.STARTED;
    final primaryColor = isStarted
        ? const Color(0xFFE53935)
        : AppColors.primaryGreen; // Uso del color unificado

    // -----------------------------------------------------------
    // LOGICA MOCK HÍBRIDA (PARA VISUALIZAR BENEFICIARIOS)
    // -----------------------------------------------------------
    // Aquí simulamos que hay más pasajeros si la lista viene vacía o con 1 solo,
    // para cumplir con tu requerimiento de "verlo" aunque el backend no esté listo.
    // Cuando el backend esté listo, borra este bloque 'if'.
    List<Passenger> displayPassengers = List.from(trip.passengers);
    if (displayPassengers.length <= 1) {
      // Usamos el objeto Passenger real
      displayPassengers.add(Passenger(name: 'Juan Pérez', nationalId: '0000'));
      displayPassengers.add(
        Passenger(name: 'Pepito López', nationalId: '1111'),
      );
    }
    // -----------------------------------------------------------

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Drag Handle
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

          // 2. Cabecera: Estado + FUEC (Botones más grandes)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _getStatusText(trip.status).toUpperCase(),
                  style: GoogleFonts.poppins(
                    color: primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (trip.fuecUrl != null) {
                    await launchUrl(
                      Uri.parse(trip.fuecUrl!),
                      mode: LaunchMode.externalApplication,
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Generando PDF...")),
                    );
                  }
                },
                icon: const Icon(
                  Icons.description,
                  size: 18,
                  color: Colors.white,
                ),
                label: const Text(
                  "VER FUEC",
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  elevation: 0,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),

          const Divider(height: 30),

          // 3. Información del Cliente y Contacto
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, size: 30, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.passengerName,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      "Cliente Principal",
                      style: GoogleFonts.poppins(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // BOTONES DE CONTACTO CLICKABLES
                    Row(
                      children: [
                        _ContactButton(
                          icon: Icons.chat_bubble, // WhatsApp
                          color: const Color(0xFF25D366),
                          label: "Chat",
                          onTap: () {
                            if (trip.passengers.isNotEmpty &&
                                trip.passengers.first.phone != null) {
                              provider.launchWhatsApp(
                                trip.passengers.first.phone!,
                              );
                            }
                          },
                        ),
                        const SizedBox(width: 10),
                        _ContactButton(
                          icon: Icons.sos, // SOS
                          color: Colors.red,
                          label: "SOS 123",
                          onTap: () => provider.launchSOS(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 4. LISTA DE BENEFICIARIOS (FUEC REQUIREMENT)
          // Se muestra si hay más de 1 pasajero (o si usamos el mock)
          if (displayPassengers.length > 1) ...[
            const SizedBox(height: 15),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "Beneficiarios / Acompañantes (FUEC):",
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: displayPassengers.skip(1).map((p) {
                      return Chip(
                        avatar: const CircleAvatar(
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.person_add,
                            size: 14,
                            color: Colors.black,
                          ),
                        ),
                        label: Text(
                          p.name,
                          style: GoogleFonts.poppins(fontSize: 12),
                        ),
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.grey.shade300),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // 5. Direcciones con mejor diseño
          _buildAddressTile(
            Icons.my_location,
            trip.status == TripStatus.ACCEPTED ? "Recoger en:" : "Origen:",
            trip.originAddress,
            Colors.blue,
            isFirst: true,
          ),
          _buildAddressTile(
            Icons.location_on,
            trip.status == TripStatus.ACCEPTED ? "Llevar a:" : "Destino:",
            trip.destinationAddress,
            Colors.red,
            isLast: true,
          ),

          const SizedBox(height: 25),

          // 6. BOTONES DE ACCIÓN (GRANDE Y CLARO)
          Row(
            children: [
              // Botón CANCELAR (Visible y con texto)
              if (trip.status != TripStatus.STARTED)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmCancel(context, provider),
                      icon: const Icon(
                        Icons.cancel_outlined,
                        color: Colors.red,
                      ),
                      label: Text(
                        "Cancelar\nViaje",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                      ),
                    ),
                  ),
                ),

              // Botón PRINCIPAL
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: provider.isLoading
                        ? null
                        : () => provider.handleTripAction(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                      shadowColor: primaryColor.withValues(alpha: 0.4),
                    ),
                    child: provider.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _getActionText(trip.status).toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),

          // 7. Botón Waze/Maps (Estilo "Link")
          const SizedBox(height: 10),
          Center(
            child: InkWell(
              onTap: provider.openExternalNavigation,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.network(
                      'https://upload.wikimedia.org/wikipedia/commons/thumb/a/a9/Waze_logo_2020.svg/1200px-Waze_logo_2020.svg.png',
                      height: 20,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.navigation,
                        size: 20,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Abrir Waze / Google Maps",
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helpers de Texto
  String _getStatusText(TripStatus status) {
    switch (status) {
      case TripStatus.ACCEPTED:
        return "En Camino";
      case TripStatus.ARRIVED:
        return "Esperando Pasajero";
      case TripStatus.STARTED:
        return "Viaje en Curso";
      default:
        return "";
    }
  }

  String _getActionText(TripStatus status) {
    switch (status) {
      case TripStatus.ACCEPTED:
        return "Llegué al Sitio";
      case TripStatus.ARRIVED:
        return "Iniciar Carrera";
      case TripStatus.STARTED:
        return "Finalizar Viaje";
      default:
        return "Cargando";
    }
  }

  // Widget auxiliar para direcciones con línea conectora visual
  Widget _buildAddressTile(
    IconData icon,
    String label,
    String address,
    Color dotColor, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(icon, size: 20, color: dotColor),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.grey[300],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    address,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(BuildContext context, HomeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "¿Cancelar viaje?",
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Esta acción afectará tu tasa de aceptación y podría generar cargos.",
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Volver"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.cancelCurrentTrip(context);
            },
            child: const Text(
              "Sí, Cancelar",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget privado para botón de contacto estilizado
class _ContactButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ContactButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
