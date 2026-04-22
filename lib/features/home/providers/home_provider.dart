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
  Timer? _heartbeatTimer;

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
    final savedTrip = await _storageService.getCurrentTrip();
    if (savedTrip != null) {
      // 🔥 VALIDACIÓN EXTRA: Si el viaje guardado no tiene dirección o ID real, bórralo.
      if (savedTrip.id == "0" ||
          savedTrip.originAddress.contains("Origen...")) {
        await _storageService.clearCurrentTrip();
      } else {
        _activeTrip = savedTrip;
        _isOnline = true;
        _startListeningTrips();
        await _calculateRouteForCurrentStatus();
      }
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
    _heartbeatTimer?.cancel(); // Limpiar anterior

    // Timer que avisa al server cada 30 seg aunque estés quieto
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isOnline && _activeTrip == null && _currentPosition != null) {
        _driverRepository.updatePosition(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      }
    });

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

    // 1. VALIDACIÓN PREVIA DE VEHÍCULO
    if (!_isOnline && _selectedVehicle == null) {
      return "⚠️ Debes seleccionar un vehículo para conectarte.";
    }

    // 2. VALIDACIÓN CRÍTICA DE GPS (Evita ser invisible en Redis)
    if (!_isOnline && _currentPosition == null) {
      _isLoading = true;
      notifyListeners();

      // Intentamos obtener la ubicación una última vez antes de fallar
      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        _currentPosition = LatLng(position.latitude, position.longitude);
      } else {
        _isLoading = false;
        notifyListeners();
        return "⚠️ No se pudo obtener tu ubicación GPS. Verifica los permisos.";
      }
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 3. Validar documentos (SOAT/Tecno) antes de conectar
      if (!_isOnline) {
        await _checkDocumentsValidity();
      }

      final String userId = sl<AuthProvider>().user?.id ?? "0";

      // 4. Llamada al servidor enviando OBLIGATORIAMENTE las coordenadas
      final bool success = await _driverRepository.toggleStatus(
        isOnline: !_isOnline,
        driverId: userId,
        vehicleId: _selectedVehicle?.id,
        lat:
            _currentPosition?.latitude, // Ya garantizamos que no es null arriba
        lng: _currentPosition?.longitude,
      );

      if (success) {
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
      } else {
        return "No se pudo actualizar el estado en el servidor.";
      }
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

    // Escuchamos el stream que viene del repositorio de sockets
    _tripSubscription = _tripRepository.listenForTrips().listen((trip) {
      // 1. 🔥 LÓGICA DE CANCELACIÓN EN TIEMPO REAL
      // Si el ID del viaje cancelado coincide con el que el conductor tiene en pantalla
      if (trip.status == TripStatus.CANCELLED) {
        bool esMiOferta = _incomingTrip?.id == trip.id;
        bool esMiViajeActivo = _activeTrip?.id == trip.id;

        if (esMiOferta || esMiViajeActivo) {
          debugPrint(
            "🛑 El viaje ${trip.id} ha sido cancelado. Limpiando UI...",
          );

          _incomingTrip = null;
          _activeTrip = null;
          _routePoints = [];
          _storageService.clearCurrentTrip();

          notifyListeners(); // Esto hace que el aviso desaparezca de la pantalla
        }
        return;
      }

      // 2. Lógica normal para mostrar ofertas nuevas
      if (_activeTrip != null || _incomingTrip != null) return;
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
      final idParaResponder = _incomingTrip!.assignmentId ?? _incomingTrip!.id;

      final acceptedTrip = await _tripRepository.acceptTrip(
        idParaResponder,
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      // --- CAMBIO AQUÍ: Actualizamos estados PRIMERO ---
      _activeTrip = acceptedTrip;
      _incomingTrip = null; // Esto quita el panel de "Oferta" inmediatamente
      _isLoading =
          false; // Quitamos el loading para que el botón no se quede gris

      // Notificamos para que la UI cambie a TripPanelSheet de inmediato
      notifyListeners();

      // --- LUEGO: Guardamos y calculamos la ruta en segundo plano ---
      await _storageService.saveCurrentTrip(_activeTrip!);
      await _calculateRouteForCurrentStatus();
      // (Nota: _calculateRouteForCurrentStatus ya llama a notifyListeners al final)
    } catch (e) {
      debugPrint("Error al aceptar viaje: $e");
      _isLoading = false;
      notifyListeners();
    }
  }

  void rejectIncomingTrip() {
    if (_incomingTrip != null) {
      // 🔥 CAMBIO CLAVE: Usamos assignmentId igual que en aceptar,
      // para que Laravel busque la asignación correcta y no dé 404.
      final idParaResponder = _incomingTrip!.assignmentId ?? _incomingTrip!.id;

      _tripRepository.rejectTrip(idParaResponder);

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
            onPaymentConfirmed: (Trip freshTrip) {
              // C. Callback: El pago fue confirmado (Vía Socket o Vía Efectivo)
              _finalizeTripWithWallet(context, freshTrip);
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
  // Añadimos el parámetro Trip? updatedTrip
  Future<void> _finalizeTripWithWallet(
    BuildContext context,
    Trip? updatedTrip,
  ) async {
    if (_activeTrip == null && updatedTrip == null) return;

    // Si recibimos el viaje actualizado del modal, lo usamos
    if (updatedTrip != null) {
      _activeTrip = updatedTrip;
    }

    try {
      if (context.mounted) {
        // 1. Mantenemos tus llamadas a los otros Providers (Esto quita las advertencias)
        Provider.of<WalletProvider>(
          context,
          listen: false,
        ).registerCompletedTrip(_activeTrip!);
        Provider.of<HistoryProvider>(
          context,
          listen: false,
        ).addFinishedTrip(_activeTrip!);

        // 2. Mi mejora: Formateamos la ganancia dinámica que viene del Backend
        final String gananciaFormateada = _activeTrip!.driverRevenue
            .toStringAsFixed(0)
            .replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (Match m) => '${m[1]}.',
            );

        // 3. Mostramos el SnackBar corregido
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ Viaje finalizado. Tu ganancia neta: \$$gananciaFormateada",
            ),
            backgroundColor: Colors.green[800],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      _finishTrip();
    } catch (e) {
      debugPrint("Error local al cerrar viaje: $e");
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

      // Si tiene éxito, limpiamos normal
      _finishTrip();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Viaje cancelado con éxito")),
        );
      }
    } catch (e) {
      debugPrint("Error cancelando: $e");

      // 🔥 FORZAR LIMPIEZA: Aunque el servidor falle, liberamos al conductor
      _finishTrip();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Estado sincronizado localmente.")),
        );
      }
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
    _heartbeatTimer?.cancel();

    super.dispose();
  }
}
