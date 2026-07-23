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
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/utils/cached_tile_provider.dart';
import 'dart:io'; // <--- Permite usar el tipo 'File' para la foto tomada
import 'package:image_picker/image_picker.dart'; // <--- Permite abrir la cámara nativa del teléfono
// ... Asegúrese de tener estas importaciones al inicio del archivo ...
import 'dart:async'; // 🟢 Requerido para StreamSubscription
import 'package:cached_network_image/cached_network_image.dart'; // 🟢 AGREGAR ESTA IMPORTACIÓN
import 'package:intl/intl.dart'; // 🟢 Importación agregada para usar DateFormat
import 'package:flutter/services.dart'; // 🟢 NUEVA IMPORTACIÓN PARA MINIMIZAR LA APP
import '../services/location_service.dart';
import '../widgets/payment_waiting_sheet.dart';

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
  final TextEditingController _pinController = TextEditingController();
  bool _isPanelMinimized = false;

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
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 🟢 Agrega esta llamada aquí antes de iniciar el GPS:
      _checkAndForcePermissions();
      context.read<HomeProvider>().initLocation();
      context.read<WalletProvider>().loadWalletData();
      context.read<HomeProvider>().addListener(_onTripStateChanged);
    });
  }

  // 🟢 NUEVO MÉTODO: Sincroniza el estado del turno cuando el conductor regresa a la app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint(
        "📡 [Lifecycle] Conductor regresó a la app. Re-sincronizando estado completo...",
      );
      // 🚀 Llama al método del Provider que sincroniza tanto el turno como el viaje en background
      context.read<HomeProvider>().recargarEstadoCompleto();
    }
  }

  Future<void> _checkAndForcePermissions() async {
    final locationService = LocationService();
    bool hasPermissions = await locationService.checkPermissions();

    if (!hasPermissions && mounted) {
      _showPermissionExplanationDialog();
    }
  }

  void _showPermissionExplanationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Evita que se cierre tocando fuera
      builder: (ctx) => PopScope(
        canPop: false, // Bloquea el botón físico "atrás" de Android
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: const Color(
            0xFF161B2E,
          ), // Fondo pizarra premium a juego
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      // ignore: deprecated_member_use
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.security_rounded,
                      color: Colors.redAccent,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "CONFIGURACIÓN REQUERIDA",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Para poder recibir viajes y navegar, VAMOS requiere el acceso obligatorio a dos configuraciones críticas del sistema:\n\n"
                  "1. Ubicación 'Permitir Siempre': Para rastrear tu ruta y ubicación en tiempo real cuando tengas la pantalla bloqueada.\n"
                  "2. Optimización de Batería 'Sin Restricciones': Evita que el celular pause o bloquee el GPS de fondo para ahorrar batería.\n\n"
                  "Sin otorgar ambas configuraciones, la aplicación no funcionará correctamente.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF94A3B8),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(
                        ctx,
                      ); // Cierra temporalmente para evitar modales encimados
                      final locationService = LocationService();
                      bool success = await locationService.checkPermissions();
                      if (success) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "¡Configuraciones autorizadas con éxito!",
                              ),
                              backgroundColor: AppColors.primaryGreen,
                            ),
                          );
                          // Re-inicializamos el servicio de GPS en el Provider
                          context.read<HomeProvider>().initLocation();
                        }
                      } else {
                        // Bucle de persistencia: Reabre si no se autorizaron
                        if (mounted) {
                          _showPermissionExplanationDialog();
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      "OTORGAR ACCESOS",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onTripStateChanged() {
    if (!mounted) return;

    final provider = context.read<HomeProvider>();
    if (provider.hasPendingLateAlert && provider.lateTrip != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showLateAlertDialog(context, provider);
        }
      });
    }
    // 🚀 NUEVA ESCUCHA: Levanta el Pop-up interactivo al llegar a cero
    if (provider.hasPendingWaitingDecision && provider.activeTrip != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showWaitingDecisionDialog(context, provider);
        }
      });
    }
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
          });
        });

        _markerAnimationController!.forward();
        if (_isTrackingDriver && _isMapReady) {
          final double currentZoom = _mapController.camera.zoom;
          final LatLng offsetCenter = _getOffsetPosition(newPos, currentZoom);

          // 🟢 CORREGIDO: Usamos move() directo para el auto-seguimiento continuo.
          // Esto evita que se saturen los Tickers/Animaciones simultáneamente en el hilo principal.
          _mapController.move(offsetCenter, currentZoom);
        }
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
      // 🟢 OPTIMIZACIÓN DE CÁMERA:
      // Durante la oferta entrante, no alejamos el mapa con zoom gigante.
      // Enfocamos de cerca al conductor (zoom 16.5) para que no haya saltos erráticos en la UI.
      if (provider.currentPosition != null && _isMapReady) {
        final double currentZoom = 16.5;
        final LatLng offsetCenter = _getOffsetPosition(
          provider.currentPosition!,
          currentZoom,
        );
        _animatedMapMove(offsetCenter, currentZoom);
      }
    } else if (trip != null) {
      // 🟢 OPTIMIZACIÓN: Solo auto-encuadramos rutas de recogida o llegada
      // si el conductor NO tiene el enganche de cámara permanente activo.
      if (!_isTrackingDriver) {
        if (trip.status == TripStatus.ARRIVED) {
          _centerMapOnData(
            vehiclePos: provider.currentPosition,
            targetPos: provider.passengerLocation,
          );
        } else if (provider.routePoints.isNotEmpty &&
            _animatedPosition == null) {
          LatLng target = trip.status == TripStatus.ACCEPTED
              ? trip.originLocation
              : trip.destinationLocation;
          _animatedMapMove(target, 15.5);
        }
      }
    }
  }

  void _showWaitingDecisionDialog(BuildContext context, HomeProvider provider) {
    provider.dismissWaitingDecision(); // Cierra el gatillo para evitar loops

    showDialog(
      context: context,
      barrierDismissible:
          false, // Obliga al conductor a elegir una de las dos opciones
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: const Color(
          0xFF161B2E,
        ), // Fondo pizarra profunda de su interfaz
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    // ignore: deprecated_member_use
                    color: Colors.amber.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.timer_off_rounded,
                    color: Colors.amberAccent,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "TIEMPO EXPIRO",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "El pasajero superó los 5 minutos de cortesía en el sitio. ¿Deseas seguir esperando (se cobrará tiempo extra) o cancelar por inasistencia?",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF94A3B8),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              // Botón Aceptar Esperar (Cierra el modal y deja corriendo el cronómetro)
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    "SEGUIR ESPERANDO",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Botón Cancelar (Aplica multa al usuario en BD y libera al conductor)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  provider.cancelCurrentTrip(
                    context,
                  ); // Llama al método de cancelación asíncrono
                },
                child: Text(
                  "CANCELAR (COBRAR INASISTENCIA)",
                  style: GoogleFonts.montserrat(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⏰ ALERTA VISUAL AVANZADA: Diálogo con información completa e inicio directo de ruta
  void _showLateAlertDialog(BuildContext context, HomeProvider provider) {
    final trip = provider.lateTrip;
    if (trip == null) return;

    // Reseteamos el estado en el provider para que la alerta no se vuelva a gatillar
    provider.dismissLateAlert();

    final String horaSalida = trip.scheduledAt != null
        ? DateFormat('hh:mm a').format(trip.scheduledAt!.toLocal())
        : "Acordada";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: const Color(0xFF161B2E), // Fondo pizarra premium
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. HEADER: Icono decorativo centrado de alerta
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amberAccent,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Título
              Text(
                "¡ESTÁS RETRASADO!",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),

              // Mensaje descriptivo
              Text(
                "Tu viaje programado para las $horaSalida ya debió haber iniciado. Por favor, inicia la ruta o contacta al pasajero de inmediato.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: const Color(0xFF94A3B8), // Gris suave muy legible
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),

              // 2. DETALLE DEL VIAJE (Ficha con iconos de Timeline)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(
                    0xFF0B0F19,
                  ), // Fondo oscuro para aislar la información
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Column(
                  children: [
                    _buildLateAlertDetailRow(
                      Icons.person_rounded,
                      "Pasajero",
                      trip.passengerName,
                      Colors.blueAccent,
                    ),
                    const SizedBox(height: 12),
                    _buildLateAlertDetailRow(
                      Icons.radio_button_checked_rounded,
                      "Recogida",
                      trip.originAddress,
                      AppColors.primaryGreen,
                    ),
                    const SizedBox(height: 12),
                    _buildLateAlertDetailRow(
                      Icons.location_on_rounded,
                      "Destino",
                      trip.destinationAddress,
                      Colors.redAccent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // 3. ACCIONES PRINCIPALES (Botonera Premium)
              // 3. ACCIONES PRINCIPALES (Botonera Premium protegida)
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      // 🟢 Ejecutamos de forma segura la ruta de encuentro
                      bool exito = await provider.iniciarRutaAlOrigenConViaje(
                        trip,
                      );
                      if (exito && ctx.mounted) {
                        Navigator.pop(ctx); // Cierra el diálogo de alerta
                      }
                    } catch (e) {
                      // Si falla por validaciones del backend, cerramos el diálogo y alertamos con SnackBar
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              e.toString().replaceAll("Exception: ", ""),
                              style: GoogleFonts.montserrat(
                                fontWeight: FontWeight.bold,
                              ),
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
                    elevation: 0,
                  ),
                  child: Text(
                    "IR AL ENCUENTRO",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        "CERRAR",
                        style: GoogleFonts.montserrat(
                          color: Colors.grey[500],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        if (trip.passengerPhone != null &&
                            trip.passengerPhone!.isNotEmpty) {
                          final Uri whatsappUri = Uri.parse(
                            "https://wa.me/${trip.passengerPhone!.replaceAll(RegExp(r'[^0-9]'), '')}",
                          );
                          if (await canLaunchUrl(whatsappUri)) {
                            await launchUrl(
                              whatsappUri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        }
                      },
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 16,
                        color: Colors.orangeAccent,
                      ),
                      label: Text(
                        "CONTACTAR",
                        style: GoogleFonts.montserrat(
                          color: Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
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

  // Método helper de soporte para estructurar las filas del diálogo
  Widget _buildLateAlertDetailRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.montserrat(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[500],
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
    _pinController.dispose();
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

  Future<void> _launchExternalMap(
    String app,
    LatLng origin,
    LatLng destination,
    List<Map<String, dynamic>> stops,
  ) async {
    Uri uri;
    if (app == 'google') {
      if (stops.isNotEmpty) {
        // 🟢 GOOGLE MAPS MULTIPUNTO: Estructuramos origen, paradas (waypoints) y destino final
        final String originStr = "${origin.latitude},${origin.longitude}";
        final String destStr =
            "${destination.latitude},${destination.longitude}";
        final String waypointsStr = stops
            .map((s) => "${s['lat']},${s['lng']}")
            .join('|');

        uri = Uri.parse(
          "https://www.google.com/maps/dir/?api=1&origin=$originStr&destination=$destStr&waypoints=$waypointsStr&travelmode=driving",
        );
      } else {
        uri = Uri.parse(
          "google.navigation:q=${destination.latitude},${destination.longitude}",
        );
        if (!await canLaunchUrl(uri)) {
          uri = Uri.parse(
            "https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}",
          );
        }
      }
    } else {
      // 🟢 WAZE TRAMO POR TRAMO: Si hay paradas intermedias, lo guía primero a la parada más cercana, de lo contrario al destino
      final LatLng target = stops.isNotEmpty
          ? LatLng(
              stops.first['lat']?.toDouble() ?? 0.0,
              stops.first['lng']?.toDouble() ?? 0.0,
            )
          : destination;

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

  void _showExternalNavSheet(
    BuildContext context,
    LatLng origin,
    LatLng target,
    List<Map<String, dynamic>> stops,
  ) {
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
                        _launchExternalMap('google', origin, target, stops);
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
                        _launchExternalMap('waze', origin, target, stops);
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
    final List paradas = trip.desglosePrecio?['paradas'] ?? [];

    return Column(
      children: [
        // 1. Origen
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
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        // 2. Paradas Intermedias (si existen)
        if (paradas.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 2, height: 12, color: Colors.white24),
            ),
          ),
          ...paradas.map((p) {
            final String dir = p['direccion'] ?? 'Parada intermedia';
            return Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.adjust_rounded,
                      size: 16,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        dir,
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
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 7),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 2,
                      height: 12,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ],
            );
          }),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(width: 2, height: 16, color: Colors.white24),
            ),
          ),
        ],

        // 3. Destino Final
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
                  color: Colors.white,
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

  List<List<LatLng>> _splitRoutePoints(
    List<LatLng> points,
    List<Map<String, dynamic>> stops,
  ) {
    if (points.isEmpty) return [];
    if (stops.isEmpty) return [points];

    List<List<LatLng>> segments = [];
    int lastIndex = 0;

    for (var stop in stops) {
      final double? stopLat = double.tryParse(stop['lat']?.toString() ?? '');
      final double? stopLng = double.tryParse(stop['lng']?.toString() ?? '');
      if (stopLat == null || stopLng == null) continue;

      final stopLatLng = LatLng(stopLat, stopLng);
      int closestIndex = lastIndex;
      double minDistance = double.infinity;

      for (int i = lastIndex; i < points.length; i++) {
        double dist = Geolocator.distanceBetween(
          points[i].latitude,
          points[i].longitude,
          stopLatLng.latitude,
          stopLatLng.longitude,
        );
        if (dist < minDistance) {
          minDistance = dist;
          closestIndex = i;
        }
      }

      if (closestIndex > lastIndex) {
        segments.add(points.sublist(lastIndex, closestIndex + 1));
        lastIndex = closestIndex;
      }
    }

    if (lastIndex < points.length) {
      segments.add(points.sublist(lastIndex));
    }

    return segments;
  }

  // 🟢 AGREGAR ESTE MÉTODO AQUÍ ADENTRO DE _HomeScreenState:
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

  /// Abre el selector de imagen según el origen (Cámara o Galería)
  Future<File?> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: source,
        imageQuality: 50, // Comprime al 50% para ahorrar datos móviles
      );
      if (photo != null) {
        return File(photo.path);
      }
    } catch (e) {
      debugPrint("Error al seleccionar imagen: $e");
    }
    return null;
  }

  /// Muestra un diálogo elegante para elegir entre Galería (screenshots) o Cámara
  Future<File?> _showImageSourceDialog(BuildContext context) async {
    return showDialog<File?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Seleccionar Comprobante",
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: AppColors.primaryGreen,
              ),
              title: const Text(
                "Galería (Capturas de pantalla)",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                final file = await _pickImage(
                  ImageSource.gallery,
                ); // 🟢 Permite subir capturas
                if (ctx.mounted) Navigator.pop(ctx, file);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: AppColors.primaryGreen,
              ),
              title: const Text(
                "Cámara",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () async {
                final file = await _pickImage(ImageSource.camera);
                if (ctx.mounted) Navigator.pop(ctx, file);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- INTERFAZ COMPLETA PARA EL CONDUCTOR (VIAJE EN CURSO) ---
  Widget _buildFullScreenDriverTripView(
    BuildContext context,
    HomeProvider provider,
    Trip trip,
  ) {
    final primaryColor = AppColors.primaryGreen;
    // 🟢 SOLUCIÓN: El precio de viaje en curso del conductor muestra el valor neto real a cobrar (con descuento)
    final String formattedPrice =
        "\$${trip.passengerCashToPay.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}";
    return Container(
      color: AppColors.darkBlue,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===============================================================
              // BANNERS DE ALERTA EN PANTALLA COMPLETA
              // ===============================================================
              if (provider.isNetworkDisconnected ||
                  provider.isGpsSignalLost) ...[
                if (provider.isNetworkDisconnected)
                  _buildStatusBanner(
                    icon: Icons.cloud_off_rounded,
                    message:
                        "Sin conexión a internet. Intentando reconectar...",
                    backgroundColor: Colors.redAccent,
                  ),
                if (provider.isGpsSignalLost && !provider.isNetworkDisconnected)
                  _buildStatusBanner(
                    icon: Icons.gps_off_rounded,
                    message: "Señal de GPS débil o inestable.",
                    backgroundColor: Colors.orangeAccent,
                  ),
                const SizedBox(height: 12),
              ],

              // ÁREA CENTRAL REDISEÑADA CON LOGO Y ESTADO DE CONEXIÓN (Sin distancias ni tiempos estimados)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logotipo de la aplicación
                      Image.asset(
                        'assets/images/logo.png',
                        height: 180,
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
                            "VALOR ESTIMADO: $formattedPrice COP", // 🚀 Mostrar precio en viaje en curso para el conductor
                            style: GoogleFonts.montserrat(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            "Comisión descontada de tu billetera",
                            style: GoogleFonts.montserrat(
                              color: Colors.grey[400],
                              fontSize: 10,
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
                            : "https://api.vamosapp.com.co/api/viajes/${trip.id}/fuec/pdf-interno"; // <-- Corregido aquí
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
                    // Pasajero Principal con Foto Dinámica en Caché
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
                            // Sincronizado con CachedNetworkImageProvider para persistencia offline
                            backgroundImage:
                                (trip.passengerPhotoUrl != null &&
                                    trip.passengerPhotoUrl!.isNotEmpty)
                                ? CachedNetworkImageProvider(
                                    trip.passengerPhotoUrl!,
                                  )
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
                                _animatedPosition ??
                                    provider.currentPosition ??
                                    const LatLng(0.0, 0.0),
                                trip.destinationLocation,
                                List<Map<String, dynamic>>.from(
                                  trip.desglosePrecio?['paradas'] ?? [],
                                ),
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

                  // 🟢 NUEVO: BOTÓN DE CANCELACIÓN EN VISTA DE VIAJE EMPEZADO (STARTED)
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmCancel(context, provider),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.redAccent,
                      ),
                      label: Text(
                        "CANCELAR VIAJE",
                        style: GoogleFonts.montserrat(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 1.1,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: Colors.redAccent,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: Colors.red.withValues(alpha: 0.02),
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

          _showExternalNavSheet(
            context,
            _animatedPosition ??
                provider.currentPosition ??
                const LatLng(0.0, 0.0),
            target,
            List<Map<String, dynamic>>.from(
              trip.desglosePrecio?['paradas'] ?? [],
            ),
          );
        },
      ),
    );
  }

  // --- BOTÓN DE CENTRADO CONSTANTE (Enfocado en el Conductor con offset inteligente) ---
  Widget _buildReCenterButton(HomeProvider provider) {
    return _buildPremiumButton(
      icon: Icons.my_location,
      onPressed: () {
        final LatLng? driverPos = provider.currentPosition;
        if (driverPos != null) {
          setState(() {
            // Activamos el seguimiento permanente de la cámara en el mapa
            _isTrackingDriver = true;
          });
          final double currentZoom = _mapController.camera.zoom;

          // 🟢 CORREGIDO: Pasamos la coordenada pura (driverPos).
          // _animatedMapMove() se encargará de aplicarle el offset de manera limpia una sola vez.
          _animatedMapMove(driverPos, currentZoom);
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
    Color indicatorColor;
    String statusText;

    switch (provider.turnoEstado) {
      case 'ACTIVO':
        indicatorColor = AppColors.primaryGreen; // Verde para activo
        statusText = "EN LÍNEA";
        break;
      case 'BREAK':
        indicatorColor = Colors.orangeAccent; // Naranja para descanso
        statusText = "EN BREAK";
        break;
      default:
        indicatorColor = Colors.redAccent; // Rojo para desconectado
        statusText = "DESCONECTADO";
    }

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
                  color: indicatorColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                statusText,
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

  Widget _buildMinimizedPanel(Trip trip) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B2E).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.navigation_rounded,
              color: AppColors.primaryGreen,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "En camino",
                  style: GoogleFonts.montserrat(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  trip.passengerName,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 🟢 BOTÓN EN REEPLAZO: Contenedor táctil inmune a desbordes de temas globales de Android
          InkWell(
            onTap: () {
              setState(() {
                _isPanelMinimized = false;
              });
            },
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                "VER",
                style: GoogleFonts.montserrat(
                  color: Colors.white,
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

  Widget _buildPanelContent(BuildContext context, HomeProvider provider) {
    if (provider.incomingTrip != null) {
      return TripRequestSheet(
        trip: provider.incomingTrip!,
        onAccept: () => provider.acceptIncomingTrip(),
        onReject: () => provider.rejectIncomingTrip(),
      );
    }

    if (provider.activeTrip != null) {
      final trip = provider.activeTrip!;
      final String statusStr = trip.status.toString();

      // 1. Viaje programado asignado en espera
      if (statusStr.contains('SCHEDULED_ASSIGNED')) {
        return _buildScheduledAssignedSheet(context, provider);
      }

      // 2. Si es Yendo al Encuentro (ACCEPTED) y el conductor decidió colapsarlo
      if (trip.status == TripStatus.ACCEPTED && _isPanelMinimized) {
        return _buildMinimizedPanel(trip);
      }

      // 3. Conductor llegó al sitio (ARRIVED) - Requiere PIN si es programado
      if (statusStr.contains('ARRIVED')) {
        // Al llegar al sitio, forzamos que el panel se expanda automáticamente
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isPanelMinimized) {
            setState(() => _isPanelMinimized = false);
          }
        });

        if (provider.isActiveTripScheduled) {
          return _buildPinActivationSheet(context, provider);
        } else {
          return TripPanelSheet(
            onMinimize: () => setState(() => _isPanelMinimized = true),
          );
        }
      }

      // Por defecto, mandamos la función de colapsar al panel de viaje general
      return TripPanelSheet(
        onMinimize: () => setState(() => _isPanelMinimized = true),
      );
    }

    // Panel de control de turnos en tiempo real
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
          // 1. Selector de vehículo: Solo se muestra si está OFFLINE
          if (provider.turnoEstado == 'OFFLINE') ...[
            _VehicleSelector(provider: provider),
            const SizedBox(height: 12),
          ],

          // 2. ESTADO: OFFLINE (El conductor debe iniciar el turno)
          if (provider.turnoEstado == 'OFFLINE') ...[
            SizedBox(
              width: double.infinity,
              height: 65,
              child: ElevatedButton(
                onPressed: provider.isLoading
                    ? null
                    : () {
                        _showShiftFormModal(
                          context: context,
                          provider: provider,
                          isStarting:
                              true, // Iniciar turno con kilometraje y foto
                        );
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                ),
                child: provider.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        "CONECTARSE AHORA",
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],

          // 🟢 BOTONERA ACTUALIZADA Y RESPONSIVA (SOPORTA PANTALLAS PEQUEÑAS)
          if (provider.turnoEstado == 'ACTIVO') ...[
            Row(
              children: [
                // Botón de Break de 15 min
                Expanded(
                  child: SizedBox(
                    height: 55,
                    child: OutlinedButton.icon(
                      onPressed: provider.isLoading
                          ? null
                          : () => provider.iniciarBreak(),
                      icon: const Icon(
                        Icons.coffee_rounded,
                        color: AppColors.primaryGreen,
                        size: 16, // Reducido un píxel para ganar espacio
                      ),
                      label: FittedBox(
                        // 🟢 CORREGIDO: Evita desbordes y wraps feos
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "BREAK",
                          style: GoogleFonts.montserrat(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(
                          color: AppColors.primaryGreen,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ), // Margen interno responsivo
                      ),
                    ),
                  ),
                ),

                if (!provider.alreadyHadLunch) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 55,
                      child: OutlinedButton.icon(
                        onPressed: provider.isLoading
                            ? null
                            : () async {
                                final err = await provider.iniciarAlmuerzo();
                                if (err != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("❌ $err"),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              },
                        icon: const Icon(
                          Icons.restaurant,
                          color: Colors.blueAccent,
                          size: 16, // Reducido para espacio
                        ),
                        label: FittedBox(
                          // 🟢 CORREGIDO: El texto "ALMUERZO" ya no saltará de línea
                          fit: BoxFit.scaleDown,
                          child: Text(
                            "ALMUERZO",
                            style: GoogleFonts.montserrat(
                              color: Colors.blueAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Colors.blueAccent,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),

                // Botón para Terminar Turno (Cerrar)
                Expanded(
                  child: SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      onPressed: provider.isLoading
                          ? null
                          : () {
                              _showShiftFormModal(
                                context: context,
                                provider: provider,
                                isStarting: false,
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: FittedBox(
                        // 🟢 CORREGIDO: Evitamos desbordes en 'CERRAR'
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "CERRAR",
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          // 🟢 MEJORA ESTADO ALMUERZO: Solo se muestra el botón ancho para Volver al Turno
          if (provider.turnoEstado == 'ALMUERZO') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.blueAccent.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.restaurant,
                    color: Colors.blueAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Fin de almuerzo en: ",
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    provider.lunchTimerFormated,
                    style: GoogleFonts.montserrat(
                      color: Colors.blueAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: provider.isLoading
                    ? null
                    : () => provider.reanudarTurnoCompleto(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  "VOLVER AL TURNO (REANUDAR)",
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],

          // 🟢 MEJORA ESTADO BREAK: Solo se muestra el botón ancho para Volver al Turno
          if (provider.turnoEstado == 'BREAK') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.orangeAccent.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.hourglass_bottom_rounded,
                    color: Colors.orangeAccent,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Fin de break en: ",
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    provider.breakTimerFormated,
                    style: GoogleFonts.montserrat(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: provider.isLoading
                    ? null
                    : () async {
                        final error = await provider.reanudarTurnoCompleto();
                        if (error != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("❌ $error"),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  "VOLVER AL TURNO (REANUDAR)",
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 🟢 NUEVO: Tarjeta que se le muestra al conductor cuando tiene un viaje programado asignado en espera (Con desglose de peajes)
  Widget _buildScheduledAssignedSheet(
    BuildContext context,
    HomeProvider provider,
  ) {
    final trip = provider.activeTrip!;

    // Lectura segura de peajes desde el modelo
    final double totalPeajes = (trip.desglosePrecio?['total_peajes'] ?? 0.0)
        .toDouble();
    final int numPeajes =
        (trip.desglosePrecio?['peajes_detalles'] as List? ?? []).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(25, 25, 25, 35),
      decoration: BoxDecoration(
        color: const Color(0xFF161B2E).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "VIAJE PROGRAMADO ASIGNADO",
                style: GoogleFonts.montserrat(
                  color: AppColors.primaryGreen,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.2,
                ),
              ),
              const Icon(
                Icons.event_available,
                color: Colors.white70,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            trip.passengerName,
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),

          _buildAddressesTimelineView(trip),

          // 🟢 NUEVO: INDICADOR DE PEAJES DEL VIAJE PROGRAMADO
          if (totalPeajes > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orangeAccent.withValues(alpha: 0.25),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.toll_rounded,
                    color: Colors.orangeAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "Peajes del viaje ($numPeajes):",
                    style: GoogleFonts.montserrat(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "\$${totalPeajes.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}",
                    style: GoogleFonts.montserrat(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 25),

          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: provider.isLoading
                  ? null
                  : () => provider.iniciarRutaAlOrigen(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
              ),
              child: provider.isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      "IR AL ENCUENTRO (INICIAR RUTA)",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // 🟢 NUEVA VERSIÓN: Incluye contador de espera y botón de gracia +3 minutos
  Widget _buildPinActivationSheet(BuildContext context, HomeProvider provider) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        25,
        20,
        25,
        MediaQuery.of(context).viewInsets.bottom + 30,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF161B2E).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(35)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Indicador de arrastre
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          Text(
            "ACTIVACIÓN DE VIAJE",
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),

          Text(
            "Solicita al pasajero el PIN de inicio de 6 dígitos que llegó a su correo o app para poner en marcha el servicio.",
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: Colors.grey[400],
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // ===================================================================
          // 🟢 NUEVO: CONTADOR DE TIEMPO DE ESPERA DINÁMICO EN EL INGRESO DE PIN
          // ===================================================================
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
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

          // 🟢 NUEVO: BOTÓN DE GRACIA +3 MINUTOS (Solo si aún no expiran los 5 mins de cortesía)
          if (provider.waitSeconds > 0) ...[
            const SizedBox(height: 12),
            _buildExtraWaitingTimeButton(context, provider),
          ],

          const SizedBox(height: 20),

          // CAMPO DE TEXTO PARA EL PIN
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              counterText: "",
              hintText: "000000",
              hintStyle: const TextStyle(
                color: Colors.white24,
                letterSpacing: 8,
              ),
              filled: true,
              fillColor: const Color(0xFF0B0F19),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(
                  color: AppColors.primaryGreen,
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // BOTÓN DE VERIFICACIÓN
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: provider.isLoading
                  ? null
                  : () async {
                      final pin = _pinController.text.trim();
                      if (pin.length != 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("⚠️ El PIN debe ser de 6 dígitos"),
                          ),
                        );
                        return;
                      }

                      try {
                        bool exito = await provider.activarViajeProgramado(pin);
                        if (exito && context.mounted) {
                          _pinController.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "🟢 ¡Viaje activado! Iniciando ruta de recogida...",
                              ),
                              backgroundColor: AppColors.primaryGreen,
                            ),
                          );
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("❌ PIN incorrecto o expirado."),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceAll("Exception: ", ""),
                              ),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
              ),
              child: provider.isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      "VERIFICAR Y ACTIVAR",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================================
  // 🟢 METODOS DE SOPORTE PARA TIEMPO DE ESPERA (Colocar aquí al final de _HomeScreenState)
  // ===================================================================
  String _formatWaitTime(int seconds) {
    final int mins = seconds ~/ 60;
    final int secs = seconds % 60;
    return "$mins:${secs.toString().padLeft(2, '0')}";
  }

  Widget _buildExtraWaitingTimeButton(
    BuildContext context,
    HomeProvider provider,
  ) {
    final bool yaAgregado = provider.extraWaitingTimeAdded;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: yaAgregado
            ? null
            : () async {
                try {
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: yaAgregado
              // ignore: deprecated_member_use
              ? Colors.white.withOpacity(0.02)
              // ignore: deprecated_member_use
              : Colors.amber.withOpacity(0.05),
        ),
      ),
    );
  }

  // --- MEJORA: Centrado dinámico adaptativo según el estado de apertura/minimizado del panel ---
  double _getVerticalOffset() {
    final screenHeight = MediaQuery.of(context).size.height;
    final provider = context.read<HomeProvider>();
    final trip = provider.activeTrip;

    // Si hay un viaje activo y el panel NO está minimizado (está abierto en pantalla),
    // aplicamos un pequeño offset seguro del 11% para subir el auto y que no quede oculto bajo la tarjeta.
    if (trip != null && !_isPanelMinimized) {
      return screenHeight * 0.11;
    }

    // Si el panel está colapsado (minimizado) o no hay viaje activo, centramos al auto perfectamente en el medio
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

    // Leemos la ubicación inicial solo una vez al renderizar por primera vez
    final homeProvider = context.read<HomeProvider>();
    final LatLng initialCenter =
        homeProvider.currentPosition ?? const LatLng(4.6097, -74.0817);

    // 🟢 ENVOLVEMOS EL RETORNO EN UN POPSCOPE DE SEGURIDAD
    return PopScope(
      canPop:
          false, // Bloquea el cierre automático de la pantalla para evitar volver a WelcomeScreen
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;

        final provider = context.read<HomeProvider>();

        // ESCUDO: Si el conductor tiene un viaje en curso, evitamos que salga por accidente
        if (provider.activeTrip != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "⚠️ Tienes un servicio activo en curso. No puedes salir en este momento.",
                style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        // Si no hay viaje activo, minimiza la aplicación limpiamente a segundo plano
        // sin alterar el token ni destruir el estado de autenticación.
        SystemNavigator.pop();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const SideMenu(),
        body: Stack(
          children: [
            // ... Mantiene todo tu contenido exactamente igual ...
            // ===================================================================
            // 1. EL MAPA Y LAS CAPAS ESTÁTICAS (No se reconstruyen nunca al mover el GPS)
            // ===================================================================
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 16.0,
                onMapReady: () {
                  setState(() => _isMapReady = true);
                  final currentPos = context
                      .read<HomeProvider>()
                      .currentPosition;
                  if (currentPos != null &&
                      context.read<HomeProvider>().activeTrip == null &&
                      context.read<HomeProvider>().incomingTrip == null) {
                    _mapController.move(currentPos, 16.5);
                  }
                },
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
                      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  tileProvider: CachedTileProvider(),
                  retinaMode: true,
                  maxNativeZoom: 18,
                  minNativeZoom: 10,
                  keepBuffer: 1,
                  panBuffer: 0,
                  tileBuilder: (context, tileWidget, tile) {
                    return ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        2.2,
                        0.0,
                        0.0,
                        0.0,
                        35.0,
                        0.0,
                        2.2,
                        0.0,
                        0.0,
                        35.0,
                        0.0,
                        0.0,
                        2.2,
                        0.0,
                        35.0,
                        0.0,
                        0.0,
                        0.0,
                        1.0,
                        0.0,
                      ]),
                      child: tileWidget,
                    );
                  },
                ),

                // CAPA DE POLILÍNEAS OPTIMIZADA (Solo se reconstruye si cambian las rutas)
                Consumer<HomeProvider>(
                  builder: (context, provider, _) {
                    final trip = provider.activeTrip;
                    final incoming = provider.incomingTrip;
                    final bool isArrived =
                        trip != null && trip.status == TripStatus.ARRIVED;

                    final pointsToDraw = provider.routePoints.isEmpty
                        ? <LatLng>[]
                        : (_animatedRoutePoints.isNotEmpty
                              ? _animatedRoutePoints
                              : provider.routePoints);

                    if (pointsToDraw.isNotEmpty &&
                        incoming == null &&
                        !isArrived) {
                      // Extraemos paradas
                      final List<Map<String, dynamic>> stops = [];

                      // 🟢 CORRECCIÓN CRÍTICA: Solo cargamos paradas intermedias en la fase EN CURSO (STARTED).
                      // Durante la aproximación al origen (ACCEPTED) NO se debe segmentar la polilínea.
                      if (trip != null &&
                          trip.status == TripStatus.STARTED &&
                          trip.desglosePrecio != null &&
                          trip.desglosePrecio!['paradas'] != null) {
                        stops.addAll(
                          List<Map<String, dynamic>>.from(
                            trip.desglosePrecio!['paradas'],
                          ),
                        );
                      }

                      // 🟢 Segmentamos la ruta del conductor
                      final List<List<LatLng>> segments = _splitRoutePoints(
                        pointsToDraw,
                        stops,
                      );

                      final List<Polyline> polylinesToDraw = [];

                      for (int i = 0; i < segments.length; i++) {
                        final bool isLastSegment = (i == segments.length - 1);
                        polylinesToDraw.add(
                          Polyline(
                            points: segments[i],
                            strokeWidth: 5.0,
                            // 🟢 Sincronizado: Naranja para paradas, Azul para el destino en conductor
                            color: isLastSegment
                                ? Colors.blueAccent
                                : Colors.deepOrangeAccent,
                          ),
                        );
                      }

                      return PolylineLayer(polylines: polylinesToDraw);
                    }

                    return const SizedBox.shrink();
                  },
                ),

                // CAPA DE MARCADORES OPTIMIZADA (Usa su propio Consumer interno)
                _MarkersLayer(
                  animatedPosition: _animatedPosition,
                  animatedHeading: _animatedHeading,
                  animatedPassengerPosition: _animatedPassengerPosition,
                ),
              ],
            ),

            // ===================================================================
            // 2. CAPAS SUPERIORES E INTERFAZ (Se reconstruyen de forma aislada)
            // ===================================================================
            Consumer<HomeProvider>(
              builder: (context, provider, _) {
                final trip = provider.activeTrip;
                final incoming = provider.incomingTrip;

                // 🟢 RE-ESTABLECIDO: SI EL VIAJE ESTÁ EN CURSO (STARTED), MOSTRAR VISTA SIN MAPA
                if (trip != null && trip.status == TripStatus.STARTED) {
                  if (_isMapReady) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isMapReady = false);
                    });
                  }
                  return _buildFullScreenDriverTripView(
                    context,
                    provider,
                    trip,
                  );
                }

                // 🟢 BLINDADO: SI EL VIAJE ESTÁ EN ESPERA DE PAGO (DROPPED_OFF), MOSTRAR COBRO A PANTALLA COMPLETA
                if (trip != null && trip.status == TripStatus.DROPPED_OFF) {
                  if (_isMapReady) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isMapReady = false);
                    });
                  }
                  return Scaffold(
                    backgroundColor: const Color(
                      0xFF0B0F19,
                    ), // Fondo oscuro de la app
                    body: SafeArea(
                      child: PaymentWaitingSheet(
                        tripId: trip.id,
                        amount: trip.price,
                        paymentMethod: trip.paymentMethod,
                        onPaymentConfirmed: (Trip freshTrip) {
                          // 🟢 SINCRO: Llama al método público del provider para actualizar billetera, historial y mostrar el popup de éxito
                          provider.finalizeTripWithWallet(context, freshTrip);
                        },
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    if (trip?.status != TripStatus.STARTED) _buildMenuButton(),
                    if (trip == null && incoming == null)
                      _buildOnlineStatusIndicator(provider),
                    if (provider.isNetworkDisconnected ||
                        provider.isGpsSignalLost)
                      Positioned(
                        top: 90,
                        left: 20,
                        right: 20,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (provider.isNetworkDisconnected)
                              _buildStatusBanner(
                                icon: Icons.cloud_off_rounded,
                                message:
                                    "Sin conexión a internet. Intentando reconectar...",
                                backgroundColor: Colors.redAccent,
                              ),
                            if (provider.isGpsSignalLost &&
                                !provider.isNetworkDisconnected)
                              _buildStatusBanner(
                                icon: Icons.gps_off_rounded,
                                message: "Señal de GPS débil o inestable.",
                                backgroundColor: Colors.orangeAccent,
                              ),
                          ],
                        ),
                      ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                              right: 20,
                              bottom: 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (trip != null) ...[
                                  _buildWazeButton(provider),
                                  const SizedBox(height: 12),
                                ],
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
            // === TARJETA INTERACTIVA DE PROPUESTA DE RUTA SOBRE EL MAPA ===
            Consumer<HomeProvider>(
              builder: (context, provider, _) {
                if (!provider.hasPendingRouteChangeProposal) {
                  return const SizedBox.shrink();
                }

                return Container(
                  color: Colors
                      .black54, // Fondo oscurecido para concentrar la atención
                  width: double.infinity,
                  height: double.infinity,
                  alignment: Alignment.center,
                  child: Dialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    backgroundColor: const Color(0xFF1F2937),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              // ignore: deprecated_member_use
                              color: Colors.amberAccent.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.alt_route_rounded,
                              color: Colors.amberAccent,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            "Cambio de Ruta Propuesto",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "El pasajero solicita modificar el trayecto en curso:",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.montserrat(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // 🟢 TIMELINE DETALLADO DE PARADAS Y DURACIÓN POR TRAMOS
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111827),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.map_rounded,
                                      color: Colors.orangeAccent,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "ITINERARIO DE LA PROPUESTA",
                                      style: GoogleFonts.montserrat(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.orangeAccent,
                                        letterSpacing: 1.1,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Renderizado de las paradas intermedias propuestas
                                if (provider.proposedNewStops.isNotEmpty) ...[
                                  for (
                                    int i = 0;
                                    i < provider.proposedNewStops.length;
                                    i++
                                  ) ...[
                                    _proposedTimelineRow(
                                      Icons.adjust_rounded,
                                      "PARADA ${i + 1}: ${provider.proposedNewStops[i]['direccion']}",
                                      "${provider.proposedNewStops[i]['tiempo_tramo_minutos'] ?? 0} min",
                                      Colors.orangeAccent,
                                    ),
                                    _proposedTimelineLine(),
                                  ],
                                ],

                                // Destino Final Propuesto
                                _proposedTimelineRow(
                                  Icons.location_on_rounded,
                                  "DESTINO: ${provider.proposedNewDestination}",
                                  "${provider.proposedFinalSegmentMinutes} min",
                                  Colors.redAccent,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),

                          // DESGLOSE FINANCIERO PREMIUM Y DURACIÓN TOTAL CONSOLIDADA
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111827),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "NUEVO VALOR A COBRAR:",
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "\$ ${provider.proposedNewPrice.toStringAsFixed(0)}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(
                                  color: Colors.white12,
                                  height: 16,
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "NUEVA GANANCIA NETA:",
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "\$ ${provider.proposedNewDriverRevenue.toStringAsFixed(0)}",
                                      style: const TextStyle(
                                        color: Color(0xFF10B981),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(
                                  color: Colors.white12,
                                  height: 16,
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "DURACIÓN ESTIMADA TOTAL:",
                                        style: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "${provider.proposedNewDurationMinutes} MIN",
                                      style: const TextStyle(
                                        color: Colors.amberAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(
                                  color: Colors.white12,
                                  height: 16,
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "NUEVOS PEAJES EN RUTA:",
                                        style: TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      "\$ ${provider.proposedNewTolls.toStringAsFixed(0)}",
                                      style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // 🟢 NUEVO BOTÓN: PERMITE AL CONDUCTOR VERIFICAR LA NUEVA RUTA EN GOOGLE MAPS / WAZE ANTES DE ACEPTAR
                          SizedBox(
                            height: 48,
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _showExternalNavSheet(
                                  context,
                                  _animatedPosition ??
                                      provider.currentPosition ??
                                      const LatLng(0.0, 0.0),
                                  LatLng(
                                    provider.proposedLatDestino,
                                    provider.proposedLngDestino,
                                  ),
                                  List<Map<String, dynamic>>.from(
                                    provider.proposedNewStops,
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.map_rounded,
                                color: Colors.amberAccent,
                                size: 18,
                              ),
                              label: Text(
                                "VERIFICAR NUEVA RUTA EN GPS",
                                style: GoogleFonts.montserrat(
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Colors.amberAccent,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () {
                                    provider.responderPropuestaRuta(
                                      false,
                                    ); // Rechazar
                                  },
                                  child: Text(
                                    "RECHAZAR",
                                    style: GoogleFonts.montserrat(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    provider.responderPropuestaRuta(
                                      true,
                                    ); // Aceptar
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    "ACEPTAR CAMBIO",
                                    style: GoogleFonts.montserrat(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
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
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _proposedTimelineRow(
    IconData icon,
    String label,
    String duration,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          duration,
          style: GoogleFonts.montserrat(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _proposedTimelineLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 7),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(width: 2, height: 12, color: Colors.white24),
      ),
    );
  }

  /// Abre la cámara del dispositivo para capturar la foto del tablero
  Future<File?> _takeDashboardPhoto() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50, // Comprime al 50% de calidad para ahorrar internet
      );
      if (photo != null) {
        return File(photo.path);
      }
    } catch (e) {
      debugPrint("Error al abrir la cámara: $e");
    }
    return null;
  }

  Widget _buildStatusBanner({
    required IconData icon,
    required String message,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.montserrat(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Abre el modal interactivo para ingresar el kilometraje, capturar la foto del tablero y comprobantes de pago/gasto opcionales
  void _showShiftFormModal({
    required BuildContext context,
    required HomeProvider provider,
    required bool
    isStarting, // true para Iniciar Turno, false para Terminar Turno
  }) {
    final TextEditingController mileageController = TextEditingController();
    File? selectedPhoto;

    // LISTAS LOCALES PARA ALMACENAR COMPROBANTES Y VALORES (OPCIONALES AL CERRAR)
    final List<File> comprobantesCargados = [];
    final List<double> comprobantesValores = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled:
          true, // Permite que el modal suba cuando se abre el teclado
      backgroundColor: const Color(0xFF161B2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext modalCtx, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                20,
                24,
                MediaQuery.of(modalCtx).viewInsets.bottom +
                    30, // Margen de seguridad para el teclado
              ),
              child: SingleChildScrollView(
                // Permite scroll cómodo si la lista de comprobantes crece
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Text(
                      isStarting ? "INICIAR TURNO" : "TERMINAR TURNO",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isStarting
                          ? "Ingresa el kilometraje inicial de tu vehículo y toma una foto nítida del tablero (nivel de gasolina)."
                          : "Ingresa el kilometraje final, toma la foto final del tablero y adjunta comprobantes si es necesario.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.grey[400],
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 1. Campo de texto para ingresar Kilometraje
                    TextField(
                      controller: mileageController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.montserrat(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: "Kilometraje del vehículo",
                        labelStyle: GoogleFonts.poppins(
                          color: Colors.grey[400],
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0B0F19),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(color: Colors.white12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(
                            color: AppColors.primaryGreen,
                            width: 2,
                          ),
                        ),
                        prefixIcon: const Icon(
                          Icons.speed,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. Tarjeta Interactiva para Tomar la Foto del Tablero (OBLIGATORIA)
                    InkWell(
                      onTap: () async {
                        final File? photo = await _takeDashboardPhoto();
                        if (photo != null) {
                          setModalState(() {
                            selectedPhoto = photo;
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: selectedPhoto != null
                              ? AppColors.primaryGreen.withValues(alpha: 0.1)
                              : const Color(0xFF0B0F19),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: selectedPhoto != null
                                ? AppColors.primaryGreen
                                : Colors.white10,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              selectedPhoto != null
                                  ? Icons.check_circle_rounded
                                  : Icons.camera_alt_rounded,
                              color: selectedPhoto != null
                                  ? AppColors.primaryGreen
                                  : Colors.grey[400],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selectedPhoto != null
                                    ? "¡Foto del tablero capturada con éxito!"
                                    : "Tomar foto del tablero",
                                style: GoogleFonts.poppins(
                                  color: selectedPhoto != null
                                      ? AppColors.primaryGreen
                                      : Colors.grey[400],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 🟢 3. SECCIÓN RE-DISEÑADA DE COMPROBANTES DE FACTURAS (SOLO AL TERMINAR TURNO)
                    if (!isStarting) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              "COMPROBANTES Y FACTURAS (OPCIONAL)",
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                                letterSpacing: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (comprobantesCargados.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              "${comprobantesCargados.length} adjuntado(s)",
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: AppColors.primaryGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Botón premium para cargar facturas
                      InkWell(
                        onTap: () async {
                          final File? ticketFile = await _showImageSourceDialog(
                            context,
                          );
                          if (ticketFile != null && context.mounted) {
                            final double?
                            valorFactura = await showDialog<double>(
                              context: context,
                              builder: (dialogCtx) {
                                final TextEditingController textController =
                                    TextEditingController();
                                return dialogCtx.mounted
                                    ? AlertDialog(
                                        backgroundColor: const Color(
                                          0xFF1F2937,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        title: Text(
                                          "Valor de la Factura",
                                          style: GoogleFonts.montserrat(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        content: TextField(
                                          controller: textController,
                                          keyboardType: TextInputType.number,
                                          autofocus: true,
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          decoration: const InputDecoration(
                                            labelText:
                                                "Monto de la Factura (\$)",
                                            labelStyle: TextStyle(
                                              color: Colors.white70,
                                            ),
                                            enabledBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                color: Colors.white30,
                                              ),
                                            ),
                                            focusedBorder: UnderlineInputBorder(
                                              borderSide: BorderSide(
                                                color: AppColors.primaryGreen,
                                              ),
                                            ),
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dialogCtx, null),
                                            child: const Text(
                                              "CANCELAR",
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              final val =
                                                  double.tryParse(
                                                    textController.text.trim(),
                                                  ) ??
                                                  0.0;
                                              Navigator.pop(dialogCtx, val);
                                            },
                                            child: const Text(
                                              "GUARDAR",
                                              style: TextStyle(
                                                color: AppColors.primaryGreen,
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : const SizedBox.shrink();
                              },
                            );

                            if (valorFactura != null) {
                              setModalState(() {
                                comprobantesCargados.add(ticketFile);
                                comprobantesValores.add(valorFactura);
                              });
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(15),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B0F19),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.cloud_upload_rounded,
                                color: AppColors.primaryGreen,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "Adjuntar Factura",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // VISTA PREVIA PREMIUM DE COMPROBANTES CARGADOS
                      if (comprobantesCargados.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: comprobantesCargados.length,
                            itemBuilder: (ctx, i) {
                              return Stack(
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    margin: const EdgeInsets.only(
                                      right: 12,
                                      top: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppColors.primaryGreen
                                            .withValues(alpha: 0.4),
                                        width: 1.5,
                                      ),
                                      image: DecorationImage(
                                        image: FileImage(
                                          comprobantesCargados[i],
                                        ),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 14,
                                    left: 4,
                                    right: 16,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.75,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "\$${comprobantesValores[i].toStringAsFixed(0)}",
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.montserrat(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 4,
                                    top: 2,
                                    child: GestureDetector(
                                      onTap: () {
                                        setModalState(() {
                                          comprobantesCargados.removeAt(i);
                                          comprobantesValores.removeAt(i);
                                        });
                                      },
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.redAccent,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white,
                                          size: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 18),

                    // 4. Botón de confirmación y envío de datos
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: () async {
                          final String mileageStr = mileageController.text
                              .trim();
                          if (mileageStr.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "⚠️ Debes ingresar el kilometraje.",
                                ),
                              ),
                            );
                            return;
                          }
                          if (selectedPhoto == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "⚠️ Debes tomar la foto del tablero.",
                                ),
                              ),
                            );
                            return;
                          }

                          final int mileage = int.parse(
                            mileageController.text.trim(),
                          );

                          // Cerramos el modal primero para que no obstruya la vista
                          Navigator.pop(ctx);

                          String? error;

                          // 🟢 ENVOLVEMOS LAS PETICIONES EN UN TRY-CATCH SEGURO
                          try {
                            if (isStarting) {
                              debugPrint(
                                "API_DEBUG_FRONT: Iniciando llamada asíncrona a iniciarTurnoCompleto...",
                              );
                              error = await provider.iniciarTurnoCompleto(
                                kilometraje: mileage,
                                foto: selectedPhoto!,
                              );
                              debugPrint(
                                "API_DEBUG_FRONT: iniciarTurnoCompleto finalizó. Valor devuelto -> '$error'",
                              );
                            } else {
                              debugPrint(
                                "API_DEBUG_FRONT: Iniciando llamada asíncrona a terminarTurnoCompleto...",
                              );
                              error = await provider.terminarTurnoCompleto(
                                kilometraje: mileage,
                                foto: selectedPhoto!,
                                comprobantesFotos: comprobantesCargados,
                                comprobantesValores: comprobantesValores,
                              );
                              debugPrint(
                                "API_DEBUG_FRONT: terminarTurnoCompleto finalizó. Valor devuelto -> '$error'",
                              );
                            }
                          } catch (e, stackTrace) {
                            // Captura y limpia el mensaje en caso de excepción del Api Client
                            error = e.toString().replaceAll("Exception: ", "");
                            debugPrint(
                              "API_DEBUG_FRONT: Excepción capturada en catch del front -> $e",
                            );
                            debugPrint(
                              "API_DEBUG_FRONT: StackTrace -> $stackTrace",
                            );
                          }

                          debugPrint(
                            "API_DEBUG_FRONT: Evaluando error final en UI -> '$error'",
                          );

                          // Modificar este bloque de evaluación de errores
                          // Modificar este bloque de evaluación de errores
                          if (error != null && context.mounted) {
                            final String lowerError = error.toLowerCase();

                            // 1. Detectar error de Vehículo en uso (Laravel 400)
                            if (lowerError.contains("en uso") ||
                                lowerError.contains("uso activo") ||
                                lowerError.contains(
                                  "vehículo ya está en uso",
                                ) ||
                                lowerError.contains("ya se encuentra en uso")) {
                              _showShiftBlockedAlert(
                                context,
                                title: "Vehículo en Uso",
                                message:
                                    error, // Mostrará el mensaje exacto del backend
                                icon: Icons.warning_amber_rounded,
                                color: Colors.orangeAccent,
                              );
                            }
                            // 2. Detectar error de Billetera/Saldo insuficiente (Laravel 402)
                            else if (lowerError.contains("billetera") ||
                                lowerError.contains("saldo") ||
                                lowerError.contains("pendientes") ||
                                lowerError.contains("insuficiente") ||
                                lowerError.contains("suspendida")) {
                              _showShiftBlockedAlert(
                                context,
                                title: "Cuenta Suspendida",
                                message:
                                    error, // Mostrará la explicación del saldo
                                icon: Icons.account_balance_wallet_rounded,
                                color: Colors.redAccent,
                              );
                            }
                            // 3. 🟢 Cualquier otro error del backend (como SOAT vencido, licencia vencida, etc.)
                            else {
                              _showShiftBlockedAlert(
                                context,
                                title: "Acceso Restringido",
                                message:
                                    error, // Muestra dinámicamente el mensaje enviado por Laravel
                                icon: Icons.lock_outline_rounded,
                                color: Colors.redAccent,
                              );
                            }
                          } else if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isStarting
                                      ? "🟢 ¡Turno iniciado con éxito!"
                                      : "🔴 ¡Turno finalizado con éxito!",
                                ),
                                backgroundColor: AppColors.primaryGreen,
                              ),
                            );
                          }
                        },
                        child: Text(
                          isStarting
                              ? "CONFIRMAR E INICIAR"
                              : "CONFIRMAR Y FINALIZAR",
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 🟢 ALERTA DINÁMICA DE BLOQUEO DE TURNO (Maneja múltiples tipos de errores)
  void _showShiftBlockedAlert(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color color,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
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
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 40),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  color: Colors.grey[300],
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    "ENTENDIDO",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
  final LatLng? animatedPassengerPosition;

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

        final LatLng? passengerPosToDraw =
            animatedPassengerPosition ?? provider.passengerLocation;

        // 🟢 Extraer de forma segura las paradas intermedias si existen
        final List<Marker> stopMarkers = [];
        if (trip != null &&
            trip.desglosePrecio != null &&
            trip.desglosePrecio!['paradas'] != null) {
          final paradas = trip.desglosePrecio!['paradas'] as List;
          for (var stop in paradas) {
            final double? lat = double.tryParse(stop['lat']?.toString() ?? '');
            final double? lng = double.tryParse(stop['lng']?.toString() ?? '');
            if (lat != null && lng != null) {
              stopMarkers.add(
                Marker(
                  point: LatLng(lat, lng),
                  width: 30,
                  height: 30,
                  child: const Icon(
                    Icons
                        .flag_circle_rounded, // 👈 Icono de bandera para paradas
                    color: Colors.deepOrangeAccent, // 👈 Color naranja/ámbar
                    size: 28,
                  ),
                ),
              );
            }
          }
        }

        if (trip == null ||
            (trip.status != TripStatus.ACCEPTED &&
                trip.status != TripStatus.ARRIVED) ||
            passengerPosToDraw == null) {
          return MarkerLayer(
            markers: [
              if (posToDraw != null)
                _buildDriverMarker(posToDraw, headingToDraw),
              ...stopMarkers, // 🟢 Paradas agregadas
            ],
          );
        }

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

            ...stopMarkers, // 🟢 Paradas agregadas
          ],
        );
      },
    );
  }

  // 🟢 METODO DE AYUDA RESTAURADO
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
