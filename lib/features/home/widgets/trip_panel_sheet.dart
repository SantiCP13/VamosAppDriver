// lib/features/home/widgets/trip_panel_sheet.dart
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/trip_model.dart';
import '../providers/home_provider.dart';
import '../../../core/theme/app_colors.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 🟢 NUEVA IMPORTACIÓN

class TripPanelSheet extends StatelessWidget {
  final VoidCallback? onMinimize;

  const TripPanelSheet({super.key, this.onMinimize});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HomeProvider>(context);
    final trip = provider.activeTrip;

    if (trip == null) return const SizedBox.shrink();

    // 🟢 CÁLCULO SINCRO-HÍBRIDO DE ESPERA EXTRA (CLIENTE + BACKEND EN TODOS LOS ESTADOS)
    final bool tieneDemoraBackend = trip.waitingMinutes > 0;
    final bool esArrivedYDemora =
        trip.status == TripStatus.ARRIVED && provider.waitSeconds < 0;

    final double precioMinutoEspera =
        (trip.desglosePrecio?['precio_minuto_espera'] ?? 500.0).toDouble();

    final int minutosDemoraAcumulados = tieneDemoraBackend
        ? trip.waitingMinutes
        : (esArrivedYDemora ? (provider.waitSeconds.abs() / 60).ceil() : 0);

    final double recargoEsperaExtra = tieneDemoraBackend
        ? trip.waitingFee
        : (minutosDemoraAcumulados * precioMinutoEspera);

    // 🟢 SOLUCIÓN: Calculamos el precio acumulado usando la tarifa neta real con descuento
    final double precioFinalConEspera = tieneDemoraBackend
        ? trip.passengerCashToPay
        : (trip.passengerCashToPay + recargoEsperaExtra);
    // Peajes del Viaje (Origen a Destino)
    final double peajesViaje = (trip.desglosePrecio?['total_peajes'] ?? 0.0)
        .toDouble();
    final List peajesViajeList = trip.desglosePrecio?['peajes_detalles'] ?? [];

    // Peajes de Recogida (Aproximación del conductor)
    final double peajesAproximacion =
        (trip.desglosePrecio?['peajes_aproximacion_total'] ?? 0.0).toDouble();
    final List peajesAproximacionList =
        trip.desglosePrecio?['peajes_aproximacion_detalles'] ?? [];

    // Peajes consolidados para el cálculo total
    final double totalPeajesConsolidados = peajesViaje + peajesAproximacion;
    final int numPeajesTotal =
        peajesViajeList.length + peajesAproximacionList.length;
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
                  Row(
                    children: [
                      _fuecButton(trip, context),
                      // 🟢 NUEVO: Botón premium para colapsar el viaje y volver al inicio
                      if (trip.status == TripStatus.ACCEPTED &&
                          onMinimize != null) ...[
                        const SizedBox(width: 10),
                        InkWell(
                          onTap: onMinimize!,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1F2937),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Text(
                              "Cerrar",
                              style: GoogleFonts.montserrat(
                                color: Colors.grey[400],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // SECCIÓN: PASAJERO PRINCIPAL (Ahora con WhatsApp)
              _buildClientSection(trip, provider, primaryColor, context),
              const SizedBox(height: 16),

              // MANIFIESTO DE PASAJEROS ADICIONALES
              if (trip.status != TripStatus.ARRIVED) ...[
                _buildPassengerManifest(trip.passengers),
                const SizedBox(height: 16),
              ],

              // TIMELINE DE DIRECCIONES
              if (trip.status != TripStatus.ARRIVED) ...[
                _buildTimelineAddresses(trip),
              ],

              // 🟢 INDICADOR DEL VALOR TOTAL DEL SERVICIO CON RECARGO DE DEMORA DINÁMICO
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937).withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.payments_rounded,
                          color: Color(0xFF10B981), // Verde
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          esArrivedYDemora
                              ? "TARIFA ACUMULADA EN VIVO:"
                              : "VALOR ESTIMADO DEL VIAJE:",
                          style: GoogleFonts.montserrat(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white70,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatCurrency(
                            precioFinalConEspera,
                          ), // Sincronizado en tiempo real
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF10B981), // Verde
                          ),
                        ),
                      ],
                    ),
                    if (esArrivedYDemora) ...[
                      const Divider(color: Colors.white12, height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Recargo por demora (+$minutosDemoraAcumulados min):",
                            style: GoogleFonts.montserrat(
                              fontSize: 10,
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            "+ ${_formatCurrency(recargoEsperaExtra)}",
                            style: GoogleFonts.montserrat(
                              fontSize: 11,
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              if (totalPeajesConsolidados > 0) ...[
                const SizedBox(height: 16),
                _buildTollsCard(
                  trip,
                  totalPeajesConsolidados,
                  numPeajesTotal,
                  // Unificamos las listas de detalles para que se pinten de manera secuencial y transparente en la UI del conductor
                  [...peajesAproximacionList, ...peajesViajeList],
                ),
              ],
              if (trip.status == TripStatus.ARRIVED) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    color: provider.waitSeconds > 0
                        ? const Color(0xFF10B981).withValues(
                            alpha: 0.12,
                          ) // Verde cortesía
                        : Colors.amber.withValues(
                            alpha: 0.12,
                          ), // Amarillo espera extra
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: provider.waitSeconds > 0
                          ? const Color(0xFF10B981).withValues(alpha: 0.25)
                          : Colors.amberAccent.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        provider.waitSeconds > 0
                            ? Icons.hourglass_bottom_rounded
                            : Icons.add_alarm_rounded,
                        color: provider.waitSeconds > 0
                            ? const Color(0xFF10B981)
                            : Colors.amberAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        provider.waitSeconds > 0
                            ? "EL PASAJERO TIENE: ${_formatWaitTime(provider.waitSeconds)} MIN"
                            : "COBRANDO ESPERA EXTRA: +${_formatWaitTime(provider.waitSeconds.abs())} MIN",
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: provider.waitSeconds > 0
                              ? const Color(0xFF10B981)
                              : Colors.amberAccent,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 🚀 Ajuste: El botón manual de adición solo se muestra durante los 5 minutos de cortesía
              if (trip.status == TripStatus.ARRIVED &&
                  provider.waitSeconds > 0) ...[
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

  // 🟢 COMPONENTE PREMIUM: Muestra la lista de peajes de la carretera de forma horizontal e interactiva
  Widget _buildTollsCard(
    Trip trip,
    double totalPeajes,
    int numPeajes,
    List peajesList,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.toll_rounded,
                color: Colors.orangeAccent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(
                "PEAJES DE LA RUTA ($numPeajes)",
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.orangeAccent,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              Text(
                _formatCurrency(totalPeajes),
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: peajesList.map((p) {
                final String nombre = p['nombre'] ?? 'Peaje';
                final double precio = (p['precio'] ?? 0.0).toDouble();
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF374151),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        nombre.toUpperCase(),
                        style: GoogleFonts.montserrat(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatCurrency(precio),
                        style: GoogleFonts.montserrat(
                          fontSize: 11,
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
  // ... (Su código de _confirmCancel u otros métodos anteriores se mantiene igual)

  // 🟢 COLOQUE ESTE MÉTODO AQUÍ (Dentro de la clase TripPanelSheet, antes del último '}')
  String _formatCurrency(double amount) {
    return "\$${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}";
  }
} // <--- Esta es la última llave de cierre del archivo

Widget _stateHeaderLabel(TripStatus status, Color activeColor) {
  // 🟢 OPTIMIZACIÓN: Cambiado "YENDO AL ENCUENTRO" por "EN CAMINO" para ahorrar 45px de espacio
  final String labelText = status == TripStatus.STARTED
      ? "VIAJE EN CURSO"
      : (status == TripStatus.ARRIVED ? "EN EL SITIO" : "EN CAMINO");

  return Container(
    // 🟢 OPTIMIZACIÓN: Reducido padding horizontal de 16 a 12, y vertical de 10 a 8
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          size: 15, // Un píxel más discreto para evitar desbordes
          color: activeColor,
        ),
        const SizedBox(width: 6),
        Text(
          labelText.toUpperCase(),
          style: GoogleFonts.montserrat(
            color: activeColor,
            fontWeight: FontWeight.w900,
            fontSize:
                10, // Bajado un punto (de 11 a 10) para máxima responsividad
            letterSpacing: 0.8,
          ),
        ),
      ],
    ),
  );
}

Widget _fuecButton(Trip trip, BuildContext context) {
  return InkWell(
    onTap: () {
      final String fallbackUrl =
          (trip.fuecUrl != null && trip.fuecUrl!.isNotEmpty)
          ? trip.fuecUrl!
          : "https://api.vamosapp.com.co/api/viajes/${trip.id}/fuec/pdf-interno";

      _openFuec(fallbackUrl, context);
    },
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
            "Ver FUEC",
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
          child: CircleAvatar(
            // 🟢 CORREGIDO: Dinámico y sin 'const'
            radius: 20,
            backgroundColor: const Color(0xFF374151),
            backgroundImage:
                (trip.passengerPhotoUrl != null &&
                    trip.passengerPhotoUrl!.isNotEmpty)
                ? CachedNetworkImageProvider(trip.passengerPhotoUrl!)
                : null,
            child:
                (trip.passengerPhotoUrl == null ||
                    trip.passengerPhotoUrl!.isEmpty)
                ? const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 22,
                  )
                : null,
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
        _roundIconButton(
          Icons.chat_bubble_outline_rounded,
          activeColor,
          () async {
            if (rawPhone.isNotEmpty) {
              final String cleanPhone = rawPhone.replaceAll(
                RegExp(r'[^0-9]'),
                '',
              );
              final Uri whatsappUri = Uri.parse("https://wa.me/$cleanPhone");
              if (await canLaunchUrl(whatsappUri)) {
                await launchUrl(
                  whatsappUri,
                  mode: LaunchMode.externalApplication,
                );
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No se pudo abrir WhatsApp para chatear con el pasajero',
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
          },
        ),
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
  final List paradas = trip.desglosePrecio?['paradas'] ?? [];

  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF1F2937).withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
    ),
    child: Column(
      children: [
        // 1. Punto de Partida
        _timelineRow(
          Icons.radio_button_checked_rounded,
          trip.originAddress,
          const Color(0xFF10B981),
        ),

        // 2. Renderizado dinámico de Paradas Intermedias (si existen)
        if (paradas.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 2, height: 12, color: Colors.grey[800]),
            ),
          ),
          ...paradas.map((p) {
            final String dir = p['direccion'] ?? 'Parada intermedia';
            return Column(
              children: [
                _timelineRow(Icons.adjust_rounded, dir, Colors.amberAccent),
                Padding(
                  padding: const EdgeInsets.only(left: 7),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 2,
                      height: 12,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            );
          }),
        ] else ...[
          // Línea divisoria estándar si no hay paradas intermedias
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 2, height: 16, color: Colors.grey[800]),
            ),
          ),
        ],

        // 3. Destino Final
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
  // Leemos el estado dinámico desde el Provider
  final bool yaAgregado = provider.extraWaitingTimeAdded;

  return SizedBox(
    width: double.infinity,
    height: 48,
    child: OutlinedButton.icon(
      // Si ya fue agregado, el onPressed pasa a ser null para deshabilitar el botón
      onPressed: yaAgregado
          ? null
          : () async {
              try {
                // Enviamos 3 minutos al backend
                await provider.addExtraWaitingTime(3);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Se han adicionado +3 minutos al tiempo de espera del pasajero",
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
      icon: Icon(
        Icons.add_alarm_rounded,
        color: yaAgregado ? Colors.grey[600] : Colors.amberAccent,
        size: 20,
      ),
      label: Text(
        yaAgregado
            ? "TIEMPO EXTRA MÁXIMO ADICIONADO"
            : "ADICIONAR +3 MIN DE ESPERA",
        style: GoogleFonts.montserrat(
          color: yaAgregado ? Colors.grey[600] : Colors.amberAccent,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.8,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: yaAgregado
              ? (Colors.grey[800] ?? Colors.grey)
              : Colors.amberAccent,
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: yaAgregado
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.amber.withValues(alpha: 0.05),
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
  // 🟢 Detectamos si ya expiraron los 5 minutos de espera en estado ARRIVED
  final bool esInasistencia =
      trip.status == TripStatus.ARRIVED && provider.waitSeconds <= 0;
  final String labelCancelar = esInasistencia ? "INASISTENCIA" : "CANCELAR";

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
                backgroundColor: esInasistencia
                    ? Colors.amber.withValues(
                        alpha: 0.08,
                      ) // Color aviso para inasistencia
                    : Colors.red.withValues(alpha: 0.08),
                foregroundColor: esInasistencia
                    ? Colors.amber[300]
                    : Colors.red[300],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: esInasistencia
                        ? Colors.amber.withValues(alpha: 0.25)
                        : Colors.red.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  labelCancelar,
                  maxLines: 1,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w900,
                    fontSize:
                        11, // Reducido levemente para evitar overflows en palabras largas
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
  if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error al abrir PDF')));
    }
  }
}

String _formatWaitTime(int seconds) {
  final int mins = seconds ~/ 60;
  final int secs = seconds % 60;
  return "$mins:${secs.toString().padLeft(2, '0')}";
}

String _getActionText(TripStatus status) => status == TripStatus.ACCEPTED
    ? "Llegué al sitio"
    : (status == TripStatus.ARRIVED ? "Iniciar carrera" : "Finalizar viaje");

void _confirmCancel(BuildContext context, HomeProvider provider) {
  final trip = provider.activeTrip;
  if (trip == null) return;

  showDialog(
    context: context,
    barrierDismissible: false,
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
              "Si cancelas este viaje activo que ya se encuentra EN CURSO, se aplicará la penalización correspondiente configurada en el sistema.",
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
