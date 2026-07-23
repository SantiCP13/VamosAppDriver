// lib/features/history/screens/scheduled_trips_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/models/trip_model.dart';
import '../../home/providers/home_provider.dart';
import '../data/repositories/history_repository_impl.dart';

class ScheduledTripsScreen extends StatefulWidget {
  const ScheduledTripsScreen({super.key});

  @override
  State<ScheduledTripsScreen> createState() => _ScheduledTripsScreenState();
}

class _ScheduledTripsScreenState extends State<ScheduledTripsScreen> {
  final HistoryRepositoryImpl _repository = HistoryRepositoryImpl();
  bool _isLoading = true;
  List<Trip> _scheduledTrips = [];

  final Color darkBg = const Color(0xFF0B0F19);
  final Color cardColor = const Color(0xFF161B2E);

  @override
  void initState() {
    super.initState();
    _loadScheduledTrips();
  }

  Future<void> _loadScheduledTrips() async {
    setState(() => _isLoading = true);
    final allTrips = await _repository.getTripHistory();

    // Filtrar únicamente los viajes programados que están asignados o pendientes
    final filtered = allTrips.where((t) {
      final statusStr = t.status.toString().toUpperCase();
      return statusStr.contains('SCHEDULED_ASSIGNED') ||
          statusStr.contains('PENDING_SCHEDULED');
    }).toList();

    setState(() {
      _scheduledTrips = filtered;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final homeProvider = context.watch<HomeProvider>();

    return Scaffold(
      backgroundColor: darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // --- CABECERA ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Text(
                    "VIAJES PROGRAMADOS",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // --- CUERPO ---
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryGreen,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadScheduledTrips,
                      color: AppColors.primaryGreen,
                      child: _scheduledTrips.isEmpty
                          ? _buildEmptyState()
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 10,
                              ),
                              itemCount: _scheduledTrips.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, index) =>
                                  _buildScheduledCard(
                                    _scheduledTrips[index],
                                    homeProvider,
                                  ),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduledCard(Trip trip, HomeProvider homeProvider) {
    final currencyFormat = NumberFormat.currency(
      locale: 'es_CO',
      symbol: '\$',
      decimalDigits: 0,
    );

    // 🟢 1. CONVERSIÓN CRÍTICA DE HORA DEL VIAJE AL HUSO LOCAL
    final DateTime localScheduledDate = (trip.scheduledAt ?? trip.date)
        .toLocal();
    final List<dynamic> stops = trip.intermediateStops ?? [];
    final double totalTolls = (trip.desglosePrecio?['total_peajes'] ?? 0.0)
        .toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat(
                  'dd MMM, yyyy • hh:mm a',
                  'es', // Forzado en español para mantener consistencia
                ).format(localScheduledDate).toUpperCase(),
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryGreen,
                  letterSpacing: 1,
                ),
              ),
              const Icon(
                Icons.event_available_rounded,
                color: Colors.white30,
                size: 16,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Colors.white10),
          ),

          // Timeline de Ruta
          // 1. Origen
          _buildAddressRow(
            Icons.radio_button_checked,
            AppColors.primaryGreen,
            trip.originAddress,
          ),

          // 2. Renderizado de paradas intermedias
          if (stops.isNotEmpty) ...[
            for (var stop in stops) ...[
              const SizedBox(height: 4),
              _buildRouteConnector(),
              const SizedBox(height: 4),
              _buildAddressRow(
                Icons.adjust_rounded,
                Colors.orangeAccent,
                stop['direccion']?.toString() ??
                    stop['name']?.toString() ??
                    'Parada intermedia',
              ),
            ],
          ],

          const SizedBox(height: 4),
          _buildRouteConnector(),
          const SizedBox(height: 4),

          // 3. Destino
          _buildAddressRow(
            Icons.location_on_rounded,
            Colors.redAccent,
            trip.destinationAddress,
          ),
          const SizedBox(height: 18),

          // 🟢 2. DETALLES OPERATIVOS (DURACIÓN, DISTANCIA Y PEAJES)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                _buildMetricRow(
                  Icons.timer_outlined,
                  "Duración estimada:",
                  "${trip.duration.toStringAsFixed(0)} min",
                  Colors.white70,
                ),
                const SizedBox(height: 6),
                _buildMetricRow(
                  Icons.straighten_rounded,
                  "Distancia del trayecto:",
                  "${trip.distanceKm.toStringAsFixed(1)} km",
                  Colors.white70,
                ),
                const SizedBox(height: 6),
                _buildMetricRow(
                  Icons.toll_rounded,
                  "Peajes incluidos:",
                  totalTolls > 0
                      ? currencyFormat.format(totalTolls)
                      : "Sin peajes",
                  totalTolls > 0 ? Colors.orangeAccent : Colors.white30,
                  valueColor: totalTolls > 0
                      ? Colors.orangeAccent
                      : Colors.white54,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 🟢 3. DESGLOSE DE GANANCIA NETA VS MONTO A COBRAR
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(
                0xFF0B0F19,
              ), // Fondo oscuro para aislar la visualización
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _priceColumn(
                  "GANANCIA NETA",
                  currencyFormat.format(trip.driverRevenue),
                  AppColors.primaryGreen,
                ),
                Container(width: 1, height: 35, color: Colors.white10),
                _priceColumn(
                  "VALOR A COBRAR",
                  trip.price <= 0.0
                      ? "Por confirmar"
                      : currencyFormat.format(
                          trip.passengerCashToPay,
                        ), // 🟢 Muestra el valor real neto con descuento
                  trip.price <= 0.0 ? AppColors.primaryGreen : Colors.white70,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // BOTÓN DE ACCIÓN: IR AL ENCUENTRO
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: homeProvider.isLoading
                  ? null
                  : () async {
                      try {
                        bool exito = await homeProvider
                            .iniciarRutaAlOrigenConViaje(trip);
                        if (exito && mounted) {
                          Navigator.pop(context); // Regresa al mapa principal
                        }
                      } catch (e) {
                        // 🟢 CAPTURAMOS LA EXCEPCIÓN: Muestra el mensaje descriptivo (ej: Turno inactivo o Placa incorrecta)
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceAll("Exception: ", ""),
                              ),
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: homeProvider.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      "IR AL ENCUENTRO",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow(IconData icon, Color color, String text) => Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );

  Widget _buildRouteConnector() {
    return Row(
      children: [
        const SizedBox(width: 7),
        Container(width: 2, height: 10, color: Colors.white12),
      ],
    );
  }

  // Métodos helpers para estructurar la información del viaje programado de forma limpia
  Widget _buildMetricRow(
    IconData icon,
    String label,
    String value,
    Color iconColor, {
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 11,
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: valueColor ?? Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _priceColumn(String title, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: 9,
            color: Colors.white38,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() => Center(
    child: Text(
      "SIN VIAJES PROGRAMADOS",
      style: GoogleFonts.montserrat(color: Colors.white30, letterSpacing: 1),
    ),
  );
}
