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
  bool _isAscending = false; // Control de ordenamiento
  String _selectedFilter = 'Todos'; // 🟢 Control de filtro dinámico
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

    // 🟢 Sorteo inteligente: Convertimos a local antes de comparar para evitar fallos de desfase
    trips.sort((a, b) {
      try {
        DateTime dateA = a.date.toLocal();
        DateTime dateB = b.date.toLocal();
        return _isAscending ? dateA.compareTo(dateB) : dateB.compareTo(dateA);
      } catch (e) {
        return 0;
      }
    });

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
            // Cabecera premium consistente (AppBar con botón de ordenación)
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
                  Expanded(
                    child: Text(
                      "HISTORIAL DE VIAJES",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isAscending = !_isAscending;
                      });
                      _loadHistory();
                    },
                    icon: Icon(
                      _isAscending
                          ? Icons.swap_vert_rounded
                          : Icons.swap_vert_rounded,
                      color: _isAscending
                          ? AppColors.primaryGreen
                          : Colors.white,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),
            ),

            // 🟢 INYECCIÓN: Barra de Filtros dinámica estilo conductor
            _buildFilterBar(),

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
                      child:
                          _applyFilter(_trips)
                              .isEmpty // 🟢 Aplicamos el filtro en caliente
                          ? _buildEmptyState()
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 10,
                              ),
                              itemCount: _applyFilter(
                                _trips,
                              ).length, // 🟢 Conteo filtrado
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, index) => _buildTripCard(
                                _applyFilter(_trips)[index],
                              ), // 🟢 Renderizado filtrado
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 🟢 Genera la barra de pestañas filtrables para el conductor (Sin programados)
  Widget _buildFilterBar() {
    final filters = [
      'Todos',
      'Finalizados',
      'Cancelados',
    ]; // 🟢 Removido 'Programados'
    return Container(
      height: 46,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter;

          return GestureDetector(
            onTap: () {
              setState(() => _selectedFilter = filter);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryGreen : cardColor,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: isSelected ? Colors.transparent : Colors.white10,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          // ignore: deprecated_member_use
                          color: AppColors.primaryGreen.withOpacity(0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Center(
                child: Text(
                  filter,
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    color: isSelected ? Colors.white : Colors.grey[400],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // 🟢 Clasifica los viajes de forma segura según su estado de base de datos (Sin programados)
  List<Trip> _applyFilter(List<Trip> list) {
    if (_selectedFilter == 'Finalizados') {
      return list.where((t) {
        final statusStr = t.status.toString().toUpperCase();
        return statusStr == 'COMPLETED';
      }).toList();
    }
    if (_selectedFilter == 'Cancelados') {
      return list.where((t) {
        final statusStr = t.status.toString().toUpperCase();
        return statusStr == 'CANCELLED';
      }).toList();
    }
    return list;
  }

  Widget _buildTripCard(Trip trip) {
    final currencyFormat = NumberFormat.currency(
      locale: 'es_CO',
      symbol: '\$',
      decimalDigits: 0,
    );

    // 🟢 1. CONVERSIÓN CRÍTICA DE FECHA AL HUSO HORARIO LOCAL
    final DateTime localDate = trip.date.toLocal();

    // 🟢 2. DETECCIÓN DINÁMICA DE ESTADOS REALES DEL VIAJE
    final bool isCompleted = trip.status == TripStatus.COMPLETED;
    final bool isCancelled = trip.status == TripStatus.CANCELLED;
    final bool isUpcoming =
        trip.status == TripStatus.PENDING ||
        trip.status == TripStatus.SCHEDULED_ASSIGNED;

    Color statusColor = AppColors.primaryGreen;
    String statusLabel = "COMPLETADO";
    IconData statusIcon = Icons.check_circle_rounded;

    if (isCancelled) {
      statusColor = Colors.redAccent;
      statusLabel = "CANCELADO";
      statusIcon = Icons.cancel_rounded;
    } else if (isUpcoming) {
      statusColor = Colors.orangeAccent;
      statusLabel = "PROGRAMADO";
      statusIcon = Icons.event_available_rounded;
    } else if (!isCompleted) {
      statusColor = Colors.blueAccent;
      statusLabel = "EN CURSO";
      statusIcon = Icons.navigation_rounded;
    }

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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 🟢 3. CABECERA RESPONSIVA (Soporta nombres de fecha largos sin desbordar)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 11,
                        color: Colors.white30,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            DateFormat(
                              'EEE, d MMM • hh:mm a',
                              'es',
                            ).format(localDate).toUpperCase(),
                            style: GoogleFonts.montserrat(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Insignia de Estado dinámica
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 10, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: GoogleFonts.montserrat(
                          fontSize: 9,
                          color: statusColor,
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

          // 🟢 4. DESGLOSE FINANCIERO RESPONSIVO (Uso de FittedBox para autoescalar cifras monetarias)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isCancelled ? "PENALIZACIÓN" : "GANANCIA NETA",
                        style: GoogleFonts.montserrat(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.white30,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          currencyFormat.format(
                            trip.driverRevenue,
                          ), // Mapeo de ganancia neta real corregida
                          style: GoogleFonts.montserrat(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: isCancelled
                                ? Colors.redAccent
                                : AppColors.primaryGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isCancelled) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "VALOR RECIBIDO",
                          style: GoogleFonts.montserrat(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: Colors.white30,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            trip.price <= 0.0
                                ? "Por confirmar"
                                : currencyFormat.format(
                                    trip.passengerCashToPay,
                                  ), // 🟢 Muestra el efectivo neto real recibido
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: trip.price <= 0.0
                                  ? AppColors.primaryGreen
                                  : Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
