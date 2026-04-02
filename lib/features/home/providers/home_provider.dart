import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// --------------------------------------------------------
// IMPORTS CORE (Modelos e Inyección)
// --------------------------------------------------------
import '../../../core/models/trip_model.dart';
import '../../../core/models/document_model.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../core/di/injection_container.dart';

// --------------------------------------------------------
// IMPORTS SERVICES & REPOSITORIES
// --------------------------------------------------------
import '../services/location_service.dart';
import '../services/trip_service.dart';
import '../repositories/driver_repository.dart';
import '../repositories/trip_repository.dart';

// --------------------------------------------------------
// IMPORTS MODULOS EXTERNOS (Wallet, History, Widgets)
// --------------------------------------------------------
import '../../wallet/providers/wallet_provider.dart';
import '../../history/providers/history_provider.dart';
import '../widgets/payment_waiting_sheet.dart'; // <--- WIDGET DE PAGO
import '../../auth/providers/auth_provider.dart';

class HomeProvider extends ChangeNotifier {
  // 1. INYECCIÓN DE DEPENDENCIAS
  final LocationService _locationService = sl<LocationService>();
  final TripService _tripService = sl<TripService>();
  final StorageService _storageService = sl<StorageService>();
  final DriverRepository _driverRepository = sl<DriverRepository>();
  final TripRepository _tripRepository = sl<TripRepository>();

  // 2. ESTADO
  bool _isOnline = false;
  bool _isLoading = false;

  // Ubicación y Rotación
  LatLng? _currentPosition;
  double _currentHeading = 0.0;

  // Viaje
  Trip? _incomingTrip;
  Trip? _activeTrip;
  List<LatLng> _routePoints = [];

  // Vehículos y Documentos (FUEC)
  List<Vehicle> _myVehicles = [];
  Vehicle? _selectedVehicle;
  List<DriverDocument> _documents = [];

  // Subscriptions
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription? _tripSubscription;

  // 3. GETTERS PÚBLICOS
  bool get isOnline => _isOnline;
  bool get isLoading => _isLoading;
  LatLng? get currentPosition => _currentPosition;
  double get currentHeading => _currentHeading;
  Trip? get incomingTrip => _incomingTrip;
  Trip? get activeTrip => _activeTrip;
  List<LatLng> get routePoints => _routePoints;
  List<Vehicle> get myVehicles => _myVehicles;
  Vehicle? get selectedVehicle => _selectedVehicle;

  // --- AÑADIR DESPUÉS DE LA LÍNEA 65 ---
  String get distanceToTarget {
    if (_currentPosition == null || _activeTrip == null) return "---";

    const Distance distance = Distance();

    // Punto objetivo: Si voy a recoger -> Origen. Si ya inicié -> Destino.
    LatLng target =
        (_activeTrip!.status == TripStatus.ACCEPTED ||
            _activeTrip!.status == TripStatus.ARRIVED)
        ? _activeTrip!.originLocation
        : _activeTrip!.destinationLocation;

    double meterDist = distance.as(LengthUnit.Meter, _currentPosition!, target);

    if (meterDist < 1000) {
      return "${meterDist.toStringAsFixed(0)} m";
    } else {
      return "${(meterDist / 1000).toStringAsFixed(1)} km";
    }
  }
  // =======================================================
  // A. INICIALIZACIÓN Y GPS
  // =======================================================

  Future<void> initLocation() async {
    _isLoading = true;
    notifyListeners();
    await loadVehicles();

    final user = sl<AuthProvider>().user;
    if (user != null) {
      // Carga inicial de datos
      sl<WalletProvider>().loadWalletData();
      // Encendemos el monitor de la billetera (independiente de si está Online)
      _startListeningWalletUpdates(user.id);
    }
    // 1. Recuperar viaje persistido (si la app se cerró)
    final savedTrip = await _storageService.getCurrentTrip();
    if (savedTrip != null) {
      _activeTrip = savedTrip;
      _isOnline = true; // Forzamos online si hay un viaje activo
      _startListeningTrips();
      await _calculateRouteForCurrentStatus();
    }

    // 2. Permisos y GPS
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
    _positionSubscription = _locationService.getPositionStream().listen((pos) {
      _updatePosition(pos);
    });
  }

  void _updatePosition(Position pos) {
    final newLocation = LatLng(pos.latitude, pos.longitude);

    if (_currentPosition != null) {
      final Distance distance = const Distance();
      final double dist = distance.as(
        LengthUnit.Meter,
        _currentPosition!,
        newLocation,
      );

      // 1. Si está ONLINE pero NO está en un viaje, enviar "Heartbeat" de disponibilidad
      if (_isOnline && _activeTrip == null && dist > 10.0) {
        _driverRepository.updatePosition(pos.latitude, pos.longitude);
      }

      // 2. Si está en un VIAJE ACTIVO, enviar tracking para el pasajero (PuntoTrackingEvent)
      if (_activeTrip?.status == TripStatus.STARTED && dist > 15.0) {
        _tripRepository.updateLocation(
          _activeTrip!.id,
          pos.latitude,
          pos.longitude,
        );
      }

      if (dist > 2.0 && pos.heading > 0) {
        _currentHeading = pos.heading;
      }
    }

    _currentPosition = newLocation;
    notifyListeners();
  }
  // =======================================================
  // B. GESTIÓN DE VEHÍCULOS (REQUISITO FUEC)
  // =======================================================

  Future<void> loadVehicles() async {
    // BORRA O COMENTA ESTA LÍNEA:
    // if (_myVehicles.isNotEmpty) return;

    try {
      _isLoading = true;
      _myVehicles =
          []; // 🔥 LIMPIEZA: Forzamos que la lista se vacíe un instante
      notifyListeners();
      final String userId = sl<AuthProvider>().user?.id ?? "0";
      _myVehicles = await _driverRepository.getAssignedVehicles(userId);

      // Si el vehículo seleccionado ya no está en la lista (lo desactivaste en admin)
      if (_selectedVehicle != null &&
          !_myVehicles.any((v) => v.id == _selectedVehicle!.id)) {
        _selectedVehicle = _myVehicles.isNotEmpty ? _myVehicles.first : null;
        if (_isOnline && _selectedVehicle == null) {
          toggleOnlineStatus(); // Lo desconectamos por seguridad si ya no tiene auto
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectVehicle(Vehicle vehicle) {
    _selectedVehicle = vehicle;
    notifyListeners();
  }

  // =======================================================
  // C. CONTROL ONLINE / OFFLINE (GATEKEEPER)
  // =======================================================

  Future<bool> _checkDocumentsValidity() async {
    try {
      final String userId = sl<AuthProvider>().user?.id ?? "1";
      _documents = await _driverRepository.getDocuments(userId);
      final expiredDocs = _documents.where((doc) => !doc.isValid).toList();

      if (expiredDocs.isNotEmpty) {
        final docNames = expiredDocs.map((d) => d.name).join(", ");
        throw Exception("Documentos vencidos: $docNames.");
      }
      return true;
    } catch (e) {
      rethrow;
    }
  }

  Future<String?> toggleOnlineStatus() async {
    if (_isLoading) return null;

    if (!_isOnline && _selectedVehicle == null) {
      return "⚠️ Debes seleccionar un vehículo para generar el FUEC.";
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Validar documentos antes de intentar conectar (Usamos la función huérfana)
      if (!_isOnline) {
        await _checkDocumentsValidity();
      }

      final String userId = sl<AuthProvider>().user?.id ?? "0";

      // 2. Llamada al repo con todos los parámetros corregidos
      await _driverRepository.toggleStatus(
        isOnline: !_isOnline,
        driverId: userId,
        vehicleId: _selectedVehicle?.id, // Aquí ya no habrá error de String/int
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );

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
      return e.toString().replaceAll("Exception: ", "");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // =======================================================
  // D. GESTIÓN DE VIAJES (CICLO DE VIDA)
  // =======================================================
  void _startListeningWalletUpdates(String userId) {
    _tripRepository.listenForWalletUpdates(userId).listen((nuevoSaldo) {
      debugPrint(
        "💰 [REAL-TIME] Señal de billetera recibida. Saldo: $nuevoSaldo",
      );

      // Esto actualizará el Side Menu y la Wallet Screen al instante
      sl<WalletProvider>().loadWalletData(force: true);
    });
  }

  void _startListeningTrips() {
    _tripSubscription?.cancel();

    // Aquí solo dejamos la escucha de viajes (Ofertas),
    // porque esto sí solo debe ocurrir cuando el conductor está Online.
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
    if (_incomingTrip == null || _currentPosition == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      // 🔥 CAMBIO CLAVE: Usamos assignmentId si existe, sino usamos el id
      final idParaResponder = _incomingTrip!.assignmentId ?? _incomingTrip!.id;

      final acceptedTrip = await _tripRepository.acceptTrip(
        idParaResponder, // <--- Ahora enviará "8" y no "34"
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      _activeTrip = acceptedTrip;
      _incomingTrip = null;
      await _storageService.saveCurrentTrip(_activeTrip!);
      await _calculateRouteForCurrentStatus();
    } catch (e) {
      debugPrint("Error: $e");
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

  // =======================================================
  // E. MÁQUINA DE ESTADOS Y COBRO (LÓGICA CRÍTICA)
  // =======================================================

  /// Método principal llamado por el botón grande del panel
  Future<void> handleTripAction(BuildContext context) async {
    if (_activeTrip == null) return;

    // 1. SI ESTAMOS EN RUTA -> LLEGAMOS AL DESTINO -> INICIAR FLUJO DE COBRO
    if (_activeTrip!.status == TripStatus.STARTED) {
      await _initiatePaymentFlow(context);
    }
    // 2. OTROS ESTADOS (Aceptado -> Llegada -> Inicio)
    else {
      await _advanceStatusOnly();
    }
  }

  /// Flujo de Fin de Viaje:
  /// 1. Notifica llegada al backend.
  /// 2. Obtiene precio calculado.
  /// 3. Muestra Modal de Pago Bloqueante.
  Future<void> _initiatePaymentFlow(BuildContext context) async {
    _isLoading = true;
    notifyListeners();

    try {
      // A. Notificar al backend "Llegué al destino" (DROPPED_OFF).
      final updatedTrip = await _tripRepository.updateTripStatus(
        _activeTrip!.id,
        "DROPPED_OFF",
      );

      _activeTrip = updatedTrip;
      await _storageService.saveCurrentTrip(_activeTrip!);

      _isLoading = false;
      notifyListeners();

      // B. Mostrar Sheet de Espera de Pago (Bloqueante)
      if (context.mounted) {
        showModalBottomSheet(
          context: context,
          isDismissible: false, // Obligatorio esperar
          enableDrag: false,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => PaymentWaitingSheet(
            tripId: _activeTrip!.id,
            amount: _activeTrip!.price,
            paymentMethod: _activeTrip!
                .paymentMethod, // <--- CAMBIO: Pasamos el método de pago
            onPaymentConfirmed: () {
              // C. Callback: El pago fue confirmado (Vía Socket o Vía Efectivo)
              _finalizeTripWithWallet(context);
            },
          ),
        );
      }
    } catch (e) {
      debugPrint("Error calculando fin de viaje: $e");
      _isLoading = false;
      notifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al procesar llegada: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Cierre definitivo tras confirmación de pago
  Future<void> _finalizeTripWithWallet(BuildContext context) async {
    if (_activeTrip == null) return;

    try {
      // 1. Enviar estado COMPLETED al Backend Y GUARDAR EL RESULTADO
      final completedTrip = await _tripRepository.updateTripStatus(
        _activeTrip!.id,
        TripStatus.COMPLETED.name,
      );

      // <--- SOLUCIÓN: Actualizamos el viaje activo con los datos financieros reales
      _activeTrip = completedTrip;

      // 2. Actualizar módulos locales (Wallet / History)
      if (context.mounted) {
        Provider.of<WalletProvider>(
          context,
          listen: false,
        ).registerCompletedTrip(_activeTrip!);
        Provider.of<HistoryProvider>(
          context,
          listen: false,
        ).addFinishedTrip(_activeTrip!);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ Viaje finalizado. Ganancia: \$${_activeTrip!.driverRevenue.toStringAsFixed(0)}",
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // 3. Limpiar mapa y buscar nuevos viajes
      _finishTrip();
    } catch (e) {
      debugPrint("Error cerrando viaje: $e");
    }
  }

  // Avance simple de estados (Aceptado -> Llegado -> Iniciado)
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
    await _updateTripStatus(nextStatus.name);
  }

  Future<Trip?> _updateTripStatus(String statusName) async {
    if (_activeTrip == null) return null;
    try {
      final updatedTrip = await _tripRepository.updateTripStatus(
        _activeTrip!.id,
        statusName,
        // 🔥 AQUÍ PASAMOS EL GPS ACTUAL DEL EMULADOR
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );
      _activeTrip = updatedTrip;
      await _storageService.saveCurrentTrip(_activeTrip!);
      await _calculateRouteForCurrentStatus();
      notifyListeners();
      return updatedTrip;
    } catch (e) {
      debugPrint("Error actualizando estado: $e");
      rethrow;
    }
  }

  void _finishTrip() {
    _activeTrip = null;
    _routePoints = [];
    _storageService.clearCurrentTrip();
    _startListeningTrips(); // Vuelvo a escuchar ofertas
    notifyListeners();
  }

  // =======================================================
  // F. ACCIONES EXTERNAS Y NAVEGACIÓN
  // =======================================================

  Future<void> cancelCurrentTrip(BuildContext context) async {
    if (_activeTrip == null) return;
    _isLoading = true;
    notifyListeners();
    try {
      await _tripRepository.updateTripStatus(_activeTrip!.id, "CANCELLED");

      _activeTrip = null;
      _routePoints = [];
      await _storageService.clearCurrentTrip();
      _startListeningTrips();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Viaje cancelado"),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error cancelando: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> launchWhatsApp(String phone) async {
    var number = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!number.startsWith('57')) number = '57$number';

    final Uri url = Uri.parse("https://wa.me/$number");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('No se pudo abrir WhatsApp');
    }
  }

  Future<void> launchSOS() async {
    final Uri launchUri = Uri(scheme: 'tel', path: '123');
    await launchUrl(launchUri);
  }

  void openExternalNavigation() {
    if (_activeTrip == null) return;
    LatLng target = _activeTrip!.status == TripStatus.ACCEPTED
        ? _activeTrip!.originLocation
        : _activeTrip!.destinationLocation;
    MapLauncher.launchNavigation(destination: target);
  }

  // =======================================================
  // G. RUTAS
  // =======================================================

  Future<void> _calculateRouteForCurrentStatus() async {
    if (_activeTrip == null || _currentPosition == null) return;

    LatLng? destination;

    // 🚩 Si voy a buscar al pasajero o ya estoy ahí esperando:
    if (_activeTrip!.status == TripStatus.ACCEPTED ||
        _activeTrip!.status == TripStatus.ARRIVED) {
      destination = _activeTrip!.originLocation; // Punto de recogida
    }
    // 🚩 Si el pasajero ya subió y el viaje inició:
    else if (_activeTrip!.status == TripStatus.STARTED) {
      destination = _activeTrip!.destinationLocation; // Punto de destino
    }

    if (destination != null) {
      _routePoints = await _tripService.getRoutePolyline(
        _currentPosition!,
        destination,
      );
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _tripSubscription?.cancel();
    super.dispose();
  }
}
