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
            // --- CABECERA ESTILO BILLETERA ---
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

            // --- CUERPO ---
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
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
                  color: Colors.white54,
                  letterSpacing: 1,
                ),
              ),
              Text(
                currencyFormat.format(trip.price),
                style: GoogleFonts.montserrat(
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 15),
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
      "SIN VIAJES REGISTRADOS",
      style: GoogleFonts.montserrat(color: Colors.white30, letterSpacing: 1),
    ),
  );
}
