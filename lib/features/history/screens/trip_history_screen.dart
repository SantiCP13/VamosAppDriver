// lib/features/history/screens/trip_history_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/models/trip_model.dart';
import '../data/repositories/history_repository_impl.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  final HistoryRepositoryImpl _repository = HistoryRepositoryImpl();
  bool _isLoading = true;
  List<Trip> _trips = [];

  final Color darkBg = const Color(0xFF0B0F19);
  final Color cardColor = const Color(0xFF161B2E);

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final trips = await _repository.getTripHistory();
    setState(() {
      _trips = trips;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // Cabecera premium consistente
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
                    "HISTORIAL DE VIAJES",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            // Cuerpo
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryGreen,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadHistory,
                      color: AppColors.primaryGreen,
                      child: _trips.isEmpty
                          ? _buildEmptyState()
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 10,
                              ),
                              itemCount: _trips.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, index) =>
                                  _buildTripCard(_trips[index]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(Trip trip) {
    final currencyFormat = NumberFormat.currency(
      locale: 'es_CO',
      symbol: '\$',
      decimalDigits: 0,
    );

    return Container(
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Sección Cabecera de Tarjeta
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 11,
                      color: Colors.white30,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat(
                        'EEE, d MMM • hh:mm a',
                        'es',
                      ).format(trip.date).toUpperCase(),
                      style: GoogleFonts.montserrat(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 10,
                        color: AppColors.primaryGreen,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "COMPLETADO",
                        style: GoogleFonts.montserrat(
                          fontSize: 9,
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          // Sección Ruta Detallada (Timeline)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildRouteRow(
                  Icons.radio_button_on,
                  AppColors.primaryGreen,
                  "Origen",
                  trip.originAddress,
                  isMain: true,
                ),
                _buildRouteConnector(),
                _buildRouteRow(
                  Icons.location_on_rounded,
                  Colors.redAccent,
                  "Destino",
                  trip.destinationAddress,
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white10),

          // Ganancia Total de Tarjeta
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "GANANCIA NETO",
                      style: GoogleFonts.montserrat(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.white30,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currencyFormat.format(trip.price),
                      style: GoogleFonts.montserrat(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteRow(
    IconData icon,
    Color color,
    String label,
    String address, {
    bool isMain = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.montserrat(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: isMain ? AppColors.primaryGreen : Colors.white30,
                ),
              ),
              Text(
                address,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
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

  Widget _buildRouteConnector() {
    return Row(
      children: [
        const SizedBox(width: 13),
        Container(
          width: 1.5,
          height: 12,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ],
    );
  }

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.auto_graph_rounded, size: 80, color: Colors.white10),
        const SizedBox(height: 20),
        Text(
          "Sin aventuras registradas",
          style: GoogleFonts.montserrat(
            color: Colors.white30,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        Text(
          "Tus viajes completados aparecerán aquí",
          style: GoogleFonts.poppins(color: Colors.white24, fontSize: 12),
        ),
      ],
    ),
  );
}
