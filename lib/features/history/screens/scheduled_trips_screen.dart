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

    // 🟢 Filtrar únicamente los viajes programados que están asignados
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
                ).format(trip.date).toUpperCase(),
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryGreen,
                  letterSpacing: 1,
                ),
              ),
              Text(
                currencyFormat.format(trip.price),
                style: GoogleFonts.montserrat(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: Colors.white10),
          ),
          _buildAddressRow(
            Icons.radio_button_checked,
            AppColors.primaryGreen,
            trip.originAddress,
          ),
          const SizedBox(height: 12),
          _buildAddressRow(
            Icons.location_on_rounded,
            Colors.redAccent,
            trip.destinationAddress,
          ),
          const SizedBox(height: 20),

          // BOTÓN DE ACCIÓN: IR AL ENCUENTRO
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: homeProvider.isLoading
                  ? null
                  : () async {
                      bool exito = await homeProvider
                          .iniciarRutaAlOrigenConViaje(trip);
                      if (exito && mounted) {
                        Navigator.pop(context); // Regresa al mapa principal
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
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

  Widget _buildEmptyState() => Center(
    child: Text(
      "SIN VIAJES PROGRAMADOS",
      style: GoogleFonts.montserrat(color: Colors.white30, letterSpacing: 1),
    ),
  );
}
