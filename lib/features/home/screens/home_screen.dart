import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart'; // <-- AÑADIR ESTE
import '../../../core/theme/app_colors.dart';

// Imports Core & Models
import '../../../core/models/trip_model.dart';
import '../providers/home_provider.dart';
import '../../../features/auth/services/driver_auth_service.dart';
import '../../auth/screens/welcome_screen.dart' hide AppColors;
import '../../../core/models/user_model.dart';
import '../../wallet/providers/wallet_provider.dart';

// Widgets
import '../widgets/trip_request_sheet.dart';
import '../widgets/trip_panel_sheet.dart'; // <--- NUEVO IMPORT
import '../widgets/side_menu.dart';
import 'dart:math' as math; // Para la rotación
import 'package:flutter_dotenv/flutter_dotenv.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final String myMapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint("🚩 Pasó por initState de HomeScreen");

      // Iniciamos GPS y Vehículos
      context.read<HomeProvider>().initLocation();

      // 🔥 FORZAMOS CARGA DE BILLETERA
      debugPrint("🚩 Llamando a loadWalletData...");
      context.read<WalletProvider>().loadWalletData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // --- DETECTOR DE SEGUNDO PLANO ---
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkKillSwitchSilently();
    }
  }

  Future<void> _checkKillSwitchSilently() async {
    try {
      final authService = DriverAuthService();
      final status = await authService.verifySessionAndGetStatus();

      if (!mounted) return;

      // Si el administrador cambió su estado a falso en Laravel (ya no está verificado)
      if (status != UserVerificationStatus.VERIFIED && status != null) {
        _showKillSwitchModal();
      }
    } catch (e) {
      // Si tira error 403, el interceptor de api_client.dart atrapará el error
      // y lanzará el Modal desde allá.
    }
  }

  void _showKillSwitchModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Row(
            children: [
              Icon(Icons.block, color: Color.fromARGB(255, 8, 7, 71), size: 28),
              SizedBox(width: 10),
              Text(
                "Cuenta Inactiva",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: const Text(
            "Tu cuenta ha sido desactivada o puesta en revisión.\n\nPor favor, contacta a soporte:\n\n📧 soporte@vamosapp.com\n📞 +57 300 000 0000",
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                await DriverAuthService().logout();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
              },
              child: const Text(
                "Entendido",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Escuchamos los cambios del Provider Global
    final provider = context.watch<HomeProvider>();
    final trip = provider.activeTrip;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const SideMenu(),
      body: Stack(
        children: [
          // --------------------------
          // 1. EL MAPA
          // --------------------------
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  provider.currentPosition ?? const LatLng(4.6097, -74.0817),
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$myMapboxToken',
                additionalOptions: {'accessToken': myMapboxToken},
                tileProvider: NetworkTileProvider(),
              ),
              // Ruta Azul
              if (provider.routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: provider.routePoints,
                      color: Colors.blueAccent,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
              // Marcadores
              MarkerLayer(
                markers: [
                  // Auto del Conductor
                  if (provider.currentPosition != null)
                    Marker(
                      point: provider.currentPosition!,
                      width: 80,
                      height: 80,
                      child: Transform.rotate(
                        angle:
                            (provider.currentHeading *
                            math.pi /
                            180), // Rotación real
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Efecto Glow (Sombra verde suave)
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primaryGreen.withValues(
                                  alpha: 0.15,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color.fromARGB(
                                      255,
                                      9,
                                      192,
                                      3,
                                    ).withValues(alpha: 0.2),
                                    blurRadius: 15,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                            ),
                            // El Vehículo (Puedes usar un Icono o una imagen local)
                            const Icon(
                              Icons
                                  .navigation_rounded, // Icono estilo "flecha pro" o directions_car
                              color: Color.fromARGB(255, 1, 17, 71),
                              size: 35,
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Origen (Verde)
                  if (trip != null &&
                      (trip.status == TripStatus.ACCEPTED ||
                          trip.status == TripStatus.ARRIVED))
                    Marker(
                      point: trip.originLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                  // Destino (Rojo)
                  if (trip != null && trip.status == TripStatus.STARTED)
                    Marker(
                      point: trip.destinationLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.flag,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // --------------------------
          // 2. BOTÓN MENÚ (Hamburguesa)
          // --------------------------
          // Solo visible si no hay viaje activo para no saturar la pantalla
          // --- REEMPLAZAR EL BOTÓN DE MENÚ ---
          if (trip == null)
            Positioned(
              top: 50,
              left: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.menu, color: Colors.black87),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ),
            ),

          // --- REEMPLAZAR EL INDICADOR DE ESTADO (ONLINE/OFFLINE) ---
          if (trip == null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 25,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(35), // Ultra redondeado
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: provider.isOnline
                              ? AppColors.primaryGreen
                              : Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (provider.isOnline
                                          ? AppColors.primaryGreen
                                          : Colors.redAccent)
                                      .withValues(alpha: 0.4),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        provider.isOnline ? "EN LÍNEA" : "DESCONECTADO",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.5,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildPanelContent(context, provider),
          ),
          // --- REEMPLAZAR EL BOTÓN RE-CENTRAR ---
          Positioned(
            right: 20,
            bottom: trip != null ? 380 : 300,
            child: GestureDetector(
              onTap: () {
                if (provider.currentPosition != null) {
                  _mapController.move(provider.currentPosition!, 15);
                }
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.my_location, color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Selector inteligente de paneles inferiores
  Widget _buildPanelContent(BuildContext context, HomeProvider provider) {
    // CASO 1: OFERTA ENTRANTE
    if (provider.incomingTrip != null) {
      return TripRequestSheet(
        trip: provider.incomingTrip!,
        onAccept: () => provider.acceptIncomingTrip(),
        onReject: () => provider.rejectIncomingTrip(),
      );
    }

    // CASO 2: VIAJE EN CURSO (AQUÍ ESTÁ EL CAMBIO CLAVE)
    if (provider.activeTrip != null) {
      // Reemplazamos el widget antiguo por el nuevo TripPanelSheet
      // No necesitamos pasar argumentos porque TripPanelSheet usa Provider internamente.
      return const TripPanelSheet();
    }

    // CASO 3: STANDBY / OFFLINE
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(25, 15, 25, 35),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
        boxShadow: [
          BoxShadow(
            color: Colors
                .black12, // Un poco más fuerte aquí para el contraste de base
            blurRadius: 20,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle de arrastre visual
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          if (!provider.isOnline) ...[
            Text(
              "¿Listo para trabajar?",
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 15),
            _VehicleSelector(provider: provider),
          ],

          if (provider.isOnline)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Text(
                    "Esperando servicios...",
                    style: GoogleFonts.poppins(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: provider.isLoading
                  ? null
                  : () => provider.toggleOnlineStatus(),
              style: ElevatedButton.styleFrom(
                backgroundColor: provider.isOnline
                    ? Colors.grey[900]
                    : AppColors.primaryGreen,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                provider.isOnline ? "TERMINAR TURNO" : "CONECTARSE AHORA",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget auxiliar para selección de vehículos (Se mantiene igual)
class _VehicleSelector extends StatelessWidget {
  final HomeProvider provider;

  const _VehicleSelector({required this.provider});

  void _showSelectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) {
        return Consumer<HomeProvider>(
          builder: (context, provider, child) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle superior
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Text(
                    "Tu Flota Disponible",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Selecciona el vehículo que conducirás hoy",
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (provider.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40.0),
                      child: CircularProgressIndicator(
                        color: AppColors.primaryGreen,
                      ),
                    )
                  else if (provider.myVehicles.isEmpty)
                    _buildEmptyState()
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: provider.myVehicles.length,
                        itemBuilder: (context, index) {
                          final vehicle = provider.myVehicles[index];
                          final isSelected =
                              provider.selectedVehicle?.id == vehicle.id;

                          return GestureDetector(
                            onTap: () {
                              provider.selectVehicle(vehicle);
                              Navigator.pop(ctx);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.only(bottom: 15),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primaryGreen.withValues(
                                        alpha: 0.05,
                                      )
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primaryGreen
                                      : Colors.grey.shade200,
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Icono o Imagen del tipo de auto
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primaryGreen
                                          : Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.directions_car_filled_rounded,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          vehicle.fullName,
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                        Text(
                                          "Placa: ${vehicle.plate}",
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle,
                                      color: AppColors.primaryGreen,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Widget auxiliar para cuando no hay autos
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          Icon(Icons.no_crash_outlined, size: 50, color: Colors.grey[300]),
          const SizedBox(height: 15),
          Text(
            "Sin vehículos autorizados",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        provider.loadVehicles();
        _showSelectionModal(context);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20), // Borde Premium
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.garage_rounded, color: Colors.black54),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                provider.selectedVehicle == null
                    ? "Selecciona tu vehículo"
                    : "${provider.selectedVehicle!.brand} • ${provider.selectedVehicle!.plate}",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: provider.selectedVehicle == null
                      ? Colors.redAccent
                      : Colors.black87,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
