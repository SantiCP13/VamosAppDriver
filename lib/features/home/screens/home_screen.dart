import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/models/trip_model.dart';
import '../providers/home_provider.dart';
import '../../../features/auth/services/driver_auth_service.dart';
import '../../../core/models/user_model.dart';
import '../../wallet/providers/wallet_provider.dart';
import '../widgets/trip_request_sheet.dart';
import '../widgets/trip_panel_sheet.dart';
import '../widgets/side_menu.dart';
import 'dart:math' as math;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/utils/cached_tile_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final String myMapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';
  late HomeProvider _homeProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _homeProvider = Provider.of<HomeProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().initLocation();

      context.read<WalletProvider>().loadWalletData();
      context.read<HomeProvider>().addListener(_onTripStateChanged);
    });
  }

  @override
  void dispose() {
    _homeProvider.removeListener(_onTripStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    _mapController.dispose();
    super.dispose();
  }

  void _onTripStateChanged() {
    if (!mounted) return;

    // Usamos el provider directamente para verificar el viaje
    final trip = context.read<HomeProvider>().activeTrip;

    if (trip == null) return;

    if (trip.status == TripStatus.ACCEPTED ||
        trip.status == TripStatus.ARRIVED) {
      _mapController.move(trip.originLocation, 15.0);
    } else if (trip.status == TripStatus.STARTED) {
      _mapController.move(trip.destinationLocation, 15.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = DriverAuthService().currentUser;
    if (user != null &&
        user.verificationStatus != UserVerificationStatus.VERIFIED) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      drawer: const SideMenu(),
      body: Stack(
        children: [
          Selector<HomeProvider, List<LatLng>>(
            selector: (_, provider) => provider.routePoints,
            builder: (context, routePoints, child) {
              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter:
                      context.watch<HomeProvider>().currentPosition ??
                      const LatLng(4.6097, -74.0817),
                  initialZoom: 15.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://api.mapbox.com/styles/v1/mapbox/navigation-night-v1/tiles/{z}/{x}/{y}{r}?access_token=$myMapboxToken',
                    tileProvider: CachedTileProvider(),
                    // Si te sigue dando error de tipo, usa 'true' en lugar de RetinaMode.isHighDensity
                    retinaMode: true,
                    maxZoom: 16.0,
                    minZoom: 6.0,
                    tileSize: 256,
                    tileDisplay: const TileDisplay.fadeIn(
                      duration: Duration(milliseconds: 200),
                    ),
                  ),
                  if (routePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routePoints,
                          color: Colors.blueAccent,
                          strokeWidth: 5.0,
                        ),
                      ],
                    ),
                  const _MarkersLayer(),
                ],
              );
            },
          ),
          Consumer<HomeProvider>(
            builder: (context, provider, _) {
              final trip = provider.activeTrip;
              return Stack(
                children: [
                  if (trip == null) _buildMenuButton(),
                  if (trip == null) _buildOnlineStatusIndicator(provider),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      width: double.infinity,
                      // Forzamos al child a ocupar el ancho total del dispositivo
                      child: _buildPanelContent(context, provider),
                    ),
                  ),
                  _buildReCenterButton(provider, trip),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B2E).withValues(alpha: 0.8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildMenuButton() => Positioned(
    top: 50,
    left: 20,
    child: _buildPremiumButton(
      icon: Icons.menu,
      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
    ),
  );

  // En _HomeScreenState, busca este método:
  Widget _buildReCenterButton(HomeProvider provider, dynamic trip) =>
      Positioned(
        right: 20,
        bottom: trip != null ? 380 : 300,
        child: _buildPremiumButton(
          icon: Icons.my_location,
          // CAMBIO: Verificamos que sea != null antes de usar !
          onPressed: provider.currentPosition != null
              ? () => _mapController.move(provider.currentPosition!, 15)
              : () => debugPrint("GPS aún no cargado"),
        ),
      );

  Widget _buildOnlineStatusIndicator(HomeProvider provider) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 22),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161B2E).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white10, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: provider.isOnline
                      ? AppColors.primaryGreen
                      : Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                provider.isOnline ? "EN LÍNEA" : "DESCONECTADO",
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanelContent(BuildContext context, HomeProvider provider) {
    if (provider.incomingTrip != null) {
      return TripRequestSheet(
        trip: provider.incomingTrip!,
        onAccept: () => provider.acceptIncomingTrip(),
        onReject: () => provider.rejectIncomingTrip(),
      );
    }
    if (provider.activeTrip != null) return const TripPanelSheet();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(25, 25, 25, 35),
      decoration: BoxDecoration(
        color: const Color(0xFF161B2E).withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          if (!provider.isOnline) ...[
            Text(
              "¿Listo para trabajar?",
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
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
                  const CircularProgressIndicator(
                    color: AppColors.primaryGreen,
                  ),
                  const SizedBox(width: 15),
                  Text(
                    "Esperando servicios...",
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 65,
            child: ElevatedButton(
              onPressed: provider.isLoading
                  ? null
                  : () => provider.toggleOnlineStatus(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                provider.isOnline ? "TERMINAR TURNO" : "CONECTARSE AHORA",
                style: GoogleFonts.montserrat(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
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

class _VehicleSelector extends StatelessWidget {
  final HomeProvider provider;
  const _VehicleSelector({required this.provider});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        provider.loadVehicles();
        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF0B0F19),
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          builder: (ctx) => _VehicleModal(provider: provider),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: const Color(0xFF161B2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.directions_car_filled_rounded,
              color: AppColors.primaryGreen,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                provider.selectedVehicle == null
                    ? "Selecciona tu vehículo"
                    : "${provider.selectedVehicle!.brand} • ${provider.selectedVehicle!.plate}",
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white30,
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleModal extends StatelessWidget {
  final HomeProvider provider;
  const _VehicleModal({required this.provider});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Text(
            "TU FLOTA",
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          if (provider.myVehicles.isEmpty)
            Container(
              padding: const EdgeInsets.all(30),
              child: Text(
                "SIN VEHÍCULOS ASIGNADOS",
                style: GoogleFonts.poppins(color: Colors.white54),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: provider.myVehicles.length,
                itemBuilder: (context, index) {
                  final v = provider.myVehicles[index];
                  final isSelected = provider.selectedVehicle?.id == v.id;
                  return GestureDetector(
                    onTap: () {
                      provider.selectVehicle(v);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryGreen.withValues(alpha: 0.1)
                            : const Color(0xFF161B2E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryGreen
                              : Colors.white10,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.directions_car_filled_rounded,
                            color: isSelected
                                ? AppColors.primaryGreen
                                : Colors.white54,
                          ),
                          const SizedBox(width: 15),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.fullName,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "Placa: ${v.plate}",
                                style: GoogleFonts.poppins(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
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
  }
}

class _MarkersLayer extends StatelessWidget {
  const _MarkersLayer();
  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        final trip = provider.activeTrip;
        return MarkerLayer(
          markers: [
            if (provider.currentPosition != null)
              Marker(
                point: provider.currentPosition!,
                width: 60,
                height: 60,
                child: Transform.rotate(
                  angle: (provider.currentHeading * math.pi / 180),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/car.png',
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),
              ),
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
            if (trip != null && trip.status == TripStatus.STARTED)
              Marker(
                point: trip.destinationLocation,
                width: 40,
                height: 40,
                child: const Icon(Icons.flag, color: Colors.red, size: 40),
              ),
          ],
        );
      },
    );
  }
}
