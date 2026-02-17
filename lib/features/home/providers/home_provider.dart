import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

// Imports Core
import '../../../core/models/trip_model.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../core/di/injection_container.dart';

// Imports Services & Repositories
import '../services/location_service.dart';
import '../services/trip_service.dart';
import '../repositories/driver_repository.dart';
import '../repositories/trip_repository.dart';

// Imports Wallet
import '../../wallet/providers/wallet_provider.dart';

class HomeProvider extends ChangeNotifier {
  // 1. INYECCIÓN DE DEPENDENCIAS (Mejora Crítica)
  // Ahora usamos 'sl' para todo, facilitando el switch Mock/Real y tests.
  final LocationService _locationService = sl<LocationService>();
  final TripService _tripService = sl<TripService>();
  final StorageService _storageService =
      sl<
        StorageService
      >(); // Asegúrate de registrar este en DI también, o úsalo directo si es singleton simple.

  final DriverRepository _driverRepository = sl<DriverRepository>();
  final TripRepository _tripRepository = sl<TripRepository>();

  // Estado
  bool _isOnline = false;
  bool _isLoading = false;
  LatLng? _currentPosition;
  Trip? _incomingTrip;
  Trip? _activeTrip;
  List<LatLng> _routePoints = [];

  // Variables de simulación y streams
  Timer? _simulationTimer;
  int _simulationIndex = 0;
  bool _isSimulating = false;

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription? _tripSubscription;

  // Getters
  bool get isOnline => _isOnline;
  bool get isLoading => _isLoading;
  LatLng? get currentPosition => _currentPosition;
  Trip? get incomingTrip => _incomingTrip;
  Trip? get activeTrip => _activeTrip;
  List<LatLng> get routePoints => _routePoints;

  // ----------------------------------------
  // 1. INICIALIZACIÓN
  // ----------------------------------------
  Future<void> initLocation() async {
    _isLoading = true;
    notifyListeners();

    // Recuperar estado anterior (Persistencia)
    final savedTrip = await _storageService.getCurrentTrip();
    if (savedTrip != null) {
      _activeTrip = savedTrip;
      _isOnline = true;
      await _calculateRouteForCurrentStatus();
      debugPrint("♻️ VIAJE RESTAURADO: ${_activeTrip!.status}");
    }

    // Permisos y primera ubicación
    final hasPermission = await _locationService.checkPermissions();
    if (hasPermission) {
      final position = await _locationService.getCurrentLocation();
      if (position != null && !_isSimulating) {
        _currentPosition = LatLng(position.latitude, position.longitude);
      }
      _startTracking();
    }
    _isLoading = false;
    notifyListeners();
  }

  void _startTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = _locationService.getPositionStream().listen((pos) {
      if (_isSimulating) return; // Si estamos simulando ruta, ignorar GPS real
      _currentPosition = LatLng(pos.latitude, pos.longitude);
      notifyListeners();
    });
  }

  // ----------------------------------------
  // 2. CONTROL DE ESTADO (ONLINE/OFFLINE)
  // ----------------------------------------

  /// Intenta cambiar el estado.
  /// Retorna un String con el error si falla, o null si tuvo éxito.
  /// Esto permite a la UI mostrar un SnackBar.
  Future<String?> toggleOnlineStatus() async {
    if (_isLoading) return null;

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Validar documentos y estado en el Backend/Repo
      // Usar el ID real del usuario autenticado
      await _driverRepository.toggleStatus(isOnline: !_isOnline, driverId: "1");

      // 2. Si no explotó la excepción, cambiamos estado local
      _isOnline = !_isOnline;

      if (_isOnline) {
        _startListeningTrips();
      } else {
        _stopListeningTrips();
        _activeTrip = null;
        _routePoints = [];
        await _storageService.clearCurrentTrip();
      }
      return null; // Éxito (sin error)
    } catch (e) {
      debugPrint("❌ BLOQUEO OPERATIVO: $e");
      _isOnline = false; // Forzar offline por seguridad

      // Limpiamos el mensaje de excepción para que sea legible en UI
      return e.toString().replaceAll("Exception: ", "");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------
  // 3. GESTIÓN DE VIAJES (SOCKETS/POLLING)
  // ----------------------------------------
  void _startListeningTrips() {
    debugPrint("👂 PROVIDER: Escuchando ofertas...");
    _tripSubscription?.cancel();
    _tripSubscription = _tripRepository.listenForTrips().listen((trip) {
      if (_activeTrip != null) return; // Ocupado

      debugPrint("🔔 PROVIDER: ¡Nueva oferta recibida!");
      _incomingTrip = trip;

      // Reproducir sonido aquí si lo deseas
      notifyListeners();
    });
  }

  void _stopListeningTrips() {
    _tripSubscription?.cancel();
    _incomingTrip = null;
    notifyListeners();
  }

  // ----------------------------------------
  // 4. FLUJO DE VIAJE
  // ----------------------------------------
  Future<void> acceptIncomingTrip() async {
    if (_incomingTrip == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Aceptar y obtener FUEC
      final acceptedTrip = await _tripRepository.acceptTrip(_incomingTrip!.id);

      _activeTrip = acceptedTrip;
      _incomingTrip = null;

      await _storageService.saveCurrentTrip(_activeTrip!);
      await _calculateRouteForCurrentStatus();

      // Iniciar simulación para demo (Quitar en prod real si usas GPS)
      _startSimulation();
    } catch (e) {
      debugPrint("Error aceptando viaje: $e");
      // Aquí podrías manejar un error visual también
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void rejectIncomingTrip() {
    if (_incomingTrip != null) {
      _tripRepository.rejectTrip(_incomingTrip!.id);
      _incomingTrip = null;
      notifyListeners();
      // Seguir escuchando nuevas ofertas
    }
  }

  // Acción del botón principal según estado
  Future<void> handleTripAction(BuildContext context) async {
    if (_activeTrip == null) return;

    if (_activeTrip!.status == TripStatus.STARTED) {
      _finalizeTripWithWallet(context);
    } else {
      await _advanceStatusOnly();
    }
  }

  Future<void> _advanceStatusOnly() async {
    TripStatus nextStatus;
    switch (_activeTrip!.status) {
      case TripStatus.ACCEPTED:
        nextStatus = TripStatus.ARRIVED;
        break;
      case TripStatus.ARRIVED:
        nextStatus = TripStatus.STARTED;
        break;
      default:
        return;
    }
    await _updateTripStatus(nextStatus);
  }

  Future<void> _updateTripStatus(TripStatus status) async {
    if (_activeTrip == null) return;

    // Llamar al API para actualizar estado en servidor
    // await _tripRepository.updateTripStatus(_activeTrip!.id, status.name);

    _activeTrip = _activeTrip!.copyWith(status: status);
    await _storageService.saveCurrentTrip(_activeTrip!);

    _stopSimulation();
    await _calculateRouteForCurrentStatus();

    if (status == TripStatus.ACCEPTED || status == TripStatus.STARTED) {
      _startSimulation();
    }
    notifyListeners();
  }

  // ----------------------------------------
  // 5. FINANZAS Y CIERRE
  // ----------------------------------------
  void _finalizeTripWithWallet(BuildContext context) {
    if (_activeTrip == null) return;

    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    walletProvider.processTripPayment(
      _activeTrip!.price,
      _activeTrip!.id,
      _activeTrip!.destinationAddress,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("¡Viaje finalizado! Saldo actualizado."),
        backgroundColor: Colors.green,
      ),
    );

    _finishTrip();
  }

  void _finishTrip() {
    _activeTrip = null;
    _routePoints = [];
    _storageService.clearCurrentTrip();
    _stopSimulation();
    _startListeningTrips(); // Volver a escuchar ofertas
    notifyListeners();
  }

  // ----------------------------------------
  // 6. RUTAS Y MAPA
  // ----------------------------------------
  Future<void> _calculateRouteForCurrentStatus() async {
    if (_activeTrip == null || _currentPosition == null) return;

    LatLng? destination;
    if (_activeTrip!.status == TripStatus.ACCEPTED) {
      destination = _activeTrip!.originLocation;
    } else if (_activeTrip!.status == TripStatus.STARTED) {
      destination = _activeTrip!.destinationLocation;
    } else {
      _routePoints = [];
      return;
    }

    final rawPoints = await _tripService.getRoutePolyline(
      _currentPosition!,
      destination,
    );

    _routePoints = _interpolatePoints(rawPoints, steps: 20);
    notifyListeners();
  }

  void _startSimulation() {
    if (_routePoints.isEmpty) return;
    _isSimulating = true;
    _simulationIndex = 0;
    _simulationTimer?.cancel();

    _simulationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_simulationIndex < _routePoints.length) {
        _currentPosition = _routePoints[_simulationIndex];
        _simulationIndex++;
        notifyListeners();
      } else {
        _isSimulating = false;
        timer.cancel();
      }
    });
  }

  void _stopSimulation() {
    _isSimulating = false;
    _simulationTimer?.cancel();
  }

  List<LatLng> _interpolatePoints(List<LatLng> points, {int steps = 10}) {
    List<LatLng> result = [];
    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      for (int j = 0; j <= steps; j++) {
        final double t = j / steps;
        final double lat = start.latitude + (end.latitude - start.latitude) * t;
        final double lng =
            start.longitude + (end.longitude - start.longitude) * t;
        result.add(LatLng(lat, lng));
      }
    }
    return result;
  }

  void openExternalNavigation() {
    if (_activeTrip == null) return;
    LatLng target = _activeTrip!.status == TripStatus.ACCEPTED
        ? _activeTrip!.originLocation
        : _activeTrip!.destinationLocation;
    MapLauncher.launchNavigation(destination: target);
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _tripSubscription?.cancel();
    _simulationTimer?.cancel();
    super.dispose();
  }
}
