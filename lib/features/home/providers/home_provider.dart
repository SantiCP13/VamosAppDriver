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
  final LocationService _locationService = sl<LocationService>();
  final TripService _tripService = sl<TripService>();
  final StorageService _storageService = sl<StorageService>();
  final DriverRepository _driverRepository = sl<DriverRepository>();
  final TripRepository _tripRepository = sl<TripRepository>();

  // Estado
  bool _isOnline = false;
  bool _isLoading = false;

  // Ubicación y Rotación
  LatLng? _currentPosition;
  double _currentHeading = 0.0; // Para la rotación del carro

  Trip? _incomingTrip;
  Trip? _activeTrip;
  List<LatLng> _routePoints = [];

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription? _tripSubscription;

  // Getters
  bool get isOnline => _isOnline;
  bool get isLoading => _isLoading;
  LatLng? get currentPosition => _currentPosition;
  double get currentHeading => _currentHeading; // Getter nuevo
  Trip? get incomingTrip => _incomingTrip;
  Trip? get activeTrip => _activeTrip;
  List<LatLng> get routePoints => _routePoints;

  // ----------------------------------------
  // 1. INICIALIZACIÓN
  // ----------------------------------------
  Future<void> initLocation() async {
    _isLoading = true;
    notifyListeners();

    final savedTrip = await _storageService.getCurrentTrip();
    if (savedTrip != null) {
      _activeTrip = savedTrip;
      _isOnline = true;
      _startListeningTrips(); // Reconectar sockets si estaba online
      await _calculateRouteForCurrentStatus();
    }

    final hasPermission = await _locationService.checkPermissions();
    if (hasPermission) {
      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _currentHeading = position.heading;
      }
      _startTracking();
    }
    _isLoading = false;
    notifyListeners();
  }

  void _startTracking() {
    _positionSubscription?.cancel();
    // Escuchamos el GPS Real
    _positionSubscription = _locationService.getPositionStream().listen((pos) {
      _updatePosition(pos);
    });
  }

  void _updatePosition(Position pos) {
    final newLocation = LatLng(pos.latitude, pos.longitude);

    // Calcular rotación si el GPS no nos da el heading (o si estamos parados)
    // Solo actualizamos heading si nos hemos movido lo suficiente (> 2 metros)
    // para evitar que el carro gire como loco estando quieto.
    if (_currentPosition != null) {
      final Distance distance = const Distance();
      final double dist = distance.as(
        LengthUnit.Meter,
        _currentPosition!,
        newLocation,
      );

      if (dist > 2.0) {
        // Usamos el heading del GPS si es válido, si no, calculamos el bearing
        if (pos.heading > 0) {
          _currentHeading = pos.heading;
        } else {
          // Calculamos bearing manual (opcional, geolocator suele darlo bien en movimiento)
        }
      }
    }

    _currentPosition = newLocation;

    // Si hay viaje activo, verificamos proximidad o recalculamos ruta si nos desviamos
    // (Lógica avanzada: Recalcular ruta cada X metros o segundos)

    notifyListeners();
  }

  // ----------------------------------------
  // 2. CONTROL DE ESTADO
  // ----------------------------------------
  Future<String?> toggleOnlineStatus() async {
    if (_isLoading) return null;
    _isLoading = true;
    notifyListeners();

    try {
      // "Regla de Oro": El backend valida documentos aquí.
      await _driverRepository.toggleStatus(isOnline: !_isOnline, driverId: "1");

      _isOnline = !_isOnline;

      if (_isOnline) {
        _startListeningTrips();
      } else {
        _stopListeningTrips();
        _activeTrip = null;
        _routePoints = [];
        await _storageService.clearCurrentTrip();
      }
      return null;
    } catch (e) {
      debugPrint("❌ BLOQUEO OPERATIVO: $e");
      _isOnline = false;
      return e.toString().replaceAll("Exception: ", "");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ----------------------------------------
  // 3. GESTIÓN DE VIAJES
  // ----------------------------------------
  void _startListeningTrips() {
    _tripSubscription?.cancel();
    _tripSubscription = _tripRepository.listenForTrips().listen((trip) {
      if (_activeTrip != null) return;
      _incomingTrip = trip;
      notifyListeners();
    });
  }

  void _stopListeningTrips() {
    _tripSubscription?.cancel();
    _incomingTrip = null;
    notifyListeners();
  }

  Future<void> acceptIncomingTrip() async {
    if (_incomingTrip == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final acceptedTrip = await _tripRepository.acceptTrip(_incomingTrip!.id);
      _activeTrip = acceptedTrip;
      _incomingTrip = null;
      await _storageService.saveCurrentTrip(_activeTrip!);

      // Ya no simulamos, calculamos ruta real
      await _calculateRouteForCurrentStatus();
    } catch (e) {
      debugPrint("Error aceptando viaje: $e");
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
    }
  }

  // ----------------------------------------
  // 4. FLUJO DE VIAJE
  // ----------------------------------------
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
    // await _tripRepository.updateTripStatus(_activeTrip!.id, status.name); // Descomentar con API real

    _activeTrip = _activeTrip!.copyWith(status: status);
    await _storageService.saveCurrentTrip(_activeTrip!);

    await _calculateRouteForCurrentStatus();
    notifyListeners();
  }

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
        content: Text("¡Viaje finalizado!"),
        backgroundColor: Colors.green,
      ),
    );
    _finishTrip();
  }

  void _finishTrip() {
    _activeTrip = null;
    _routePoints = [];
    _storageService.clearCurrentTrip();
    _startListeningTrips();
    notifyListeners();
  }

  // ----------------------------------------
  // 5. RUTAS (REALES)
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

    // Usamos el servicio real (inyectado)
    _routePoints = await _tripService.getRoutePolyline(
      _currentPosition!,
      destination,
    );
    notifyListeners();
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
    super.dispose();
  }
}
