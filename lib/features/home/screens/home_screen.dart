// lib/features/home/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isMapReady = false;

  final String myMapboxToken = dotenv.env['MAPBOX_TOKEN'] ?? '';
  late HomeProvider _homeProvider;

  AnimationController? _mapMoveController;
  AnimationController? _markerAnimationController;

  LatLng? _animatedPosition;
  double _animatedHeading = 0.0;
  List<LatLng> _animatedRoutePoints = [];
  LatLng? _animatedPassengerPosition;
  LatLng? _passengerTargetPosition; // <--- AGREGAR ÚNICAMENTE ESTA LÍNEA

  AnimationController? _passengerAnimationController;
  bool _isTrackingDriver = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _homeProvider = Provider.of<HomeProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();

    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // INICIALIZACIÓN
    _passengerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().initLocation();
      context.read<WalletProvider>().loadWalletData();
      context.read<HomeProvider>().addListener(_onTripStateChanged);
    });
  }

  void _onTripStateChanged() {
    if (!mounted) return;

    final provider = context.read<HomeProvider>();
    final trip = provider.activeTrip;
    final incoming = provider.incomingTrip;

    // --- BLINDAJE DE SEGURIDAD ---
    if (trip != null && trip.status == TripStatus.STARTED) {
      _markerAnimationController?.stop();
      _mapMoveController?.stop();
      _passengerAnimationController
          ?.stop(); // Detener animación del pasajero si inicia el viaje
      return;
    }

    if (trip == null && incoming == null) {
      if (_animatedRoutePoints.isNotEmpty) {
        setState(() {
          _animatedRoutePoints = [];
        });
      }
    }

    final newPos = provider.currentPosition;
    final newHeading = provider.currentHeading;

    // --- ANIMACIÓN DEL VEHÍCULO DEL CONDUCTOR ---
    if (newPos != null) {
      if (_animatedPosition == null) {
        setState(() {
          _animatedPosition = newPos;
          _animatedHeading = newHeading;
        });

        // PRIMER ENFOQUE AL ABRIR LA APP:
        // Si no hay viaje activo ni oferta entrante, forzamos al mapa a centrarse de inmediato en el conductor
        if (trip == null && incoming == null) {
          _isTrackingDriver = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _isMapReady) {
              _mapController.move(newPos, 16.5);
            }
          });
        }
      } else {
        final latTween = Tween<double>(
          begin: _animatedPosition!.latitude,
          end: newPos.latitude,
        );
        final lngTween = Tween<double>(
          begin: _animatedPosition!.longitude,
          end: newPos.longitude,
        );

        double startBearing = _animatedHeading;
        double diff = newHeading - startBearing;
        while (diff < -180.0) {
          diff += 360.0;
        }
        while (diff > 180.0) {
          diff -= 360.0;
        }
        final headingTween = Tween<double>(
          begin: startBearing,
          end: startBearing + diff,
        );

        _markerAnimationController?.stop();
        _markerAnimationController?.reset();

        final animation = CurvedAnimation(
          parent: _markerAnimationController!,
          curve: Curves.linear,
        );

        _markerAnimationController!.addListener(() {
          if (!mounted) return;
          setState(() {
            _animatedPosition = LatLng(
              latTween.evaluate(animation),
              lngTween.evaluate(animation),
            );
            _animatedHeading = headingTween.evaluate(animation) % 360.0;

            if (provider.routePoints.isNotEmpty && _animatedPosition != null) {
              _animatedRoutePoints = _trimRoutePointsLocal(
                _animatedPosition!,
                provider.routePoints,
              );
            }

            if (_isTrackingDriver && _animatedPosition != null) {
              final double targetZoom = _mapController.camera.zoom;
              final LatLng offsetCenter = _getOffsetPosition(
                _animatedPosition!,
                targetZoom,
              );
              _mapController.move(offsetCenter, targetZoom);
            }
          });
        });

        _markerAnimationController!.forward();
      }
    }

    // --- ANIMACIÓN EN TIEMPO REAL DEL PASAJERO (SOPORTA ESTADOS 3 Y 4) ---
    // --- ANIMACIÓN EN TIEMPO REAL DEL PASAJERO (SOPORTA ESTADOS 3 Y 4) ---
    final rawPassengerPos = provider.passengerLocation;
    if (rawPassengerPos != null) {
      if (_animatedPassengerPosition == null) {
        setState(() {
          _animatedPassengerPosition = rawPassengerPos;
          _passengerTargetPosition = rawPassengerPos;
        });
      } else if (_passengerTargetPosition != rawPassengerPos) {
        // PROTECCIÓN: Solo inicializa la animación si la coordenada objetivo real cambió.
        // Esto evita que las actualizaciones del GPS del conductor congelen al pasajero.
        _passengerTargetPosition = rawPassengerPos;

        final passLatTween = Tween<double>(
          begin: _animatedPassengerPosition!.latitude,
          end: rawPassengerPos.latitude,
        );
        final passLngTween = Tween<double>(
          begin: _animatedPassengerPosition!.longitude,
          end: rawPassengerPos.longitude,
        );

        _passengerAnimationController?.stop();
        _passengerAnimationController?.reset();

        final passAnimation = CurvedAnimation(
          parent: _passengerAnimationController!,
          curve: Curves.linear,
        );

        _passengerAnimationController!.addListener(() {
          if (!mounted) return;
          setState(() {
            _animatedPassengerPosition = LatLng(
              passLatTween.evaluate(passAnimation),
              passLngTween.evaluate(passAnimation),
            );
          });
        });

        _passengerAnimationController!.forward();
      }
    } else {
      if (_animatedPassengerPosition != null) {
        setState(() {
          _animatedPassengerPosition = null;
          _passengerTargetPosition = null;
        });
      }
    }

    // ... dentro de _onTripStateChanged() ...
    if (incoming != null) {
      _centerMapOnData(
        vehiclePos: provider.currentPosition,
        targetPos: incoming.originLocation,
      );
    } else if (trip != null) {
      if (trip.status == TripStatus.ARRIVED) {
        // En el sitio: Centrar siempre a ambos actores dentro del espacio visible superior
        _centerMapOnData(
          vehiclePos: provider.currentPosition,
          targetPos: provider.passengerLocation,
        );
      } else if (provider.routePoints.isNotEmpty && _animatedPosition == null) {
        LatLng target = trip.status == TripStatus.ACCEPTED
            ? trip.originLocation
            : trip.destinationLocation;
        _animatedMapMove(target, 15.5);
      }
    }
  }

  List<LatLng> _trimRoutePointsLocal(
    LatLng currentPos,
    List<LatLng> originalPoints,
  ) {
    if (originalPoints.isEmpty) return [];

    int closestIndex = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < originalPoints.length; i++) {
      final double dist = math.sqrt(
        math.pow(currentPos.latitude - originalPoints[i].latitude, 2) +
            math.pow(currentPos.longitude - originalPoints[i].longitude, 2),
      );
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }

    List<LatLng> trimmed = [currentPos];
    int startIndex = closestIndex;

    if (startIndex < originalPoints.length) {
      trimmed.addAll(originalPoints.sublist(startIndex));
    } else {
      trimmed.add(originalPoints.last);
    }
    return trimmed;
  }

  @override
  void dispose() {
    _homeProvider.removeListener(_onTripStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    _mapController.dispose();
    _mapMoveController?.dispose();
    _markerAnimationController?.dispose();
    _passengerAnimationController?.dispose(); // LIBERACIÓN

    super.dispose();
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (!_isMapReady || !mounted) return;
    _mapMoveController?.dispose();

    try {
      // Aplicamos el offset al punto final para que la cámara aterrice en la posición ajustada
      final LatLng offsetDest = _getOffsetPosition(destLocation, destZoom);

      final latTween = Tween<double>(
        begin: _mapController.camera.center.latitude,
        end: offsetDest.latitude,
      );
      final lngTween = Tween<double>(
        begin: _mapController.camera.center.longitude,
        end: offsetDest.longitude,
      );
      final zoomTween = Tween<double>(
        begin: _mapController.camera.zoom,
        end: destZoom,
      );

      _mapMoveController = AnimationController(
        duration: const Duration(milliseconds: 700),
        vsync: this,
      );

      final animation = CurvedAnimation(
        parent: _mapMoveController!,
        curve: Curves.fastOutSlowIn,
      );

      _mapMoveController!.addListener(() {
        _mapController.move(
          LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
          zoomTween.evaluate(animation),
        );
      });

      _mapMoveController!.forward();
    } catch (e) {
      debugPrint("Error en animación de mapa: $e");
      final LatLng offsetDest = _getOffsetPosition(destLocation, destZoom);
      _mapController.move(offsetDest, destZoom);
    }
  }

  void _centerMapOnData({LatLng? vehiclePos, LatLng? targetPos}) {
    if (!_isMapReady) return;

    final screenHeight = MediaQuery.of(context).size.height;

    // El modal en el estado ARRIVED cubre cerca de un 45% del alto.
    // Usamos un bottom padding del 48% para empujar el área de encuadre hacia arriba.
    double bottomPadding = screenHeight * 0.38;

    if (vehiclePos != null && targetPos != null) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([vehiclePos, targetPos]),
          padding: EdgeInsets.only(
            top: 130, // Margen superior de seguridad
            bottom: bottomPadding,
            left:
                65, // Margen lateral para que no toquen los bordes de la pantalla
            right: 65,
          ),
          maxZoom:
              17.0, // <- LIMITADOR CLAVE: Evita que el mapa se acerque demasiado cuando están muy cerca
        ),
      );
    }
  }

  Future<void> _launchExternalMap(String app, LatLng target) async {
    Uri uri;
    if (app == 'google') {
      uri = Uri.parse(
        "google.navigation:q=${target.latitude},${target.longitude}",
      );
      if (!await canLaunchUrl(uri)) {
        uri = Uri.parse(
          "https://www.google.com/maps/dir/?api=1&destination=${target.latitude},${target.longitude}",
        );
      }
    } else {
      uri = Uri.parse(
        "waze://?ll=${target.latitude},${target.longitude}&navigate=yes",
      );
      if (!await canLaunchUrl(uri)) {
        uri = Uri.parse(
          "https://waze.com/ul?ll=${target.latitude},${target.longitude}&navigate=yes",
        );
      }
    }

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Error lanzando mapa externo: $e");
    }
  }

  void _showExternalNavSheet(BuildContext context, LatLng target) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Text(
                "Navegar con app externa",
                style: GoogleFonts.montserrat(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Elige tu aplicación preferida para guiarte en el camino:",
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
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _launchExternalMap('google', target);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.map_rounded,
                              color: Colors.blueAccent,
                              size: 36,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Google Maps",
                              style: GoogleFonts.montserrat(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _launchExternalMap('waze', target);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F2937),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.explore_rounded,
                              color: Colors.orangeAccent,
                              size: 36,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Waze",
                              style: GoogleFonts.montserrat(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPassengerManifestView(List<Passenger> passengers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "PASAJEROS ADICIONALES",
          style: GoogleFonts.montserrat(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: Colors.grey[400], // Gris claro legible
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
                      color: const Color(0xFF1F2937), // Fondo oscuro
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: GoogleFonts.montserrat(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white, // Texto blanco
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${p.documentType}: ${p.nationalId}",
                          style: GoogleFonts.montserrat(
                            fontSize: 10,
                            color: Colors.grey[400], // Texto gris claro
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
    );
  }

  Widget _buildAddressesTimelineView(Trip trip) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(
              Icons.radio_button_checked_rounded,
              size: 16,
              color: Color(0xFF10B981),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                trip.originAddress,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: Colors.white, // Texto blanco legible
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 7),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 2,
              height: 16,
              color: Colors.white24, // Línea gris clara
            ),
          ),
        ),
        Row(
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 16,
              color: Colors.redAccent,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                trip.destinationAddress,
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  color: Colors.white, // Texto blanco legible
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openFuec(String url, BuildContext context) async {
    if (url.isEmpty) return;
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      if (mounted) {
        // <--- CORREGIDO: Usar mounted propio del State
        ScaffoldMessenger.of(
          // ignore: use_build_context_synchronously
          context,
        ).showSnackBar(const SnackBar(content: Text('Error al abrir PDF')));
      }
    }
  }

  Future<void> _callSOS() async {
    final Uri launchUri = Uri(scheme: 'tel', path: '*123');
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo iniciar la llamada S.O.S.")),
        );
      }
    } catch (e) {
      debugPrint("Error llamando SOS: $e");
    }
  }

  // --- INTERFAZ COMPLETA PARA EL CONDUCTOR (VIAJE EN CURSO) ---
  Widget _buildFullScreenDriverTripView(
    BuildContext context,
    HomeProvider provider,
    Trip trip,
  ) {
    final primaryColor = AppColors.primaryGreen;

    return Container(
      color: AppColors.darkBlue,
      // Fondo Dark Slate Premium (Cero consumo de Mapbox tiles)
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // CABECERA: Viaje en Curso + Botón FUEC (Bien ubicado y alineado)

              // ÁREA CENTRAL REDISEÑADA CON LOGO Y ESTADO DE CONEXIÓN (Sin distancias ni tiempos estimados)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logotipo de la aplicación
                      Image.asset(
                        'assets/images/logo.png',
                        height: 220,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 24),
                      // Indicador de estado de conectividad en tiempo real
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "Conexión de rastreo activa",
                              style: GoogleFonts.montserrat(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Recordatorio de seguridad
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.navigation_rounded,
                        color: primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "VIAJE EN CURSO",
                            style: GoogleFonts.montserrat(
                              color: primaryColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            "Conduce con precaución",
                            style: GoogleFonts.montserrat(
                              color: Colors.grey[400],
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // BOTÓN DESCARGAR FUEC (Ubicado a la derecha en la cabecera)
                    InkWell(
                      onTap: () {
                        final String fallbackUrl =
                            (trip.fuecUrl != null && trip.fuecUrl!.isNotEmpty)
                            ? trip.fuecUrl!
                            : "https://api.vamosapp.com.co/api/viajes/${trip.id}/fuec/pdf";
                        _openFuec(fallbackUrl, context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "FUEC",
                              style: GoogleFonts.montserrat(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              // TARJETA DE INFORMACIÓN: Pasajeros (Tarjeta Dark Premium Translúcida)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B2E).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Pasajero Principal
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.05,
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                "Pasajero Principal",
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Manifiesto de Pasajeros Adicionales
                    if (trip.passengers.length > 1) ...[
                      const SizedBox(height: 12),
                      Divider(
                        color: Colors.white.withValues(alpha: 0.08),
                        height: 1,
                      ),
                      const SizedBox(height: 12),
                      _buildPassengerManifestView(trip.passengers),
                    ],

                    const SizedBox(height: 12),
                    Divider(
                      color: Colors.white.withValues(alpha: 0.08),
                      height: 1,
                    ),
                    const SizedBox(height: 12),

                    // Destino / Origen del Viaje
                    _buildAddressesTimelineView(trip),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // BOTONERA DE ACCIÓN INFERIOR
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Botón S.O.S (Llamar al 123) - Ancho completo
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () => _callSOS(),
                      icon: const Icon(
                        Icons.emergency_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        "S.O.S",
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[800],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      // Botón Empezar a Navegar (Waze / Google Maps)
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              _showExternalNavSheet(
                                context,
                                trip.destinationLocation,
                              );
                            },
                            icon: const Icon(
                              Icons.navigation_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            label: Text(
                              "NAVEGAR",
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Colors.white30,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.02,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Botón Finalizar Viaje
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () => provider.handleTripAction(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                              shadowColor: primaryColor.withValues(alpha: 0.3),
                            ),
                            child: Text(
                              "FINALIZAR VIAJE",
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWazeButton(HomeProvider provider) {
    final trip = provider.activeTrip;

    // Ocultar botón de Waze si el viaje es nulo o si el conductor ya llegó al sitio (ARRIVED)
    if (trip == null || trip.status == TripStatus.ARRIVED) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B2E).withValues(alpha: 0.9),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.2),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(
          Icons.navigation_rounded,
          color: AppColors.primaryGreen,
        ),
        iconSize: 28,
        onPressed: () {
          LatLng target = trip.status == TripStatus.STARTED
              ? trip.destinationLocation
              : trip.originLocation;
          _showExternalNavSheet(context, target);
        },
      ),
    );
  }

  // --- BOTÓN DE CENTRADO ADAPTATIVO (Muestra a ambos actores en pantalla) ---
  Widget _buildReCenterButton(HomeProvider provider) {
    return _buildPremiumButton(
      icon: Icons.my_location,
      onPressed: () {
        final LatLng? driverPos = provider.currentPosition;
        final LatLng? passengerPos = provider.passengerLocation;
        final trip = provider.activeTrip;

        // Si estamos esperando en el sitio, encuadra a ambos (Conductor + Pasajero)
        if (trip != null &&
            trip.status == TripStatus.ARRIVED &&
            driverPos != null &&
            passengerPos != null) {
          setState(() {
            _isTrackingDriver =
                false; // Desactivar seguimiento constante para permitir encuadre libre
          });
          _centerMapOnData(vehiclePos: driverPos, targetPos: passengerPos);
        } else if (driverPos != null) {
          setState(() {
            _isTrackingDriver = true;
          });
          _animatedMapMove(driverPos, 16.5);
        }
      },
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

    if (provider.activeTrip != null) {
      return const TripPanelSheet();
    }

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
          if (!provider.isOnline) _VehicleSelector(provider: provider),

          SizedBox(
            width: double.infinity,
            height: 65,
            child: ElevatedButton(
              onPressed: provider.isLoading
                  ? null
                  : () => provider.toggleOnlineStatus(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
              ),
              child: Text(
                provider.isOnline ? "TERMINAR TURNO" : "CONECTARSE AHORA",
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Calcula la compensación en píxeles verticales según el tamaño de la pantalla
  double _getVerticalOffset() {
    final screenHeight = MediaQuery.of(context).size.height;
    final provider = context.read<HomeProvider>();
    final trip = provider.activeTrip;

    if (trip != null) {
      if (trip.status == TripStatus.ACCEPTED ||
          trip.status == TripStatus.ARRIVED) {
        // Desplazar el centro de la cámara hacia abajo un 23% de la altura de la pantalla
        // proyecta el vehículo perfectamente en el centro de la mitad superior visible.
        return screenHeight * 0.23;
      }
    }
    return 0.0;
  }

  // Convierte la coordenada real del vehículo a una coordenada con offset para la cámara
  LatLng _getOffsetPosition(LatLng position, double zoom) {
    if (!_isMapReady) return position;
    try {
      final camera = _mapController.camera;
      final double offsetPixels = _getVerticalOffset();
      if (offsetPixels == 0.0) return position;

      // Proyecta la coordenada geográfica a píxeles del mapa según el zoom actual
      final point = camera.project(position, zoom);

      // Sumamos en Y (hacia abajo en el plano del mapa) para que la cámara enfoque más abajo,
      // lo cual empuja visualmente al vehículo hacia la parte superior de la pantalla.
      final shiftedPoint = math.Point(point.x, point.y + offsetPixels);

      // Desproyecta de regreso a coordenadas geográficas
      return camera.unproject(shiftedPoint, zoom);
    } catch (e) {
      debugPrint("Error calculando offset de cámara: $e");
      return position;
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
      body: Consumer<HomeProvider>(
        builder: (context, provider, _) {
          final trip = provider.activeTrip;

          // Si el viaje está en curso (STARTED), renderizamos la pantalla completa directamente
          // sin cargar el mapa para evitar consumo innecesario de la API de Mapbox
          if (trip != null && trip.status == TripStatus.STARTED) {
            // Aseguramos que la bandera del mapa pase a false al desmontarse para mayor protección
            if (_isMapReady) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _isMapReady = false);
              });
            }
            return _buildFullScreenDriverTripView(context, provider, trip);
          }

          final incoming = provider.incomingTrip;

          final pointsToDraw = provider.routePoints.isEmpty
              ? <LatLng>[]
              : (_animatedRoutePoints.isNotEmpty
                    ? _animatedRoutePoints
                    : provider.routePoints);

          final bool isArrived =
              trip != null && trip.status == TripStatus.ARRIVED;

          final LatLng? driverPos =
              _animatedPosition ?? provider.currentPosition;

          final LatLng? passengerPos =
              _animatedPassengerPosition ?? provider.passengerLocation;

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter:
                      provider.currentPosition ??
                      const LatLng(4.6097, -74.0817),
                  initialZoom: 16.0,

                  // MODIFICADO: Doble protección al estar listo el mapa
                  onMapReady: () {
                    setState(() => _isMapReady = true);

                    // Si al cargar el mapa ya contamos con GPS del conductor y no hay viaje, centramos inmediatamente
                    final currentPos = provider.currentPosition;
                    if (currentPos != null &&
                        trip == null &&
                        incoming == null) {
                      _mapController.move(currentPos, 16.5);
                    }
                  },

                  // BLOQUEO DE GESTOS: Si hay viaje entrante, desactivamos toda interacción
                  interactionOptions: InteractionOptions(
                    flags: incoming != null
                        ? InteractiveFlag.none
                        : InteractiveFlag.all,
                  ),
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture && _isTrackingDriver) {
                      setState(() {
                        _isTrackingDriver = false;
                      });
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://api.mapbox.com/styles/v1/mapbox/navigation-night-v1/tiles/{z}/{x}/{y}{r}?access_token=$myMapboxToken',
                    tileProvider: CachedTileProvider(),
                    retinaMode: true,
                  ),
                  if (pointsToDraw.isNotEmpty && incoming == null && !isArrived)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: pointsToDraw,
                          color: Colors.blueAccent,
                          strokeWidth: 5.0,
                        ),
                      ],
                    ),

                  if (isArrived && driverPos != null && passengerPos != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [driverPos, passengerPos],
                          color: Colors.blueAccent.withValues(
                            alpha: 0.6,
                          ), // Color más visible y estético
                          strokeWidth: 4.0,
                          pattern: const StrokePattern.dotted(),
                        ),
                      ],
                    ),

                  // MARCADORES
                  _MarkersLayer(
                    animatedPosition: _animatedPosition,
                    animatedHeading: _animatedHeading,
                    animatedPassengerPosition:
                        _animatedPassengerPosition, // Pasar la coordenada suavizada
                  ),
                ],
              ),
              if (trip == null && incoming == null) _buildMenuButton(),
              if (trip == null && incoming == null)
                _buildOnlineStatusIndicator(provider),

              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 20, bottom: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (trip != null) ...[
                            _buildWazeButton(provider),
                            const SizedBox(height: 12),
                          ],
                          // CONTROL DE VISIBILIDAD: Solo muestra el botón si no estamos en tracking,
                          // hay posición y NO hay un viaje entrante.
                          if (!_isTrackingDriver &&
                              provider.currentPosition != null &&
                              incoming == null)
                            _buildReCenterButton(provider),
                        ],
                      ),
                    ),
                    _buildPanelContent(context, provider),
                  ],
                ),
              ),
            ],
          );
        },
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
  final LatLng? animatedPosition;
  final double animatedHeading;
  final LatLng? animatedPassengerPosition; // Agregado

  const _MarkersLayer({
    required this.animatedPosition,
    required this.animatedHeading,
    this.animatedPassengerPosition,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        final trip = provider.activeTrip;

        final LatLng? posToDraw = animatedPosition ?? provider.currentPosition;
        final double headingToDraw = animatedPosition != null
            ? animatedHeading
            : provider.currentHeading;

        // Si tenemos posición suavizada la usamos, sino recurrimos al fallback del proveedor
        final LatLng? passengerPosToDraw =
            animatedPassengerPosition ?? provider.passengerLocation;

        if (trip == null ||
            (trip.status != TripStatus.ACCEPTED &&
                trip.status != TripStatus.ARRIVED) ||
            passengerPosToDraw == null) {
          return MarkerLayer(
            markers: [
              if (posToDraw != null)
                _buildDriverMarker(posToDraw, headingToDraw),
            ],
          );
        }

        // Caso B: Renderizado directo y eficiente con coordenadas animadas unificadas
        // Caso B: Renderizado directo y eficiente con coordenadas animadas unificadas
        return MarkerLayer(
          markers: [
            // 1. Vehículo del conductor
            if (posToDraw != null) _buildDriverMarker(posToDraw, headingToDraw),

            // 2. PIN de recogida estático (Verde) - OCULTAR SI ESTÁ EN EL SITIO
            if (trip.status != TripStatus.ARRIVED)
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

            // 3. Ubicación del pasajero suavizada (Azul)
            Marker(
              point: passengerPosToDraw,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Marker _buildDriverMarker(LatLng pos, double heading) {
    return Marker(
      point: pos,
      width: 60,
      height: 60,
      child: Transform.rotate(
        angle: (heading * math.pi / 180),
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
          child: Image.asset('assets/images/car.png', width: 40, height: 40),
        ),
      ),
    );
  }
}
