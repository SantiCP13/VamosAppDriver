// lib/features/home/widgets/trip_panel_sheet.dart
import 'dart:ui' as ui;
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

    final bool isStarted = trip.status == TripStatus.STARTED;
    final primaryColor = isStarted
        ? const Color(0xFF10B981) // Verde esmeralda para viaje en curso
        : AppColors.primaryGreen; // Verde de la marca para recogida

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF111827), // Fondo pizarra profunda
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra indicadora estática
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // CABECERA LIMPIA
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stateHeaderLabel(trip.status, primaryColor),
                  if (isStarted) _fuecButton(trip, context),
                ],
              ),
              const SizedBox(height: 18),

              // SECCIÓN: PASAJERO PRINCIPAL
              _buildClientSection(trip, provider, primaryColor, context),
              const SizedBox(height: 16),

              // MANIFIESTO DE PASAJEROS ADICIONALES (Ocultar si ya está en sitio de espera "ARRIVED")
              if (trip.status != TripStatus.ARRIVED) ...[
                _buildPassengerManifest(trip.passengers),
                const SizedBox(height: 16),
              ],

              // TIMELINE DE DIRECCIONES (Ocultar si ya está en sitio de espera "ARRIVED")
              if (trip.status != TripStatus.ARRIVED) ...[
                _buildTimelineAddresses(trip),
              ],

              // Botón de adición de tiempo en Estado ARRIVED
              if (trip.status == TripStatus.ARRIVED) ...[
                const SizedBox(height: 16),
                _buildExtraWaitingTimeButton(context, provider),
              ],

              const SizedBox(height: 24),

              // BOTONERA INFERIOR REDISEÑADA
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
      ),
    );
  }

  // --- ETIQUETA DE ESTADO LIMPIA Y DIRECTA (REEMPLAZA EL STATUS BADGE ANTERIOR) ---
  Widget _stateHeaderLabel(TripStatus status, Color activeColor) {
    final String labelText = status == TripStatus.STARTED
        ? "VIAJE EN CURSO"
        : (status == TripStatus.ARRIVED ? "EN EL SITIO" : "YENDO AL ENCUENTRO");

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: activeColor.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            status == TripStatus.STARTED
                ? Icons.navigation_rounded
                : Icons.person_pin_circle_rounded,
            size: 16,
            color: activeColor,
          ),
          const SizedBox(width: 8),
          Text(
            labelText.toUpperCase(),
            style: GoogleFonts.montserrat(
              color: activeColor,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fuecButton(Trip trip, BuildContext context) {
    return InkWell(
      onTap: () => _openFuec(trip.fuecUrl, context),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.picture_as_pdf_rounded,
              color: Colors.redAccent,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              "FUEC",
              style: GoogleFonts.montserrat(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPassengerPhone(Trip trip) {
    if (trip.passengerPhone != null && trip.passengerPhone!.isNotEmpty) {
      return trip.passengerPhone!;
    }
    if (trip.passengers.isNotEmpty &&
        trip.passengers.first.phone != null &&
        trip.passengers.first.phone!.isNotEmpty) {
      return trip.passengers.first.phone!;
    }
    return "";
  }

  Widget _buildClientSection(
    Trip trip,
    HomeProvider provider,
    Color activeColor,
    BuildContext context,
  ) {
    final String rawPhone = _getPassengerPhone(trip);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: activeColor.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: const CircleAvatar(
              radius: 20,
              backgroundColor: Color(0xFF374151),
              child: Icon(Icons.person_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.passengerName,
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  "Pasajero Principal",
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: Colors.grey[400],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _roundIconButton(Icons.phone_in_talk_rounded, activeColor, () async {
            if (rawPhone.isNotEmpty) {
              final String cleanPhone = rawPhone.replaceAll(
                RegExp(r'[^0-9]'),
                '',
              );
              final Uri launchUri = Uri(scheme: 'tel', path: cleanPhone);
              if (await canLaunchUrl(launchUri)) {
                await launchUrl(launchUri);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No se pudo iniciar la llamada al pasajero',
                      ),
                    ),
                  );
                }
              }
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Número de contacto no disponible en la BD'),
                  ),
                );
              }
            }
          }),
        ],
      ),
    );
  }

  Widget _buildPassengerManifest(List<Passenger> passengers) {
    if (passengers.length <= 1) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "PASAJEROS ADICIONALES EN MANIFIESTO",
            style: GoogleFonts.montserrat(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Colors.grey[500],
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: passengers
                  .skip(1)
                  .map(
                    (p) => Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF374151),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "${p.documentType}: ${p.nationalId}",
                            style: GoogleFonts.montserrat(
                              fontSize: 10,
                              color: Colors.grey[400],
                            ),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          _timelineRow(
            Icons.radio_button_checked_rounded,
            trip.originAddress,
            const Color(0xFF10B981),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 2, height: 16, color: Colors.grey[800]),
            ),
          ),
          _timelineRow(
            Icons.location_on_rounded,
            trip.destinationAddress,
            Colors.redAccent,
          ),
        ],
      ),
    );
  }

  Widget _timelineRow(IconData icon, String address, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            address,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildExtraWaitingTimeButton(
    BuildContext context,
    HomeProvider provider,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () async {
          try {
            await provider.addExtraWaitingTime(5);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Se han adicionado +5 minutos al tiempo de espera del pasajero",
                  ),
                  backgroundColor: AppColors.primaryGreen,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("No se pudo agregar tiempo extra: $e"),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          }
        },
        icon: const Icon(
          Icons.add_alarm_rounded,
          color: Colors.amberAccent,
          size: 20,
        ),
        label: Text(
          "ADICIONAR +5 MIN DE ESPERA",
          style: GoogleFonts.montserrat(
            color: Colors.amberAccent,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.8,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.amberAccent, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.amber.withValues(alpha: 0.05),
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    HomeProvider provider,
    Trip trip,
    Color primaryColor,
    bool isStarted,
  ) {
    return Row(
      children: [
        if (!isStarted) ...[
          Expanded(
            flex: 1,
            child: SizedBox(
              height: 58,
              child: ElevatedButton(
                onPressed: () => _confirmCancel(context, provider),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.08),
                  foregroundColor: Colors.red[300],
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Colors.red.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "CANCELAR",
                    maxLines: 1,
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: isStarted ? 1 : 2,
          child: SizedBox(
            height: 58,
            child: ElevatedButton(
              onPressed: () => provider.handleTripAction(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                elevation: 2,
                shadowColor: primaryColor.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _getActionText(trip.status).toUpperCase(),
                  maxLines: 1,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _roundIconButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  void _openFuec(String? url, BuildContext context) async {
    if (url == null || url.isEmpty) return;
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error al abrir PDF')));
      }
    }
  }

  String _getActionText(TripStatus status) => status == TripStatus.ACCEPTED
      ? "Llegué al sitio"
      : (status == TripStatus.ARRIVED ? "Iniciar carrera" : "Finalizar viaje");

  void _confirmCancel(BuildContext context, HomeProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(0xFF1F2937),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "¿Cancelar servicio?",
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Si cancelas este viaje activo, podrías recibir una penalización en tu historial.",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  color: Colors.grey[400],
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        "VOLVER",
                        style: GoogleFonts.montserrat(
                          color: Colors.grey[400],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        provider.cancelCurrentTrip(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "SÍ, CANCELAR",
                          maxLines: 1,
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
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
}
