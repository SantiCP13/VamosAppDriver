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
import 'dart:io'; // <--- RESUELVE EL ERROR DE 'File'
import '../../../core/services/notification_service.dart'; // <--- RESUELVE EL ERROR DE 'NotificationService'
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
  bool _extraWaitingTimeAdded = false;
  bool get extraWaitingTimeAdded => _extraWaitingTimeAdded;
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

  // --- VARIABLES DE ROBUSTEZ Y CONEXIÓN (Estilo Uber/DiDi) ---
  bool _isNetworkDisconnected = false;
  bool get isNetworkDisconnected => _isNetworkDisconnected;

  bool _isGpsSignalLost = false;
  bool get isGpsSignalLost => _isGpsSignalLost;

  Timer? _networkMonitorTimer;
  // --- NUEVAS VARIABLES PARA EL CONTROL DE TURNOS (3 ESTADOS) ---
  String _turnoEstado = 'OFFLINE'; // Valores: 'OFFLINE', 'ACTIVO', 'BREAK'
  int _breakSecondsRemaining = 900; // 15 minutos en segundos (15 * 60 = 900)
  Timer? _breakTimer;
  DateTime? _breakStartTime;
  // En HomeProvider.dart:
  bool _alreadyHadLunch = false;
  bool get alreadyHadLunch => _alreadyHadLunch;
  String get turnoEstado => _turnoEstado;
  int get breakSecondsRemaining => _breakSecondsRemaining;

  // Formateador para mostrar el tiempo del break en formato MM:SS
  String get breakTimerFormated {
    final minutes = (_breakSecondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_breakSecondsRemaining % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  int _waitSeconds = 300; // 5 minutos por defecto
  int get waitSeconds => _waitSeconds;
  Timer? _waitTimer;
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
  // En HomeProvider.dart:

  // Temporizador para el almuerzo
  int _lunchSecondsRemaining = 3600; // 1 hora
  Timer? _lunchTimer;
  DateTime? _lunchStartTime;

  int get lunchSecondsRemaining => _lunchSecondsRemaining;

  String get lunchTimerFormated {
    final hours = (_lunchSecondsRemaining ~/ 3600).toString().padLeft(2, '0');
    final minutes = ((_lunchSecondsRemaining % 3600) ~/ 60).toString().padLeft(
      2,
      '0',
    );
    final seconds = (_lunchSecondsRemaining % 60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  /// Realiza un ping rápido a nivel de sockets para confirmar conectividad real
  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup(
        'dns.google',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Cambia el estado de red de forma segura y notifica al UI
  void _setNetworkDisconnected(bool value) {
    if (_isNetworkDisconnected != value) {
      _isNetworkDisconnected = value;
      notifyListeners();
    }
  }

  /// Monitor constante que se ejecuta periódicamente para forzar la reconexión
  void _startNetworkMonitor() {
    _networkMonitorTimer?.cancel();
    _networkMonitorTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) async {
      final hasInternet = await _hasInternetConnection();
      _setNetworkDisconnected(!hasInternet);

      // Si se recupera la conexión y el conductor está online, sincronizar ubicación de inmediato
      if (hasInternet && _isOnline && _currentPosition != null) {
        if (_activeTrip != null) {
          _sendTripLocationToBackend(
            _activeTrip!.id,
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            0.0,
          );
        } else {
          _sendPositionToBackend(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
        }
      }
    });
  }

  void _stopNetworkMonitor() {
    _networkMonitorTimer?.cancel();
    _networkMonitorTimer = null;
  }

  void _startLunchTimer() {
    _lunchTimer?.cancel();
    _lunchSecondsRemaining = 3600;
    _lunchStartTime = DateTime.now();

    // Notificación nativa programada para 1 hora
    NotificationService.scheduleNotification(
      id: 888,
      title: "🍔 ¡Fin de tu hora de Almuerzo!",
      body: "Tu descanso de almuerzo ha finalizado. Debes reanudar tu turno.",
      delay: const Duration(hours: 1), // O segundos para pruebas rápidas
    );

    _lunchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lunchStartTime != null) {
        final elapsed = DateTime.now().difference(_lunchStartTime!).inSeconds;
        _lunchSecondsRemaining = 3600 - elapsed;

        if (_lunchSecondsRemaining <= 0) {
          _lunchSecondsRemaining = 0;
          _stopLunchTimer();

          NotificationService.showNotification(
            id: 888,
            title: "🍔 ¡Fin de tu hora de Almuerzo!",
            body: "Reanuda tu turno para continuar prestando servicios.",
          );
        }
        notifyListeners();
      }
    });
  }

  void _stopLunchTimer() {
    _lunchTimer?.cancel();
    _lunchTimer = null;
    _lunchStartTime = null;
    NotificationService.cancelNotification(888);
    notifyListeners();
  }

  /// Acción para Iniciar Almuerzo
  Future<String?> iniciarAlmuerzo() async {
    if (_isLoading) return null;
    _isLoading = true;
    notifyListeners();

    try {
      final position = await _locationService.getCurrentLocation();
      // Asegúrate de castear el repositorio a ApiDriverRepository si es necesario o declararlo en la interfaz
      final res = await _driverRepository.iniciarAlmuerzo(
        lat: position?.latitude ?? _currentPosition?.latitude,
        lng: position?.longitude ?? _currentPosition?.longitude,
      );

      if (res['status'] == 'success') {
        _turnoEstado = 'ALMUERZO';
        _isOnline = false;
        _alreadyHadLunch = true; // 🟢 ALMUERZO UTILIZADO

        _stopTracking();
        _stopListeningTrips();

        // Iniciar reloj de 1 hora
        _startLunchTimer();

        _isLoading = false;
        notifyListeners();
        return null;
      }
      return "No se pudo registrar tu almuerzo.";
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return e.toString().replaceAll("Exception: ", "");
    }
  }

  // Modifica reanudarTurnoCompleto() para apagar el temporizador de almuerzo si estaba activo:
  Future<String?> reanudarTurnoCompleto() async {
    if (_isLoading) return null;
    _isLoading = true;
    notifyListeners();

    try {
      final position = await _locationService.getCurrentLocation();
      final res = await _driverRepository.reanudarTurno(
        lat: position?.latitude ?? _currentPosition?.latitude,
        lng: position?.longitude ?? _currentPosition?.longitude,
      );

      if (res['status'] == 'success') {
        _turnoEstado = 'ACTIVO';
        _isOnline = true;

        // 🟢 Apagar temporizadores de pausa y de almuerzo de forma segura
        _stopBreakTimer();
        _stopLunchTimer();

        _startListeningTrips();
        _startTracking();

        _isLoading = false;
        notifyListeners();
        return null;
      }
      return "No se pudo reanudar el turno.";
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return e.toString().replaceAll("Exception: ", "");
    }
  }

  /// Inicia el temporizador de cuenta regresiva del break (CONFIGURADO A 10 SEGUNDOS PARA PRUEBA)
  void _startBreakTimer() {
    _breakTimer?.cancel();
    _breakSecondsRemaining = 10; // 🟢 Cambiado temporalmente de 900 a 10
    _breakStartTime = DateTime.now();

    // Programamos la alarma nativa para dentro de 10 segundos
    NotificationService.scheduleNotification(
      id: 999,
      title: "⏰ ¡Fin de tu Break de 15 min!",
      body: "Debes reanudar tu turno o terminar el turno de inmediato.",
      delay: const Duration(seconds: 10), // 🟢 10 segundos
    );

    _breakTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_breakStartTime != null) {
        final elapsed = DateTime.now().difference(_breakStartTime!).inSeconds;

        // 🟢 Cambiado temporalmente de 900 a 10 para que la pantalla llegue a cero en 10 segundos
        _breakSecondsRemaining = 10 - elapsed;

        if (_breakSecondsRemaining <= 0) {
          _breakSecondsRemaining = 0;
          _stopBreakTimer();

          // Alarma de respaldo por si el conductor tiene la app abierta en primer plano
          NotificationService.showNotification(
            id: 999,
            title: "⏰ ¡Fin de tu Break de 15 min!",
            body: "Debes reanudar tu turno o terminar el turno de inmediato.",
          );
        }
        notifyListeners();
      }
    });
  }

  /// Cancela el temporizador de la pausa
  void _stopBreakTimer() {
    _breakTimer?.cancel();
    _breakTimer = null;
    _breakStartTime = null;

    // 🟢 NUEVO: Si el conductor reanuda o termina el turno antes de los 15 minutos,
    // cancelamos la alarma programada para que no suene de manera molesta después.
    NotificationService.cancelNotification(999);
    notifyListeners();
  }

  /// A. INICIAR TURNO (Kilometraje + Foto inicial del tablero)
  Future<String?> iniciarTurnoCompleto({
    required int kilometraje,
    required File foto,
  }) async {
    if (_isLoading) return null;
    if (_selectedVehicle == null) {
      return "⚠️ Debes seleccionar un vehículo para iniciar el turno.";
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Validar documentos locales antes de conectar
      await _checkDocumentsValidity();

      // Obtener ubicación GPS actual
      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        _currentPosition = LatLng(position.latitude, position.longitude);
      }

      // Llamar al endpoint del backend
      final res = await _driverRepository.iniciarTurno(
        idVehiculo: _selectedVehicle!.id,
        kilometraje: kilometraje,
        foto: foto,
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );

      if (res['status'] == 'success') {
        _turnoEstado = 'ACTIVO';
        _isOnline = true; // El conductor está en línea listo para viajes
        _alreadyHadLunch = false; // 🟢 RESET PARA NUEVA JORNADA

        // Encender rastreo en tiempo real
        _startListeningTrips();
        _startTracking();
        _startRouteRecalculationTimer();

        _isLoading = false;
        notifyListeners();
        return null; // Éxito
      }
      return "No se pudo iniciar el turno en el servidor.";
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return e.toString().replaceAll("Exception: ", "");
    }
  }

  /// B. PAUSAR TURNO / INICIAR BREAK (Desconexión de 15 minutos)
  Future<String?> iniciarBreak() async {
    if (_isLoading) return null;
    _isLoading = true;
    notifyListeners();

    try {
      final position = await _locationService.getCurrentLocation();
      final res = await _driverRepository.pausarTurno(
        lat: position?.latitude ?? _currentPosition?.latitude,
        lng: position?.longitude ?? _currentPosition?.longitude,
      );

      if (res['status'] == 'success') {
        _turnoEstado = 'BREAK';
        _isOnline = false; // Desconectado temporalmente

        // Detener rastreo temporalmente durante la pausa
        _stopTracking();
        _stopListeningTrips();

        // Lanzar el temporizador de 15 minutos
        _startBreakTimer();

        _isLoading = false;
        notifyListeners();
        return null;
      }
      return "No se pudo registrar la pausa.";
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return e.toString().replaceAll("Exception: ", "");
    }
  }

  /// C. REANUDAR TURNO (Fin de pausa, volver a estar activo para viajes)

  /// D. TERMINAR TURNO (Kilometraje final + Foto final del tablero)
  /// D. TERMINAR TURNO (Kilometraje final + Foto final del tablero + Comprobantes opcionales)
  Future<String?> terminarTurnoCompleto({
    required int kilometraje,
    required File foto,
    List<File>? comprobantesFotos, // 🟢 NUEVO: Parámetro opcional
    List<double>? comprobantesValores, // 🟢 NUEVO: Parámetro opcional
  }) async {
    if (_isLoading) return null;
    _isLoading = true;
    notifyListeners();

    try {
      final position = await _locationService.getCurrentLocation();
      final res = await _driverRepository.terminarTurno(
        kilometraje: kilometraje,
        foto: foto,
        lat: position?.latitude ?? _currentPosition?.latitude,
        lng: position?.longitude ?? _currentPosition?.longitude,
        comprobantesFotos:
            comprobantesFotos, // 🟢 Enviar fotos de peajes/gasolina
        comprobantesValores: comprobantesValores, // 🟢 Enviar valores digitados
      );

      if (res['status'] == 'success') {
        _turnoEstado = 'OFFLINE';
        _isOnline = false;

        // Detener de forma definitiva todas las conexiones y rastreos de la jornada
        _stopBreakTimer();
        _stopLunchTimer();
        _stopListeningTrips();
        _stopTracking();
        _activeTrip = null;
        _routePoints = [];
        await _storageService.clearCurrentTrip();

        _isLoading = false;
        notifyListeners();
        return null;
      }
      return "No se pudo finalizar el turno.";
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return e.toString().replaceAll("Exception: ", "");
    }
  }

  void _startRouteRecalculationTimer() {
    _routeRecalculateTimer?.cancel();
    _routeRecalculateTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) {
      if (_activeTrip != null) {
        _calculateRouteForCurrentStatus();
      } else {
        _stopRouteRecalculationTimer(); // 🟢 Corrección aquí (añadir "ion")
      }
    });
  }

  void _stopRouteRecalculationTimer() {
    _routeRecalculateTimer?.cancel();
    _routeRecalculateTimer = null;
  }

  void _startWaitTimer(Trip trip) {
    _waitTimer?.cancel();
    _waitSeconds = 300; // Iniciamos con el límite de 5 minutos

    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_waitSeconds > 0) {
        _waitSeconds--;
        notifyListeners();
      } else {
        _stopWaitTimer();
      }
    });
  }

  void _stopWaitTimer() {
    _waitTimer?.cancel();
    _waitTimer = null;
    _waitSeconds = 300;
    notifyListeners();
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
    final trip = activeTrip;
    if (trip == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final dio = ApiClient().dio;

      final response = await dio.post(
        '/viajes/${trip.id}/adicionar-tiempo',
        data: {'minutos': minutes},
      );

      if (response.statusCode == 200) {
        debugPrint("🟢 Tiempo extra registrado con éxito en el backend.");
        _extraWaitingTimeAdded = true;
        _waitSeconds +=
            (minutes *
            60); // 🟢 Se suman los minutos de espera extra al contador activo
        notifyListeners();
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
  // 🟢 BLINDAJE EXTREMO: Evita que datos parciales de WebSockets corrompan los datos completos en memoria
  void _updateActiveTripWithPreservation(Trip? newTrip) {
    if (newTrip == null) {
      _activeTrip = null;
      _extraWaitingTimeAdded = false;
      _stopWaitTimer(); // <-- Detener timer al limpiar
      return;
    }

    if (_activeTrip != null && _activeTrip!.id != newTrip.id) {
      _extraWaitingTimeAdded = false;
      _stopWaitTimer(); // <-- Detener para nuevo viaje
    }

    if (_activeTrip != null && _activeTrip!.id == newTrip.id) {
      final oldTrip = _activeTrip!;
      final bool statusChanged = oldTrip.status != newTrip.status;

      final bool isNewTripPartial =
          newTrip.originAddress == 'Origen...' || newTrip.passengers.isEmpty;

      _activeTrip = newTrip.copyWith(
        originAddress: isNewTripPartial
            ? oldTrip.originAddress
            : newTrip.originAddress,
        destinationAddress: isNewTripPartial
            ? oldTrip.destinationAddress
            : newTrip.destinationAddress,
        originLocation: isNewTripPartial
            ? oldTrip.originLocation
            : newTrip.originLocation,
        destinationLocation: isNewTripPartial
            ? oldTrip.destinationLocation
            : newTrip.destinationLocation,
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

    // 🟢 CONTROL DE INICIO DEL TIMER DE ESPERA
    if (_activeTrip != null &&
        _activeTrip!.status == TripStatus.ARRIVED &&
        _waitTimer == null) {
      _startWaitTimer(_activeTrip!);
    } else if (_activeTrip != null &&
        _activeTrip!.status != TripStatus.ARRIVED) {
      _stopWaitTimer();
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

  // En HomeProvider.dart:

  Future<void> initLocation() async {
    _isLoading = true;
    notifyListeners();
    await loadVehicles();

    final authProvider = sl<AuthProvider>();
    final wallet = sl<WalletProvider>();

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

      // 🟢 NUEVO BLINDAJE DE SEGURIDAD: RESTAURAR EL ESTADO DEL TURNO DESDE EL SERVIDOR
      try {
        final turnoData = await _driverRepository.obtenerTurnoActivo();
        if (turnoData['status'] == 'success' &&
            turnoData['tiene_turno_activo'] == true) {
          _turnoEstado = turnoData['estado'];
          _alreadyHadLunch = turnoData['ya_almorzo'] ?? false;

          if (_turnoEstado == 'ACTIVO') {
            _isOnline = true;
            _startListeningTrips();
            _startTracking();
            _startRouteRecalculationTimer();
          } else if (_turnoEstado == 'BREAK') {
            _isOnline = false;
            _breakSecondsRemaining =
                turnoData['segundos_restantes'] ??
                10; // O 900 según tus pruebas

            if (_breakSecondsRemaining > 0) {
              // Reconstruimos la hora de inicio simulada para mantener sincronizado el reloj
              _breakStartTime = DateTime.now().subtract(
                Duration(seconds: 10 - _breakSecondsRemaining),
              );

              _breakTimer?.cancel();
              _breakTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                if (_breakStartTime != null) {
                  final elapsed = DateTime.now()
                      .difference(_breakStartTime!)
                      .inSeconds;
                  _breakSecondsRemaining =
                      10 -
                      elapsed; // Usar 900 si restauras a modo de producción
                  if (_breakSecondsRemaining <= 0) {
                    _breakSecondsRemaining = 0;
                    _stopBreakTimer();
                    NotificationService.showNotification(
                      id: 999,
                      title: "⏰ ¡Fin de tu Break de 15 min!",
                      body:
                          "Debes reanudar tu turno o terminar el turno de inmediato.",
                    );
                  }
                  notifyListeners();
                }
              });
            }
          } else if (_turnoEstado == 'ALMUERZO') {
            _isOnline = false;
            _lunchSecondsRemaining = turnoData['segundos_restantes'] ?? 3600;

            if (_lunchSecondsRemaining > 0) {
              _lunchStartTime = DateTime.now().subtract(
                Duration(seconds: 3600 - _lunchSecondsRemaining),
              );

              _lunchTimer?.cancel();
              _lunchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                if (_lunchStartTime != null) {
                  final elapsed = DateTime.now()
                      .difference(_lunchStartTime!)
                      .inSeconds;
                  _lunchSecondsRemaining = 3600 - elapsed;
                  if (_lunchSecondsRemaining <= 0) {
                    _lunchSecondsRemaining = 0;
                    _stopLunchTimer();
                    NotificationService.showNotification(
                      id: 888,
                      title: "🍔 ¡Fin de tu hora de Almuerzo!",
                      body:
                          "Reanuda tu turno para continuar prestando servicios.",
                    );
                  }
                  notifyListeners();
                }
              });
            }
          }
        } else {
          _turnoEstado = 'OFFLINE';
          _isOnline = false;
        }
      } catch (e) {
        debugPrint("Error restaurando estado del turno: $e");
        _turnoEstado = 'OFFLINE';
        _isOnline = false;
      }
    }

    final savedTrip = await _storageService.getCurrentTrip();
    if (savedTrip != null) {
      final tripReal = await _tripRepository.getActiveTrip();

      if (tripReal != null && tripReal.id == savedTrip.id) {
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
        _passengerLocation = tripReal.originLocation;
        _startPassengerGpsListener(_activeTrip!.id);
        _startRouteRecalculationTimer();
        await _calculateRouteForCurrentStatus();
      } else {
        await _storageService.clearCurrentTrip();
        _activeTrip = null;
      }
    } else {
      try {
        final tripReal = await _tripRepository.getActiveTrip();
        if (tripReal != null) {
          // 🚨 FILTRO: Si el viaje tiene estado SCHEDULED_ASSIGNED, lo ignoramos para que no tome el mapa al iniciar
          if (tripReal.status.toString().contains('SCHEDULED_ASSIGNED')) {
            _activeTrip = null;
          } else {
            _activeTrip = tripReal;
            _isOnline = true;
            await _storageService.saveCurrentTrip(_activeTrip!);
            _startListeningTrips();
            _passengerLocation = tripReal.originLocation;
            _startPassengerGpsListener(_activeTrip!.id);
            _startRouteRecalculationTimer();
            await _calculateRouteForCurrentStatus();
          }
        }
      } catch (e) {
        debugPrint("Error buscando viaje activo de respaldo en inicio: $e");
      }
    }

    final hasPermission = await _locationService.checkPermissions();
    if (hasPermission) {
      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _currentHeading = position.heading;
      }
      if (_isOnline) {
        _startTracking();
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  // 🟢 ACTUALIZADO: Ignora SCHEDULED_ASSIGNED al encender el turno
  Future<String?> toggleOnlineStatus() async {
    if (_isLoading) return null;

    if (!_isOnline && _selectedVehicle == null) {
      return "⚠️ Debes seleccionar un vehículo para conectarte.";
    }

    if (!_isOnline && _currentPosition == null) {
      _isLoading = true;
      notifyListeners();

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
      if (!_isOnline) {
        await _checkDocumentsValidity();
      }

      final String userId = sl<AuthProvider>().user?.id ?? "0";

      final bool success = await _driverRepository.toggleStatus(
        isOnline: !_isOnline,
        driverId: userId,
        vehicleId: _selectedVehicle?.id,
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );

      if (success) {
        _isOnline = !_isOnline;

        if (_isOnline) {
          _startListeningTrips();
          _startTracking();

          try {
            final tripReal = await _tripRepository.getActiveTrip();
            if (tripReal != null) {
              // 🚨 FILTRO: Ignoramos el programado para no tomar la pantalla al conectarse
              if (tripReal.status.toString().contains('SCHEDULED_ASSIGNED')) {
                _activeTrip = null;
              } else {
                _activeTrip = tripReal;
                await _storageService.saveCurrentTrip(_activeTrip!);
                _passengerLocation = tripReal.originLocation;
                _startPassengerGpsListener(_activeTrip!.id);
                _startRouteRecalculationTimer();
                await _calculateRouteForCurrentStatus();
              }
            }
          } catch (e) {
            debugPrint("Error buscando viaje activo al conectarse: $e");
          }
        } else {
          _stopListeningTrips();
          _stopTracking();
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

  // 🟢 NUEVO: Inicia la ruta hacia el origen desde la lista manual de viajes programados
  // 🟢 ACTUALIZADO Y BLINDADO: Inicia la ruta preservando toda la información detallada del viaje programado
  Future<bool> iniciarRutaAlOrigenConViaje(Trip trip) async {
    _isLoading = true;
    _activeTrip =
        trip; // 1. Cargamos de forma segura el viaje detallado en memoria
    notifyListeners();

    try {
      final updatedTrip = await _tripRepository.updateTripStatus(
        trip.id,
        'ACCEPTED',
      );

      // 2. 🟢 SOLUCIÓN: En lugar de sobreescribir directo, usamos preservación blindada
      // Esto filtra la respuesta parcial de la API y mantiene las direcciones y coordenadas reales intactas.
      _updateActiveTripWithPreservation(updatedTrip);

      await _storageService.saveCurrentTrip(_activeTrip!);

      _passengerLocation = _activeTrip!.originLocation;
      _startPassengerGpsListener(_activeTrip!.id);
      _startRouteRecalculationTimer();
      await _calculateRouteForCurrentStatus();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _activeTrip = null;
      _isLoading = false;
      notifyListeners();
      debugPrint("🚨 Error al iniciar ruta desde lista: $e");
      return false;
    }
  }

  void _startTracking() {
    _positionSubscription?.cancel().catchError((error) {
      debugPrint("ℹ️ Silenciando reinicio de canal de GPS: $error");
    });
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
    _startNetworkMonitor();
  }

  void _updatePosition(Position pos) async {
    final newLocation = LatLng(pos.latitude, pos.longitude);

    // Si la precisión del GPS es muy baja (mayor a 80 metros), alertar pérdida de señal GPS
    if (pos.accuracy > 80.0) {
      if (!_isGpsSignalLost) {
        _isGpsSignalLost = true;
        notifyListeners();
      }
      return; // No procesamos coordenadas inexactas para no distorsionar el mapa del pasajero
    } else {
      if (_isGpsSignalLost) {
        _isGpsSignalLost = false;
        notifyListeners();
      }
    }

    if (_currentPosition != null) {
      final Distance distance = const Distance();
      final double dist = distance.as(
        LengthUnit.Meter,
        _currentPosition!,
        newLocation,
      );

      // 1. Si está ONLINE pero NO está en un servicio activo
      if (_isOnline && _activeTrip == null && dist > 10.0) {
        _sendPositionToBackend(pos.latitude, pos.longitude);
      }

      // 2. Si está en un viaje activo, transmitir de manera resiliente
      if (_activeTrip != null) {
        final bool enServicioActivo =
            _activeTrip!.status == TripStatus.ACCEPTED ||
            _activeTrip!.status == TripStatus.ARRIVED ||
            _activeTrip!.status == TripStatus.STARTED;

        if (enServicioActivo && dist > 5.0) {
          _sendTripLocationToBackend(
            _activeTrip!.id,
            pos.latitude,
            pos.longitude,
            pos.speed,
          );
          _calculateRouteForCurrentStatus();
        }
      }

      // Estabilización del rumbo
      if (dist > 1.5) {
        _currentHeading = _calculateBearing(_currentPosition!, newLocation);
      } else if (pos.heading > 0) {
        _currentHeading = pos.heading;
      }
    }

    _currentPosition = newLocation;
    notifyListeners();
  }

  // --- MÉTODOS DE ENVÍO CON TOLERANCIA A ERRORES ---

  Future<void> _sendPositionToBackend(double lat, double lng) async {
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      _setNetworkDisconnected(true);
      return;
    }

    try {
      await _driverRepository.updatePosition(lat, lng);
      _setNetworkDisconnected(false);
    } catch (e) {
      // El envío falló por timeout o error de red transitorio
      _setNetworkDisconnected(true);
    }
  }

  Future<void> _sendTripLocationToBackend(
    String tripId,
    double lat,
    double lng,
    double speed,
  ) async {
    final hasInternet = await _hasInternetConnection();
    if (!hasInternet) {
      _setNetworkDisconnected(true);
      return;
    }

    try {
      await _tripRepository.updateLocation(
        tripId,
        lat,
        lng,
        speed: speed,
        bearing: _currentHeading,
      );
      _setNetworkDisconnected(false);
    } catch (e) {
      _setNetworkDisconnected(true);
    }
  }

  void _stopTracking() {
    _positionSubscription?.cancel().catchError((error) {
      debugPrint("ℹ️ Silenciando canal de GPS ya inactivo: $error");
    });
    _positionSubscription = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _stopNetworkMonitor();
    _setNetworkDisconnected(false);
    _isGpsSignalLost = false;
    notifyListeners();
  }

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
  // 🟢 BLINDAJE EXTREMO: Si el Socket envía una señal parcial, consulta de inmediato a la API de respaldo
  // 🟢 COMPLETAMENTE BLINDADO: Si el Socket envía datos parciales, hidrata de inmediato consultando a la API
  void _startListeningTrips() {
    _tripSubscription?.cancel();

    _tripSubscription = _tripRepository.listenForTrips().listen((trip) async {
      try {
        debugPrint("📡 [SOCKET] Evento: ${trip.status} para viaje ${trip.id}");

        if (trip.status.name == 'NO_DISPONIBLE' &&
            _incomingTrip?.id == trip.id) {
          debugPrint("🧹 [SOCKET] Limpiando alerta: viaje tomado por otro.");
          _incomingTrip = null;
          notifyListeners();
          return;
        }

        if (trip.status == TripStatus.CANCELLED ||
            trip.status == TripStatus.COMPLETED) {
          debugPrint("🛑 [SOCKET] Limpieza controlada.");
          _finishTrip();
          return;
        }

        if (trip.status == TripStatus.ACCEPTED) {
          // 🟢 BLINDAJE: Si el viaje que llega por Socket es parcial (dirección o pasajeros vacíos)
          // consultamos inmediatamente al servidor para obtener el objeto completo y detallado.
          if (trip.originAddress == 'Origen...' || trip.passengers.isEmpty) {
            final fullTrip = await _tripRepository.getActiveTrip();
            if (fullTrip != null) {
              _updateActiveTripWithPreservation(fullTrip);
            }
          } else {
            _updateActiveTripWithPreservation(trip);
          }
          _incomingTrip = null;
          notifyListeners();
        } else if (trip.status == TripStatus.PENDING) {
          if (_lastRejectedTripId == trip.id) {
            debugPrint(
              "⚠️ [SOCKET] Ignorando evento PENDING de viaje recientemente rechazado.",
            );
            return;
          }

          debugPrint("ℹ️ [SOCKET] Nueva oferta PENDING detectada: ${trip.id}");
          _incomingTrip = trip;
          calculateIncomingTripRoute();

          if (_incomingTrip != null) {
            _startValidationTimer(
              _incomingTrip!.assignmentId ?? _incomingTrip!.id,
            );
            notifyListeners();
          }
        }
      } catch (e, stackTrace) {
        debugPrint("🚨 [CRITICO] Error procesando evento de socket: $e");
        debugPrint(stackTrace.toString());
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
      _startRouteRecalculationTimer();

      notifyListeners();

      await _storageService.saveCurrentTrip(_activeTrip!);
      await _calculateRouteForCurrentStatus();
    } catch (e) {
      debugPrint("Error al aceptar viaje: $e");
      _isLoading = false;

      // --- SOLUCIÓN: EXTRAER Y MOSTRAR EL ERROR REAL DEL SERVIDOR ---
      String mensajeAMostrar = "No se pudo aceptar el viaje. Intenta de nuevo.";

      // Si tu repositorio usa Dio, puedes extraer el mensaje JSON del backend así:
      // (Ajusta esto según la librería HTTP que uses, por ejemplo, e.response?.data['message'])
      final errorString = e.toString();
      if (errorString.contains("saldo") ||
          errorString.contains("bajo") ||
          errorString.contains("Recarga")) {
        mensajeAMostrar = "Tu saldo es muy bajo. Recarga para continuar.";
      } else {
        // Limpiamos prefijos comunes si es una excepción personalizada
        mensajeAMostrar = errorString.replaceAll("Exception:", "").trim();
      }

      // Disparar la alerta visual en el front
      _showError(mensajeAMostrar);

      notifyListeners();
    }
  }

  /// Retorna si el viaje activo actual en el conductor es programado.
  bool get isActiveTripScheduled {
    if (_activeTrip == null) return false;
    // Un viaje es programado si tiene fecha asignada en 'scheduledAt'
    return _activeTrip!.scheduledAt != null;
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

  /// 🟢 NUEVO: Inicia la ruta hacia el origen del pasajero (Cambia de SCHEDULED_ASSIGNED a ACCEPTED)
  Future<void> iniciarRutaAlOrigen() async {
    if (_activeTrip == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      // Cambiamos el estado a ACCEPTED (Esto avisa al pasajero en tiempo real que vamos en camino)
      await _updateTripStatus('ACCEPTED');
    } catch (e) {
      debugPrint("🚨 Error al iniciar ruta al origen: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 🟢 ACTUALIZADO: Intenta activar el viaje programado ingresando el PIN (Pasa de ARRIVED a STARTED)
  Future<bool> activarViajeProgramado(String pin) async {
    if (_activeTrip == null || _currentPosition == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      final dio = ApiClient().dio;

      final response = await dio.post(
        '/conductor/viajes/activar-programado',
        data: {
          'codigo_activacion': pin,
          'lat': _currentPosition!.latitude,
          'lng': _currentPosition!.longitude,
        },
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        // Obtenemos el viaje actualizado desde el servidor (ahora en estado STARTED)
        final tripReal = await _tripRepository.getActiveTrip();

        if (tripReal != null) {
          _activeTrip = tripReal;

          // Guardamos en memoria local
          await _storageService.saveCurrentTrip(_activeTrip!);

          // 🟢 LIMPIEZA: Como el pasajero ya abordó, detenemos el rastreo de su celular en tiempo real
          _passengerLocation = null;
          _stopPassengerGpsListener();

          _startRouteRecalculationTimer();
          await _calculateRouteForCurrentStatus();

          _isLoading = false;
          notifyListeners();
          return true;
        }
      }

      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint("🚨 Error activando viaje programado: $e");
      rethrow;
    }
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
  /// Cierre definitivo tras confirmación de pago
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
    _stopRouteRecalculationTimer(); // 🟢 Corrección aquí (añadir "ion")

    _activeTrip = null;
    _routePoints = [];
    _extraWaitingTimeAdded = false; // Reset al finalizar

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
    _positionSubscription?.cancel().catchError((e) => null);
    _tripSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _stopPassengerGpsListener();
    _stopRouteRecalculationTimer();
    _waitTimer?.cancel(); // 🟢 Cancelar timer al destruir el provider
    _breakTimer?.cancel(); // <--- AGREGAR ESTA LÍNEA AQUÍ
    _stopNetworkMonitor();
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
