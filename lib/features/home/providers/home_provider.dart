import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math; // <-- AGREGAR ESTA LÍNEA AL INICIO
import 'package:google_fonts/google_fonts.dart'; // <--- AGREGA ESTA LÍNEA AQUÍ
import '../../../core/theme/app_colors.dart'; // <--- Y ESTA LÍNEA AQUÍ
import '../../../../core/network/api_client.dart';
import 'dart:convert';
import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
import '../repositories/driver_repository.dart';
import '../repositories/trip_repository.dart';

// --------------------------------------------------------
// IMPORTS MODULOS EXTERNOS (Wallet, History, Widgets)
// --------------------------------------------------------
import '../../wallet/providers/wallet_provider.dart';
import '../../history/providers/history_provider.dart';
import '../widgets/payment_waiting_sheet.dart'; // <--- WIDGET DE PAGO
import '../../auth/providers/auth_provider.dart';
import '../../maps/services/route_service.dart'; // <--- SERVICIO DE RUTAS (OSRM)

class HomeProvider extends ChangeNotifier {
  // 1. INYECCIÓN DE DEPENDENCIAS
  final LocationService _locationService = sl<LocationService>();
  final StorageService _storageService = sl<StorageService>();
  final DriverRepository _driverRepository = sl<DriverRepository>();
  final TripRepository _tripRepository = sl<TripRepository>();
  final RouteService _routeService = RouteService(); // Instanciamos aquí

  HomeProvider();

  // 2. ESTADO
  bool _isOnline = false;
  bool _isLoading = false;
  String? _lastRejectedTripId;
  // Añade estos Getters en HomeProvider.dart
  double get activeTripDistance => _activeTrip?.distanceKm ?? 0.0;
  // --- VARIABLES PARA CÁLCULO LOCAL DE RUTA (AHORRO API) ---

  // Ubicación y Rotación
  LatLng? _currentPosition;
  double _currentHeading = 0.0;
  // Almacena la ubicación GPS en tiempo real enviada por el pasajero
  // En home_provider.dart, añade este getter debajo de los otros:
  double get incomingDistance => _incomingDistance;
  // Para saber qué ruta estamos mostrando
  String _incomingTripEta = "--";
  // Viaje
  Trip? _incomingTrip;
  Trip? _activeTrip;
  set activeTrip(Trip? trip) {
    _updateActiveTripWithPreservation(trip);
    notifyListeners();
  }

  // 1. Calcula el rumbo matemático exacto entre los movimientos del GPS local
  double _calculateBearing(LatLng start, LatLng end) {
    double startLat = start.latitude * (math.pi / 180.0);
    double startLng = start.longitude * (math.pi / 180.0);
    double endLat = end.latitude * (math.pi / 180.0);
    double endLng = end.longitude * (math.pi / 180.0);

    double dLng = endLng - startLng;

    double y = math.sin(dLng) * math.cos(endLat);
    double x =
        math.cos(startLat) * math.sin(endLat) -
        math.sin(startLat) * math.cos(endLat) * math.cos(dLng);

    double bearing = math.atan2(y, x) * (180.0 / math.pi);
    return (bearing + 360.0) % 360.0;
  }

  // 3. Mantén el getter igual
  Trip? get activeTrip => _activeTrip;
  List<LatLng> _routePoints = [];
  set routePoints(List<LatLng> value) {
    _routePoints = value;
    notifyListeners();
  }

  double _totalRouteDistanceMeters = 0.0;
  double _totalRouteDurationSeconds = 0.0;
  // Vehículos y Documentos (FUEC)
  List<Vehicle> _myVehicles = [];
  Vehicle? _selectedVehicle;
  List<DriverDocument> _documents = [];

  // Subscriptions
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription? _tripSubscription;

  // 3. GETTERS PÚBLICOS
  double _incomingDistance = 0;

  bool get isOnline => _isOnline;
  bool get isLoading => _isLoading;
  LatLng? get currentPosition => _currentPosition;
  double get currentHeading => _currentHeading;
  Trip? get incomingTrip => _incomingTrip;
  List<LatLng> get routePoints => _routePoints;
  List<Vehicle> get myVehicles => _myVehicles;
  Vehicle? get selectedVehicle => _selectedVehicle;
  Timer? _heartbeatTimer;
  double _balance = 0.0;
  Timer? _validationTimer;
  String get incomingTripEta => _incomingTripEta;
  Timer? _routeRecalculateTimer;
  // --- VARIABLES PARA MOTOR DE TRAZADO DINÁMICO (AHORRO Y PRECISIÓN) ---
  // --- VARIABLES PARA CÁLCULO LOCAL DE RUTA (AHORRO API) ---
  // --- VARIABLES PARA MOTOR DE TRAZADO DINÁMICO (AHORRO Y PRECISIÓN) ---

  void _startRouteRecalculationTimer() {
    _routeRecalculateTimer?.cancel();
    _routeRecalculateTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) {
      if (_activeTrip != null) {
        _calculateRouteForCurrentStatus();
      } else {
        _stopRouteRecalculationTimer();
      }
    });
  }

  void _stopRouteRecalculationTimer() {
    _routeRecalculateTimer?.cancel();
    _routeRecalculateTimer = null;
  }

  void _showError(String message) {
    debugPrint("🚩 ERROR: $message");
    // Si quieres que aparezca un SnackBar, necesitarías pasar el context
    // o usar un GlobalKey<ScaffoldMessengerState>
  }

  double get balance => _balance; // Necesario para el bloqueo
  void updateBalance(double newBalance) {
    _balance = newBalance;
    notifyListeners();
  }

  // Agrega este método dentro de tu clase HomeProvider:
  // Reemplace el método anterior en home_provider.dart por este real:
  Future<void> addExtraWaitingTime(int minutes) async {
    // Asegura que tengamos un viaje activo antes de proceder
    final trip = activeTrip; // o _activeTrip, según cómo lo tenga definido
    if (trip == null) return;

    _isLoading = true; // o la variable de carga que maneje su provider
    notifyListeners();

    try {
      // Usamos el cliente HTTP global con sus interceptores de autorización Bearer
      final dio = ApiClient().dio;

      final response = await dio.post(
        '/viajes/${trip.id}/adicionar-tiempo',
        data: {'minutos': minutes},
      );

      if (response.statusCode == 200) {
        debugPrint("🟢 Tiempo extra registrado con éxito en el backend.");
      } else {
        throw Exception(
          "El servidor retornó un código de estado: ${response.statusCode}",
        );
      }
    } catch (e) {
      debugPrint("🚨 Error al conectar con el endpoint de tiempo extra: $e");
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Variable privada que almacenará el GPS en tiempo real cuando se reciba
  LatLng? _passengerLocation;
  bool _hasReceivedPassengerGps =
      false; // Guardián de señal de socket en tiempo real

  // Propiedad que lee Flutter: si no hay GPS en tiempo real aún,
  // usa automáticamente el punto de encuentro con un desfase de prueba si está en ARRIVED
  LatLng? get passengerLocation {
    if (_passengerLocation == null) return null;

    // Si estamos esperando en el sitio pero el socket en vivo no ha reportado señal aún,
    // desplazamos visualmente al pasajero ~45 metros para que la línea de bolitas y el marcador
    // se aprecien perfectamente desde el primer instante en tus pruebas.
    if (!_hasReceivedPassengerGps &&
        _activeTrip != null &&
        _activeTrip!.status == TripStatus.ARRIVED) {
      return LatLng(
        _passengerLocation!.latitude + 0.00035,
        _passengerLocation!.longitude + 0.00035,
      );
    }
    return _passengerLocation;
  }

  // Permite actualizar el GPS en tiempo real y notificar a la interfaz
  set passengerLocation(LatLng? value) {
    _passengerLocation = value;
    notifyListeners();
  }

  // 2. Método para limpiar el timer cuando ya no haga falta
  void _stopValidationTimer() {
    _validationTimer?.cancel();
    _validationTimer = null;
  }

  // Método para asegurar que no se pierdan datos críticos (como el teléfono)
  // en las respuestas simplificadas de cambio de estado del servidor.
  void _updateActiveTripWithPreservation(Trip? newTrip) {
    if (newTrip == null) {
      _activeTrip = null;
      return;
    }

    if (_activeTrip != null && _activeTrip!.id == newTrip.id) {
      final oldTrip = _activeTrip!;
      final bool statusChanged = oldTrip.status != newTrip.status;

      _activeTrip = newTrip.copyWith(
        passengerPhone:
            (newTrip.passengerPhone == null || newTrip.passengerPhone!.isEmpty)
            ? oldTrip.passengerPhone
            : newTrip.passengerPhone,
        passengers: newTrip.passengers.isEmpty
            ? oldTrip.passengers
            : newTrip.passengers,
        fuecUrl: (newTrip.fuecUrl == null || newTrip.fuecUrl!.isEmpty)
            ? oldTrip.fuecUrl
            : newTrip.fuecUrl,
      );

      // Si cambió el estado, reseteamos la polilínea y métricas para forzar recálculo fresco
      if (statusChanged) {
        _routePoints = [];
        _totalRouteDistanceMeters = 0.0;
        _totalRouteDurationSeconds = 0.0;
      }
    } else {
      _activeTrip = newTrip;
      _routePoints = [];
      _totalRouteDistanceMeters = 0.0;
      _totalRouteDurationSeconds = 0.0;
    }
  }

  // 3. Método de validación que llamaremos al recibir una oferta
  void _startValidationTimer(String assignmentId) {
    _stopValidationTimer();

    _validationTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      // Si no hay oferta, matamos el timer
      if (_incomingTrip == null) {
        _stopValidationTimer();
        return;
      }

      // Consultamos al servidor si esa asignación sigue pendiente
      try {
        final response = await _tripRepository.checkAssignmentStatus(
          assignmentId,
        );
        if (response == 'CANCELLED') {
          debugPrint(
            "🧹 [VALIDACIÓN] El servidor confirma que el viaje ya no existe.",
          );
          _incomingTrip = null;
          _stopValidationTimer();
          notifyListeners(); // Esto cerrará el modal automáticamente
        }
      } catch (e) {
        debugPrint("Error validando oferta: $e");
      }
    });
  }

  Future<void> calculateIncomingTripRoute() async {
    if (currentPosition == null || incomingTrip == null) return;

    try {
      final routeResult = await _routeService.getRoute(
        currentPosition!,
        incomingTrip!.originLocation,
      );
      _incomingDistance = routeResult.distanceMeters.toDouble();

      // 🔥 CAMBIO: Solo asignamos los puntos si NO hay viaje entrante
      // O si quieres borrarlos:
      if (incomingTrip != null) {
        // Si hay oferta, NO guardamos los puntos en la lista global que usa el mapa
        // Pero si quieres que el conductor la vea luego de aceptar,
        // esto es lo que está pasando.
      }

      // Si quieres que el mapa esté vacío mientras llega la oferta:
      routePoints = [];

      int minutes = (routeResult.durationSeconds / 60).round();
      _incomingTripEta = minutes > 0 ? "$minutes min" : "Llegando";

      notifyListeners();
    } catch (e) {
      debugPrint("Error calculando ruta: $e");
    }
  }

  // --- AÑADIR DESPUÉS DE LA LÍNEA 65 ---
  double get remainingDistanceMeters {
    if (_currentPosition == null || _activeTrip == null) return 0.0;
    const Distance distance = Distance();

    LatLng target =
        (_activeTrip!.status == TripStatus.ACCEPTED ||
            _activeTrip!.status == TripStatus.ARRIVED)
        ? _activeTrip!.originLocation
        : _activeTrip!.destinationLocation;

    return distance.as(LengthUnit.Meter, _currentPosition!, target);
  }

  // Getter de distancia formateado dinámico (Alineado al 100% con Pasajero)
  String get distanceToTarget {
    if (_currentPosition == null || _activeTrip == null) return "---";

    LatLng target = _activeTrip!.status == TripStatus.STARTED
        ? (_routePoints.isNotEmpty
              ? _routePoints.last
              : _activeTrip!.destinationLocation)
        : _activeTrip!.originLocation;

    double streetMeters = 0.0;

    if (_routePoints.isNotEmpty) {
      // Distancia desde el auto hasta el primer punto de la polilínea restante
      streetMeters += Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _routePoints.first.latitude,
        _routePoints.first.longitude,
      );

      // Suma de los segmentos restantes de la polilínea
      for (int i = 0; i < _routePoints.length - 1; i++) {
        streetMeters += Geolocator.distanceBetween(
          _routePoints[i].latitude,
          _routePoints[i].longitude,
          _routePoints[i + 1].latitude,
          _routePoints[i + 1].longitude,
        );
      }
    } else {
      // Fallback por si la ruta de OSRM aún no ha cargado
      double straightMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        target.latitude,
        target.longitude,
      );
      streetMeters = straightMeters * 1.43;
    }

    if (streetMeters <= 0) return "---";
    if (streetMeters < 1000) {
      return "${streetMeters.toStringAsFixed(0)} m";
    } else {
      return "${(streetMeters / 1000).toStringAsFixed(1)} km";
    }
  }

  // Getter de duración dinámico (Sincronizado con Pasajero y Google Maps)
  double get activeTripDuration {
    if (_currentPosition == null || _activeTrip == null) return 0.0;

    LatLng target = _activeTrip!.status == TripStatus.STARTED
        ? (_routePoints.isNotEmpty
              ? _routePoints.last
              : _activeTrip!.destinationLocation)
        : _activeTrip!.originLocation;

    double streetMeters = 0.0;

    if (_routePoints.isNotEmpty) {
      streetMeters += Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _routePoints.first.latitude,
        _routePoints.first.longitude,
      );
      for (int i = 0; i < _routePoints.length - 1; i++) {
        streetMeters += Geolocator.distanceBetween(
          _routePoints[i].latitude,
          _routePoints[i].longitude,
          _routePoints[i + 1].latitude,
          _routePoints[i + 1].longitude,
        );
      }
    } else {
      double straightMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        target.latitude,
        target.longitude,
      );
      streetMeters = straightMeters * 1.43;
    }

    // Filtro para evitar residuos de la fase de recogida
    bool isStale =
        _activeTrip!.status == TripStatus.STARTED &&
        (_totalRouteDistanceMeters < streetMeters ||
            _totalRouteDistanceMeters <= 500.0);

    double calculatedMinutes;
    if (_totalRouteDistanceMeters > 0 &&
        _totalRouteDurationSeconds > 0 &&
        !isStale) {
      double ratio = streetMeters / _totalRouteDistanceMeters;
      if (ratio > 1.0) ratio = 1.0;
      if (ratio < 0.0) ratio = 0.0;
      calculatedMinutes = (_totalRouteDurationSeconds * ratio) / 60.0;
    } else {
      // Velocidad unificada de estimación real en ciudad con tráfico a 13.5 km/h (225 metros/minuto)
      // Esto garantiza sincronización perfecta con Google Maps (4 min para ~850-900 metros)
      calculatedMinutes = streetMeters / 225.0;
    }

    if (streetMeters < 30) {
      return 0.0;
    }

    int mins = calculatedMinutes.round();
    if (streetMeters > 0 && mins < 1) mins = 1;

    return mins.toDouble();
  }
  // =======================================================
  // A. INICIALIZACIÓN Y GPS
  // =======================================================

  // En tu método initLocation dentro de HomeProvider.dart
  Future<void> initLocation() async {
    _isLoading = true;
    notifyListeners();
    await loadVehicles();

    // AQUÍ ESTABA EL ERROR:
    // Debes obtener la instancia de AuthProvider primero
    final authProvider = sl<AuthProvider>();
    final wallet = sl<WalletProvider>();

    // Ahora sí, usa authProvider.user
    if (authProvider.user != null) {
      await wallet.loadWalletData();
      _balance = wallet.balance;

      wallet.addListener(() {
        if (_balance != wallet.balance) {
          _balance = wallet.balance;
          notifyListeners();
        }
      });
      _startListeningWalletUpdates(authProvider.user!.id);
    }
    final savedTrip = await _storageService.getCurrentTrip();
    if (savedTrip != null) {
      final tripReal = await _tripRepository.getActiveTrip();

      if (tripReal != null && tripReal.id == savedTrip.id) {
        // Preservamos teléfono, pasajeros y FUEC del storage local si la API remota viene simplificada
        _activeTrip = tripReal.copyWith(
          passengerPhone:
              (tripReal.passengerPhone == null ||
                  tripReal.passengerPhone!.isEmpty)
              ? savedTrip.passengerPhone
              : tripReal.passengerPhone,
          passengers: tripReal.passengers.isEmpty
              ? savedTrip.passengers
              : tripReal.passengers,
          fuecUrl: (tripReal.fuecUrl == null || tripReal.fuecUrl!.isEmpty)
              ? savedTrip.fuecUrl
              : tripReal.fuecUrl,
        );
        _isOnline = true;
        _startListeningTrips();

        // --- INICIALIZACIÓN ÚNICA DE PARTIDA ---
        _passengerLocation = tripReal.originLocation;

        _startPassengerGpsListener(_activeTrip!.id);
        _startRouteRecalculationTimer(); // <--- AGREGADO AQUÍ

        await _calculateRouteForCurrentStatus();
      } else {
        await _storageService.clearCurrentTrip();
        _activeTrip = null;
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

      // 1. Si está ONLINE pero NO está en un servicio, enviar posición de disponibilidad
      if (_isOnline && _activeTrip == null && dist > 10.0) {
        _driverRepository.updatePosition(pos.latitude, pos.longitude);
      }

      // 2. Si está en un viaje activo, transmitir la ubicación y actualizar la ruta
      if (_activeTrip != null) {
        final bool enServicioActivo =
            _activeTrip!.status == TripStatus.ACCEPTED ||
            _activeTrip!.status == TripStatus.ARRIVED ||
            _activeTrip!.status == TripStatus.STARTED;

        if (enServicioActivo && dist > 5.0) {
          _tripRepository.updateLocation(
            _activeTrip!.id,
            pos.latitude,
            pos.longitude,
          );

          // --- CORRECCIÓN: Recalcular la ruta OSRM en tiempo real al avanzar ---
          _calculateRouteForCurrentStatus();
        }
      }

      // --- Estabilización del ángulo del vehículo (Rumbo Vectorial) ---
      if (dist > 1.5) {
        _currentHeading = _calculateBearing(_currentPosition!, newLocation);
      } else if (pos.heading > 0) {
        _currentHeading = pos.heading;
      }
    }

    _currentPosition = newLocation;
    notifyListeners();
  } // =======================================================

  Future<void> loadVehicles() async {
    // BORRA O COMENTA ESTA LÍNEA:
    // if (_myVehicles.isNotEmpty) return;

    try {
      _isLoading = true;
      notifyListeners();
      final String userId = sl<AuthProvider>().user?.id ?? "0";
      _myVehicles = await _driverRepository.getAssignedVehicles(userId);

      if (_myVehicles.isNotEmpty) {
        // Si no hay vehículo seleccionado, auto-selecciona el primero
        if (_selectedVehicle == null) {
          _selectedVehicle = _myVehicles.first;
        } else {
          // Opcional: Verifica si el seleccionado sigue existiendo
          bool existe = _myVehicles.any((v) => v.id == _selectedVehicle!.id);
          if (!existe) _selectedVehicle = _myVehicles.first;
        }
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Dentro de tu HomeProvider.dart
  Future<void> initActiveTrip() async {
    try {
      // CAMBIO: En lugar de _apiService, usa el repositorio existente
      // Asumiendo que tu TripRepository tiene un método para buscar el viaje activo
      final tripData = await _tripRepository.getActiveTrip();

      if (tripData != null) {
        _activeTrip =
            tripData; // Como el repositorio ya devuelve un objeto Trip, no necesitas .fromMap
        notifyListeners();
      } else {
        _activeTrip = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error refrescando viaje activo: $e");
      // Si falla (por 404 o red), limpiamos
      _activeTrip = null;
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
          debugPrint("🟢 LISTENER DE VIAJES INICIADO");
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

  // En tu HomeProvider.dart, localiza _startListeningTrips y añade el punto "."
  void _startListeningTrips() {
    _tripSubscription?.cancel();

    _tripSubscription = _tripRepository.listenForTrips().listen((trip) {
      try {
        debugPrint("📡 [SOCKET] Evento: ${trip.status} para viaje ${trip.id}");
        // ignore: unrelated_type_equality_checks
        if (trip.status == 'NO_DISPONIBLE' && _incomingTrip?.id == trip.id) {
          debugPrint("🧹 [SOCKET] Limpiando alerta: viaje tomado por otro.");
          _incomingTrip = null;
          notifyListeners(); // Esto le dirá a Flutter que reconstruya la UI sin el modal
          return;
        }

        if (trip.status == TripStatus.CANCELLED ||
            trip.status == TripStatus.COMPLETED) {
          debugPrint("🛑 [SOCKET] Limpieza controlada.");
          _finishTrip();
          return;
        }

        if (trip.status == TripStatus.ACCEPTED) {
          _updateActiveTripWithPreservation(trip);
          _incomingTrip = null;
          notifyListeners();
        } else if (trip.status == TripStatus.PENDING) {
          // BLINDAJE: Si es el mismo viaje que acabamos de rechazar, ignoramos el evento
          if (_lastRejectedTripId == trip.id) {
            debugPrint(
              "⚠️ [SOCKET] Ignorando evento PENDING de viaje recientemente rechazado.",
            );
            return;
          }

          debugPrint("ℹ️ [SOCKET] Nueva oferta PENDING detectada: ${trip.id}");
          _incomingTrip = trip;
          calculateIncomingTripRoute();

          // BLINDAJE: Verificamos que el viaje tenga datos mínimos antes de notificar
          if (_incomingTrip != null) {
            _startValidationTimer(
              _incomingTrip!.assignmentId ?? _incomingTrip!.id,
            );
            notifyListeners();
          }
        }
      } catch (e, stackTrace) {
        debugPrint("🚨 [CRITICO] Error procesando evento de socket: $e");
        debugPrint(stackTrace.toString()); // Esto nos dirá qué widget colapsó
      }
    });
  }

  void _stopListeningTrips() {
    _tripSubscription?.cancel();
    _incomingTrip = null;
    notifyListeners();
  }

  bool get puedeAceptarViajes {
    // Accedemos al valor actual de la billetera
    // Nota: Si WalletProvider es accesible, obtenemos su valor
    final wallet = sl<WalletProvider>();
    return wallet.balance > -20000;
  }

  Future<void> acceptIncomingTrip() async {
    if (!puedeAceptarViajes) {
      _showError("Tu saldo es muy bajo. Recarga para continuar.");
      return;
    }
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

      _activeTrip = acceptedTrip;
      _incomingTrip = null;
      _isLoading = false;

      // --- INICIALIZACIÓN ÚNICA DE PARTIDA ---
      _passengerLocation = acceptedTrip.originLocation;

      _startPassengerGpsListener(_activeTrip!.id);
      _startRouteRecalculationTimer(); // <--- AGREGADO AQUÍ

      notifyListeners();

      await _storageService.saveCurrentTrip(_activeTrip!);
      await _calculateRouteForCurrentStatus();
    } catch (e) {
      debugPrint("Error al aceptar viaje: $e");
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> rejectIncomingTrip() async {
    if (_incomingTrip == null) return;

    // Guardamos el ID antes de limpiar
    _lastRejectedTripId = _incomingTrip!.id;

    try {
      final idParaResponder = _incomingTrip!.assignmentId ?? _incomingTrip!.id;
      await _tripRepository.rejectTrip(idParaResponder);

      _incomingTrip = null;
      notifyListeners();
    } catch (e) {
      debugPrint("Error: $e");
    }

    // Limpiamos el filtro después de unos segundos
    Future.delayed(
      const Duration(seconds: 5),
      () => _lastRejectedTripId = null,
    );
  }

  PusherChannelsClient? _passengerPusherClient;
  StreamSubscription? _passengerGpsSubscription;

  void _startPassengerGpsListener(String tripId) async {
    _passengerGpsSubscription?.cancel();
    _passengerPusherClient?.disconnect();

    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'auth_token');
    if (token == null) return;

    _passengerPusherClient = PusherChannelsClient.websocket(
      options: PusherChannelsOptions.fromHost(
        scheme: 'wss',
        host: 'api.vamosapp.com.co',
        port: 443,
        key: '06exymiubefjjglwmvqe',
      ),
      connectionErrorHandler: (exception, trace, client) {
        debugPrint(
          "🚨 Error de Sockets en Conductor (Rastreo Pasajero): $exception",
        );
      },
    );

    _passengerPusherClient!.eventStream.listen((event) {
      if (event.name == 'pusher:connection_established') {
        debugPrint("✅ Conectado a Reverb para rastreo de pasajero.");

        final channel = _passengerPusherClient!.privateChannel(
          'private-viaje.$tripId',
          authorizationDelegate: DriverPusherAuth(token: token),
        );

        channel.subscribe();

        _passengerGpsSubscription = channel.bind('PasajeroTracking').listen((
          e,
        ) {
          if (e.data != null) {
            try {
              final data = json.decode(e.data!);
              final double lat = double.parse(data['lat'].toString());
              final double lng = double.parse(data['lng'].toString());

              // ACTIVAR ENTRADA DE DATOS REALES
              _hasReceivedPassengerGps = true;

              // Actualiza la posición y notifica a HomeScreen del conductor
              passengerLocation = LatLng(lat, lng);
            } catch (ex) {
              debugPrint(
                "Error procesando GPS de pasajero en tiempo real: $ex",
              );
            }
          }
        });
      }
    });

    _passengerPusherClient!.connect();
  }

  void _stopPassengerGpsListener() {
    _passengerGpsSubscription?.cancel();
    _passengerGpsSubscription = null;
    _passengerPusherClient?.disconnect();
    _passengerLocation = null;
    _hasReceivedPassengerGps = false; // <- AGREGAR ESTA LÍNEA AQUÍ
  }

  /// --- NUEVO: Lógica unificada de cancelación (Conductor) ---
  Future<void> cancelTripAsDriver(String tripId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Usamos updateTripStatus que ya tienes configurado para 'CANCELLED'
      await _tripRepository.updateTripStatus(tripId, 'CANCELLED');

      // Limpieza post-cancelación
      _finishTrip(); // Este método ya lo tienes y limpia variables y notifica
    } catch (e) {
      debugPrint("Error al cancelar: $e");
      // Si falla en servidor, limpiamos localmente por seguridad
      _finishTrip();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // =======================================================
  // E. MÁQUINA DE ESTADOS Y COBRO (LÓGICA CRÍTICA)
  // =======================================================

  /// Método principal llamado por el botón grande del panel
  /// Método principal llamado por el botón grande del panel
  Future<void> handleTripAction(BuildContext context) async {
    if (_activeTrip == null) return;

    // --- BLINDAJE DE DISTANCIA AL MARCAR LLEGADA al sitio (Estado ACCEPTED -> ARRIVED) ---
    if (_activeTrip!.status == TripStatus.ACCEPTED) {
      if (_currentPosition == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "No se pudo validar tu ubicación GPS actual. Espera un momento.",
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      // Calculamos la distancia en metros entre el conductor y el origen del viaje
      const Distance distance = Distance();
      final double distanceInMeters = distance.as(
        LengthUnit.Meter,
        _currentPosition!,
        _activeTrip!.originLocation,
      );

      // Si está a más de 100 metros, mostramos alerta y bloqueamos el avance de estado
      if (distanceInMeters > 100.0) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: const Color(0xFF1F2937),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_off_rounded,
                    color: AppColors.primaryGreen,
                    size: 50,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Demasiado lejos",
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Estás a ${distanceInMeters.toStringAsFixed(0)} metros. Para marcar tu llegada, debes acercarte a menos de 100 metros del punto de recogida.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      color: Colors.grey[300],
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.primaryGreen, // Verde esmeralda premium
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        "ENTENDIDO",
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return; // Bloquea la ejecución y no avanza el estado
      }
    }

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

      _updateActiveTripWithPreservation(updatedTrip);
      await _storageService.saveCurrentTrip(_activeTrip!);
      _routePoints = [];

      await _calculateRouteForCurrentStatus();
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
              "Viaje finalizado. Tu ganancia neta: \$$gananciaFormateada",
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
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );

      _updateActiveTripWithPreservation(updatedTrip);
      await _storageService.saveCurrentTrip(_activeTrip!);

      // Limpiamos referencias de polilínea para forzar cálculo fresco en el nuevo estado
      _routePoints = [];

      await _calculateRouteForCurrentStatus();
      notifyListeners();
      return _activeTrip;
    } catch (e) {
      debugPrint("Error actualizando estado: $e");
      rethrow;
    }
  }

  void _finishTrip() {
    debugPrint("DEBUG: _finishTrip ejecutado.");

    _stopPassengerGpsListener();
    _stopRouteRecalculationTimer();

    _activeTrip = null;
    _routePoints = [];

    _storageService.clearCurrentTrip();
    _startListeningTrips();
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
    if (_activeTrip!.status == TripStatus.ACCEPTED ||
        _activeTrip!.status == TripStatus.ARRIVED) {
      destination = _activeTrip!.originLocation; // Punto de recogida
    } else if (_activeTrip!.status == TripStatus.STARTED) {
      destination = _activeTrip!.destinationLocation; // Destino final
    }

    if (destination == null) return;

    double straightToTarget = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      destination.latitude,
      destination.longitude,
    );

    bool isStale =
        _activeTrip!.status == TripStatus.STARTED &&
        (_totalRouteDistanceMeters < straightToTarget ||
            _totalRouteDistanceMeters <= 500.0);

    // 1. Trazado inicial: Si no hay ruta en memoria o detectamos datos obsoletos (stale)
    if (_routePoints.isEmpty || isStale) {
      try {
        final routeResult = await _routeService
            .getRoute(_currentPosition!, destination)
            .timeout(const Duration(seconds: 5));

        _routePoints = routeResult.points;
        _totalRouteDistanceMeters = routeResult.distanceMeters.toDouble();
        _totalRouteDurationSeconds = routeResult.durationSeconds.toDouble();
        notifyListeners();
      } catch (e) {
        debugPrint("Error obteniendo ruta inicial del viaje (Conductor): $e");
      }
      return;
    }

    // 2. Medir desvío
    int closestIndex = 0;
    double minDistanceToRoute = double.infinity;

    for (int i = 0; i < _routePoints.length; i++) {
      double d = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        _routePoints[i].latitude,
        _routePoints[i].longitude,
      );
      if (d < minDistanceToRoute) {
        minDistanceToRoute = d;
        closestIndex = i;
      }
    }

    if (minDistanceToRoute > 250.0) {
      try {
        final routeResult = await _routeService
            .getRoute(_currentPosition!, destination)
            .timeout(const Duration(seconds: 5));

        _routePoints = routeResult.points;
        _totalRouteDistanceMeters = routeResult.distanceMeters.toDouble();
        _totalRouteDurationSeconds = routeResult.durationSeconds.toDouble();
        notifyListeners();
      } catch (e) {
        debugPrint("Error recalculando desvío en ruta (Conductor): $e");
      }
      return;
    }

    // 3. Borrado local del trayecto recorrido
    if (closestIndex < _routePoints.length) {
      _routePoints = _routePoints.sublist(closestIndex);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _tripSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _stopPassengerGpsListener(); // <--- AGREGUE ESTA LÍNEA AQUÍ
    _stopRouteRecalculationTimer(); // <--- AGREGADO AQUÍ

    super.dispose();
  }
}

class DriverPusherAuth
    implements
        EndpointAuthorizableChannelAuthorizationDelegate<
          PrivateChannelAuthorizationData
        > {
  final String token;
  DriverPusherAuth({required this.token});

  @override
  EndpointAuthFailedCallback? get onAuthFailed =>
      (exception, trace) =>
          debugPrint("Error Auth Sockets Conductor: $exception");

  @override
  Future<PrivateChannelAuthorizationData> authorizationData(
    String socketId,
    String channelName,
  ) async {
    final dio = ApiClient().dio;
    try {
      final response = await dio.post(
        '/broadcasting/auth',
        data: {'socket_id': socketId, 'channel_name': channelName},
      );
      return PrivateChannelAuthorizationData(
        authKey: response.data['auth'] ?? '',
      );
    } catch (e) {
      debugPrint("🚨 Error en autenticación de sockets del conductor: $e");
      rethrow;
    }
  }
}
