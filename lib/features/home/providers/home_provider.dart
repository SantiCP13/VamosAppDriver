import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
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
import 'dart:io';
import '../../../core/services/notification_service.dart';
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
import '../widgets/payment_waiting_sheet.dart';
import '../../auth/providers/auth_provider.dart';
import '../../maps/services/route_service.dart';

class HomeProvider extends ChangeNotifier {
  // 1. INYECCIÓN DE DEPENDENCIAS
  final LocationService _locationService = sl<LocationService>();
  final StorageService _storageService = sl<StorageService>();
  final DriverRepository _driverRepository = sl<DriverRepository>();
  final TripRepository _tripRepository = sl<TripRepository>();
  final RouteService _routeService = RouteService();

  HomeProvider();

  // 2. ESTADO
  bool _isOnline = false;
  bool _isLoading = false;
  String? _lastRejectedTripId;

  double get activeTripDistance => _activeTrip?.distanceKm ?? 0.0;

  bool _extraWaitingTimeAdded = false;
  bool get extraWaitingTimeAdded => _extraWaitingTimeAdded;

  LatLng? _currentPosition;
  double _currentHeading = 0.0;

  double get incomingDistance => _incomingDistance;

  String _incomingTripEta = "--";

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

  // NUEVO: Almacenamiento temporal de puntos GPS en zonas sin cobertura
  final List<Map<String, dynamic>> _offlineTrackingBuffer = [];
  bool _isSyncingBuffer = false;

  // --- NUEVAS VARIABLES PARA EL CONTROL DE TURNOS (3 ESTADOS) ---
  String _turnoEstado = 'OFFLINE';
  int _breakSecondsRemaining = 900;
  Timer? _breakTimer;
  DateTime? _breakStartTime;

  bool _alreadyHadLunch = false;
  bool get alreadyHadLunch => _alreadyHadLunch;
  String get turnoEstado => _turnoEstado;
  int get breakSecondsRemaining => _breakSecondsRemaining;

  String get breakTimerFormated {
    final minutes = (_breakSecondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_breakSecondsRemaining % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  int _waitSeconds = 300;
  int get waitSeconds => _waitSeconds;
  Timer? _waitTimer;

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

  Trip? get activeTrip => _activeTrip;
  List<LatLng> _routePoints = [];
  set routePoints(List<LatLng> value) {
    _routePoints = value;
    notifyListeners();
  }

  double _totalRouteDistanceMeters = 0.0;
  double _totalRouteDurationSeconds = 0.0;

  List<Vehicle> _myVehicles = [];
  Vehicle? _selectedVehicle;
  List<DriverDocument> _documents = [];

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription? _tripSubscription;

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

  int _lunchSecondsRemaining = 3600;
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

  /// Retorna si existen coordenadas pendientes de sincronización en la cola local
  bool get hasPendingOfflineCoordinates => _offlineTrackingBuffer.isNotEmpty;

  /// Cambia el estado de red de forma segura y notifica al UI
  void _setNetworkDisconnected(bool value) {
    if (_isNetworkDisconnected != value) {
      _isNetworkDisconnected = value;
      notifyListeners();
    }
  }

  void _startLunchTimer() {
    _lunchTimer?.cancel();
    _lunchSecondsRemaining = 3600;
    _lunchStartTime = DateTime.now();

    NotificationService.scheduleNotification(
      id: 888,
      title: "🍔 ¡Fin de tu hora de Almuerzo!",
      body: "Tu descanso de almuerzo ha finalizado. Debes reanudar tu turno.",
      delay: const Duration(hours: 1),
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

  Future<String?> iniciarAlmuerzo() async {
    if (_isLoading) return null;
    _isLoading = true;
    notifyListeners();

    try {
      final position = await _locationService.getCurrentLocation();
      final res = await _driverRepository.iniciarAlmuerzo(
        lat: position?.latitude ?? _currentPosition?.latitude,
        lng: position?.longitude ?? _currentPosition?.longitude,
      );

      if (res['status'] == 'success') {
        _turnoEstado = 'ALMUERZO';
        _isOnline = false;
        _alreadyHadLunch = true;

        _stopHeartbeat();
        _stopListeningTrips();

        _startLunchTimer();

        _isLoading = false;
        notifyListeners();
        return null;
      }

      if (res.containsKey('message')) {
        return res['message'].toString();
      }

      return "No se pudo registrar tu almuerzo.";
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return _extractExceptionMessage(e);
    }
  }

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
        _alreadyHadLunch = false;

        _startListeningTrips();
        _startTracking();
        _startRouteRecalculationTimer();

        _isLoading = false;
        notifyListeners();
        return null;
      }

      if (res.containsKey('message')) {
        return res['message'].toString();
      }

      return "No se pudo iniciar el turno en el servidor.";
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return _extractExceptionMessage(e);
    }
  }

  void _startBreakTimer() {
    _breakTimer?.cancel();
    _breakSecondsRemaining = 900;
    _breakStartTime = DateTime.now();

    NotificationService.scheduleNotification(
      id: 999,
      title: "¡Fin de tu Break de 15 min!",
      body: "Debes reanudar tu turno o terminar el turno de inmediato.",
      delay: const Duration(minutes: 15),
    );

    _breakTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_breakStartTime != null) {
        final elapsed = DateTime.now().difference(_breakStartTime!).inSeconds;
        _breakSecondsRemaining = 900 - elapsed;

        if (_breakSecondsRemaining <= 0) {
          _breakSecondsRemaining = 0;
          _stopBreakTimer();

          NotificationService.showNotification(
            id: 999,
            title: "¡Fin de tu Break de 15 min!",
            body: "Debes reanudar tu turno o terminar el turno de inmediato.",
          );
        }
        notifyListeners();
      }
    });
  }

  void _stopBreakTimer() {
    _breakTimer?.cancel();
    _breakTimer = null;
    _breakStartTime = null;
    NotificationService.cancelNotification(999);
    notifyListeners();
  }

  Future<String?> iniciarTurnoCompleto({
    required int kilometraje,
    required File foto,
  }) async {
    if (_isLoading) {
      debugPrint(
        "API_DEBUG_PROVIDER: Retornando temprano porque _isLoading ya es true.",
      );
      return null;
    }
    if (_selectedVehicle == null) {
      return "⚠️ Debes seleccionar un vehículo para iniciar el turno.";
    }

    _isLoading = true;
    notifyListeners();

    try {
      await _checkDocumentsValidity();

      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        _currentPosition = LatLng(position.latitude, position.longitude);
      }

      debugPrint(
        "API_DEBUG_PROVIDER: Enviando petición HTTP a iniciarTurno...",
      );
      final res = await _driverRepository.iniciarTurno(
        idVehiculo: _selectedVehicle!.id,
        kilometraje: kilometraje,
        foto: foto,
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );
      debugPrint(
        "API_DEBUG_PROVIDER: Respuesta recibida del repositorio -> $res",
      );

      if (res['status'] == 'success') {
        _turnoEstado = 'ACTIVO';
        _isOnline = true;
        _alreadyHadLunch = false;

        _startListeningTrips();
        _startTracking();
        _startRouteRecalculationTimer();

        _isLoading = false;
        notifyListeners();
        return null;
      }

      if (res.containsKey('message')) {
        final backendMessage = res['message'].toString();
        debugPrint(
          "API_DEBUG_PROVIDER: El backend retornó un estado fallido controlado con mensaje: $backendMessage",
        );
        return backendMessage;
      }

      return "No se pudo iniciar el turno en el servidor.";
    } catch (e, stackTrace) {
      debugPrint(
        "API_DEBUG_PROVIDER: Se capturó una excepción en el catch -> $e",
      );
      debugPrint("API_DEBUG_PROVIDER: StackTrace -> $stackTrace");
      _isLoading = false;
      notifyListeners();

      final extractedMsg = _extractExceptionMessage(e);
      debugPrint("API_DEBUG_PROVIDER: Mensaje extraído final -> $extractedMsg");
      return extractedMsg;
    }
  }

  void forzarEstadoOffline() {
    _turnoEstado = 'OFFLINE';
    notifyListeners();
  }

  Future<void> verificarTurnoActivoConServidor() async {
    try {
      final turnoData = await _driverRepository.obtenerTurnoActivo();

      if (turnoData['status'] == 'success' &&
          turnoData['tiene_turno_activo'] == true) {
        _turnoEstado = turnoData['estado'];
      } else {
        _turnoEstado = 'OFFLINE';
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error verificando turno activo con servidor: $e");
    }
  }

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
        _isOnline = false;

        _stopHeartbeat();
        _stopListeningTrips();

        _startBreakTimer();

        _isLoading = false;
        notifyListeners();
        return null;
      }
      return "No se pudo registrar la pausa.";
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return _extractExceptionMessage(e);
    }
  }

  Future<String?> terminarTurnoCompleto({
    required int kilometraje,
    required File foto,
    List<File>? comprobantesFotos,
    List<double>? comprobantesValores,
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
        comprobantesFotos: comprobantesFotos,
        comprobantesValores: comprobantesValores,
      );

      if (res['status'] == 'success') {
        _turnoEstado = 'OFFLINE';
        _isOnline = false;

        _stopBreakTimer();
        _stopLunchTimer();
        _stopListeningTrips();
        _stopHeartbeat();
        _activeTrip = null;
        _routePoints = [];
        await _storageService.clearCurrentTrip();

        _isLoading = false;
        notifyListeners();
        return null;
      }

      if (res.containsKey('message')) {
        return res['message'].toString();
      }

      return "No se pudo finalizar el turno.";
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return _extractExceptionMessage(e);
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
        _stopRouteRecalculationTimer();
      }
    });
  }

  void _stopRouteRecalculationTimer() {
    _routeRecalculateTimer?.cancel();
    _routeRecalculateTimer = null;
  }

  void _startWaitTimer(Trip trip) {
    _waitTimer?.cancel();
    _waitSeconds = 300;

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
  }

  double get balance => _balance;
  void updateBalance(double newBalance) {
    _balance = newBalance;
    notifyListeners();
  }

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
        _waitSeconds += (minutes * 60);
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

  LatLng? _passengerLocation;
  bool _hasReceivedPassengerGps = false;

  LatLng? get passengerLocation {
    if (_passengerLocation == null) return null;

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

  set passengerLocation(LatLng? value) {
    _passengerLocation = value;
    notifyListeners();
  }

  void _stopValidationTimer() {
    _validationTimer?.cancel();
    _validationTimer = null;
  }

  void _updateActiveTripWithPreservation(Trip? newTrip) {
    if (newTrip == null) {
      _activeTrip = null;
      _extraWaitingTimeAdded = false;
      _stopWaitTimer();
      return;
    }

    if (_activeTrip != null && _activeTrip!.id != newTrip.id) {
      _extraWaitingTimeAdded = false;
      _stopWaitTimer();
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

    if (_activeTrip != null &&
        _activeTrip!.status == TripStatus.ARRIVED &&
        _waitTimer == null) {
      _startWaitTimer(_activeTrip!);
    } else if (_activeTrip != null &&
        _activeTrip!.status != TripStatus.ARRIVED) {
      _stopWaitTimer();
    }
  }

  void _startValidationTimer(String assignmentId) {
    _stopValidationTimer();

    _validationTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      if (_incomingTrip == null) {
        _stopValidationTimer();
        return;
      }

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
          notifyListeners();
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

      routePoints = [];

      int minutes = (routeResult.durationSeconds / 60).round();
      _incomingTripEta = minutes > 0 ? "$minutes min" : "Llegando";

      notifyListeners();
    } catch (e) {
      debugPrint("Error calculando ruta: $e");
    }
  }

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

  String get distanceToTarget {
    if (_currentPosition == null || _activeTrip == null) return "---";

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

    if (streetMeters <= 0) return "---";
    if (streetMeters < 1000) {
      return "${streetMeters.toStringAsFixed(0)} m";
    } else {
      return "${(streetMeters / 1000).toStringAsFixed(1)} km";
    }
  }

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
      calculatedMinutes = streetMeters / 225.0;
    }

    if (streetMeters < 30) {
      return 0.0;
    }

    int mins = calculatedMinutes.round();
    if (streetMeters > 0 && mins < 1) mins = 1;

    return mins.toDouble();
  }

  Future<void> initLocation() async {
    _isLoading = true;
    notifyListeners();

    try {
      debugPrint(
        "💾 [HomeProvider - INIT] Leyendo última posición del disco persistente...",
      );
      final cachedPos = await _storageService.getLastPosition();
      if (cachedPos != null) {
        _currentPosition = LatLng(cachedPos['lat']!, cachedPos['lng']!);
        _currentHeading = 0.0;
        debugPrint(
          "✅ [HomeProvider - INIT] Posición de respaldo cargada en la UI: $_currentPosition",
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint(
        "🚨 [HomeProvider - INIT] Error al leer caché local en el arranque: $e",
      );
    }

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
            _breakSecondsRemaining = turnoData['segundos_restantes'] ?? 900;

            if (_breakSecondsRemaining > 0) {
              _breakStartTime = DateTime.now().subtract(
                Duration(seconds: 900 - _breakSecondsRemaining),
              );

              _breakTimer?.cancel();
              _breakTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
                if (_breakStartTime != null) {
                  final elapsed = DateTime.now()
                      .difference(_breakStartTime!)
                      .inSeconds;
                  _breakSecondsRemaining = 900 - elapsed;
                  if (_breakSecondsRemaining <= 0) {
                    _breakSecondsRemaining = 0;
                    _stopBreakTimer();
                    NotificationService.showNotification(
                      id: 999,
                      title: "¡Fin de tu Break de 15 min!",
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
      try {
        final tripReal = await _tripRepository.getActiveTrip().timeout(
          const Duration(seconds: 4),
        );

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
        } else if (tripReal == null) {
          await _storageService.clearCurrentTrip();
          _activeTrip = null;
        }
      } catch (e) {
        debugPrint(
          "📡 [OFFLINE] Error de conexión con el servidor. Restaurando viaje de almacenamiento local: $e",
        );

        _activeTrip = savedTrip;
        _isOnline = true;
        _startListeningTrips();
        _passengerLocation = savedTrip.originLocation;
        _startRouteRecalculationTimer();
        await _calculateRouteForCurrentStatus();
      }
    } else {
      try {
        final tripReal = await _tripRepository.getActiveTrip().timeout(
          const Duration(seconds: 4),
        );

        if (tripReal != null) {
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
        debugPrint(
          "Error buscando viaje activo de respaldo offline en inicio: $e",
        );
      }
    }

    final hasPermission = await _locationService.checkPermissions();
    if (hasPermission) {
      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _currentHeading = position.heading;
      }
      // Arranca el rastreador de GPS local inmediatamente sin importar el estado
      _startTracking();
    }
    _isLoading = false;
    notifyListeners();
  }

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
          _startHeartbeat(); // 🟢 NUEVO: Encender envío de red

          try {
            final tripReal = await _tripRepository.getActiveTrip();
            if (tripReal != null) {
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
          _stopHeartbeat();
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

  Future<bool> iniciarRutaAlOrigenConViaje(Trip trip) async {
    if (_selectedVehicle == null) {
      _showError(
        "⚠️ Debes seleccionar o tener un vehículo activo para iniciar.",
      );
      return false;
    }

    if (trip.vehicleId != null &&
        _selectedVehicle!.id.toString() != trip.vehicleId.toString()) {
      _showError(
        "⚠️ No puedes iniciar este viaje. El vehículo que tienes activo actualmente (${_selectedVehicle!.plate}) no coincide con el vehículo asignado legalmente para este servicio.",
      );
      return false;
    }

    _isLoading = true;
    _activeTrip = trip;
    notifyListeners();

    try {
      final updatedTrip = await _tripRepository.updateTripStatus(
        trip.id,
        'ACCEPTED',
      );

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

  /// Inicia el reporte constante de presencia hacia el servidor
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isOnline && _activeTrip == null && _currentPosition != null) {
        _driverRepository.updatePosition(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
        );
      }
    });
  }

  /// Apaga el reporte de presencia al servidor
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // 1. Añade esta propiedad en la sección de estado de HomeProvider
  TrackingProfile _currentProfile = TrackingProfile.offline;
  TrackingProfile get currentProfile => _currentProfile;

  // 2. Método auxiliar para evaluar cuál es el perfil que la aplicación exige en este instante
  TrackingProfile _determineRequiredProfile() {
    // Si hay un viaje activo en fase de transporte o recogida, se exige perfil de viaje
    if (_activeTrip != null) {
      final status = _activeTrip!.status;
      if (status == TripStatus.ACCEPTED ||
          status == TripStatus.ARRIVED ||
          status == TripStatus.STARTED) {
        return TrackingProfile.activeTrip;
      }
    }

    // Si el conductor tiene el turno activo y está conectado en línea
    if (_turnoEstado == 'ACTIVO' && _isOnline) {
      return TrackingProfile.onlineIdle;
    }

    // Por defecto (Offline, Break, Almuerzo)
    return TrackingProfile.offline;
  }

  // 3. Modifica _startTracking para que evalúe y reactive el stream dinámicamente
  void _startTracking() {
    final requiredProfile = _determineRequiredProfile();
    debugPrint("🔋 [GPS CONTROL] Solicitando perfil: ${requiredProfile.name}");

    // Si ya estamos transmitiendo bajo este perfil exacto, evitamos sobrecargar el hardware reiniciando el stream
    if (_positionSubscription != null && _currentProfile == requiredProfile) {
      return;
    }

    _currentProfile = requiredProfile;

    // Cancelamos la suscripción anterior de manera segura antes de levantar la nueva
    _positionSubscription?.cancel().catchError((error) {
      debugPrint("ℹ️ Silenciando reinicio de canal de GPS: $error");
    });

    _positionSubscription = _locationService
        .getPositionStream(profile: _currentProfile)
        .listen((pos) {
          _updatePosition(pos);
        });

    // Si está en línea, iniciamos también el reporte periódico de presencia para la administración
    if (_isOnline) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }
  }

  // 4. Reemplaza el método _updatePosition en tu HomeProvider por esta versión inteligente
  void _updatePosition(Position pos) async {
    final newLocation = LatLng(pos.latitude, pos.longitude);

    // A. Guardamos la última posición en disco local como respaldo inmediato de UI
    try {
      await _storageService.saveLastPosition(pos.latitude, pos.longitude);
    } catch (ex) {
      debugPrint("🚨 [GPS STORAGE] Fallo de persistencia rápida: $ex");
    }

    // B. CONTROL DE PRECISIÓN: Si la señal de GPS es sumamente débil (baja precisión espacial),
    // se reporta a la interfaz de usuario pero NO se envía al backend para evitar saltos locos en el mapa del cliente
    if (pos.accuracy > 45.0) {
      if (!_isGpsSignalLost) {
        _isGpsSignalLost = true;
        notifyListeners();
      }
      return; // Ignoramos la coordenada imprecisa para envíos de red
    } else {
      if (_isGpsSignalLost) {
        _isGpsSignalLost = false;
        notifyListeners();
      }
    }

    // C. CÁLCULO DE DESPLAZAMIENTO REAL
    if (_currentPosition != null) {
      const Distance distance = Distance();
      final double dist = distance.as(
        LengthUnit.Meter,
        _currentPosition!,
        newLocation,
      );

      // FILTRO PREMIUM DE MOVIMIENTO:
      // Si el conductor está detenido (velocidad casi nula o movimiento menor a 2 metros),
      // ignoramos el reporte hacia el servidor para conservar batería y paquete de datos.
      final bool estaInmovil = pos.speed < 0.25 && dist < 2.0;

      if (!estaInmovil) {
        // 1. Reporte en estado de espera (Online pero sin viaje)
        if (_isOnline && _activeTrip == null && dist > 12.0) {
          _sendPositionToBackend(pos.latitude, pos.longitude);
        }

        // 2. Reporte en viaje activo
        if (_activeTrip != null) {
          final bool enServicioActivo =
              _activeTrip!.status == TripStatus.ACCEPTED ||
              _activeTrip!.status == TripStatus.ARRIVED ||
              _activeTrip!.status == TripStatus.STARTED;

          if (enServicioActivo && dist > 3.0) {
            _sendTripLocationToBackend(
              _activeTrip!.id,
              pos.latitude,
              pos.longitude,
              pos.speed,
            );
            _calculateRouteForCurrentStatus();
          }
        }

        // Calculamos el rumbo (bearing) solo si el desplazamiento es físico y real
        if (dist > 1.8) {
          _currentHeading = _calculateBearing(_currentPosition!, newLocation);
        } else if (pos.heading > 0) {
          _currentHeading = pos.heading;
        }
      }
    }

    _currentPosition = newLocation;
    notifyListeners();
  }

  Future<void> _sendPositionToBackend(double lat, double lng) async {
    debugPrint(
      "📡 [RED SEND] En espera. Enviando posición al servidor: ($lat, $lng)",
    );

    try {
      await _driverRepository.updatePosition(lat, lng);
      _setNetworkDisconnected(false);
    } catch (e) {
      _setNetworkDisconnected(true);
    }
  }

  Future<void> _sendTripLocationToBackend(
    String tripId,
    double lat,
    double lng,
    double speed,
  ) async {
    debugPrint(
      "🏎️ [RED SEND] En viaje activo. Enviando tracking al servidor: ($lat, $lng) a $speed m/s",
    );

    final Map<String, dynamic> coordinatePayload = {
      'tripId': tripId,
      'lat': lat,
      'lng': lng,
      'speed': speed,
      'bearing': _currentHeading,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      await _tripRepository.updateLocation(
        tripId,
        lat,
        lng,
        speed: speed,
        bearing: _currentHeading,
      );

      _setNetworkDisconnected(false);

      if (_offlineTrackingBuffer.isNotEmpty) {
        _syncOfflineTrackingBuffer();
      }
    } catch (e) {
      _setNetworkDisconnected(true);

      if (_offlineTrackingBuffer.length < 500) {
        _offlineTrackingBuffer.add(coordinatePayload);
        debugPrint(
          "💾 [GPS OFFLINE] Coordenada guardada en búfer local. Total en cola: ${_offlineTrackingBuffer.length}",
        );
      }
    }
  }

  Future<void> _syncOfflineTrackingBuffer() async {
    if (_isSyncingBuffer || _offlineTrackingBuffer.isEmpty) return;
    _isSyncingBuffer = true;

    debugPrint(
      "🔄 [GPS OFFLINE] Iniciando sincronización de ${_offlineTrackingBuffer.length} puntos acumulados...",
    );

    try {
      while (_offlineTrackingBuffer.isNotEmpty) {
        final Map<String, dynamic> pendingPoint = _offlineTrackingBuffer.first;
        final String tripId = pendingPoint['tripId'].toString();

        await _tripRepository.updateLocation(
          tripId,
          pendingPoint['lat'],
          pendingPoint['lng'],
          speed: pendingPoint['speed'],
          bearing: pendingPoint['bearing'],
        );

        _offlineTrackingBuffer.removeAt(0);
      }
      _setNetworkDisconnected(false);
      debugPrint("✅ [GPS OFFLINE] Búfer offline sincronizado por completo.");
    } catch (e) {
      _setNetworkDisconnected(true);
      debugPrint(
        "🚨 [GPS OFFLINE] Sincronización interrumpida debido a inestabilidad de red.",
      );
    } finally {
      _isSyncingBuffer = false;
      notifyListeners();
    }
  }

  Future<void> loadVehicles() async {
    try {
      _isLoading = true;
      notifyListeners();
      final String userId = sl<AuthProvider>().user?.id ?? "0";
      _myVehicles = await _driverRepository.getAssignedVehicles(userId);

      if (_myVehicles.isNotEmpty) {
        if (_selectedVehicle == null) {
          _selectedVehicle = _myVehicles.first;
        } else {
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

  Future<void> initActiveTrip() async {
    try {
      final tripData = await _tripRepository.getActiveTrip();

      if (tripData != null) {
        _activeTrip = tripData;
        notifyListeners();
      } else {
        _activeTrip = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error refrescando viaje activo: $e");
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

      sl<WalletProvider>().loadWalletData(force: true);
    });
  }

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

      _passengerLocation = acceptedTrip.originLocation;

      _startPassengerGpsListener(_activeTrip!.id);
      _startRouteRecalculationTimer();

      notifyListeners();

      await _storageService.saveCurrentTrip(_activeTrip!);
      await _calculateRouteForCurrentStatus();
    } catch (e) {
      debugPrint("Error al aceptar viaje: $e");
      _isLoading = false;

      String mensajeAMostrar = "No se pudo aceptar el viaje. Intenta de nuevo.";

      final errorString = e.toString();
      if (errorString.contains("saldo") ||
          errorString.contains("bajo") ||
          errorString.contains("Recarga")) {
        mensajeAMostrar = "Tu saldo es muy bajo. Recarga para continuar.";
      } else {
        mensajeAMostrar = errorString.replaceAll("Exception:", "").trim();
      }

      _showError(mensajeAMostrar);

      notifyListeners();
    }
  }

  bool get isActiveTripScheduled {
    if (_activeTrip == null) return false;
    return _activeTrip!.scheduledAt != null;
  }

  Future<void> rejectIncomingTrip() async {
    if (_incomingTrip == null) return;

    _lastRejectedTripId = _incomingTrip!.id;

    try {
      final idParaResponder = _incomingTrip!.assignmentId ?? _incomingTrip!.id;
      await _tripRepository.rejectTrip(idParaResponder);

      _incomingTrip = null;
      notifyListeners();
    } catch (e) {
      debugPrint("Error: $e");
    }

    Future.delayed(
      const Duration(seconds: 5),
      () => _lastRejectedTripId = null,
    );
  }

  Future<void> iniciarRutaAlOrigen() async {
    if (_activeTrip == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _updateTripStatus('ACCEPTED');
    } catch (e) {
      debugPrint("🚨 Error al iniciar ruta al origen: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

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
        final tripReal = await _tripRepository.getActiveTrip();

        if (tripReal != null) {
          _activeTrip = tripReal;

          await _storageService.saveCurrentTrip(_activeTrip!);

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

              _hasReceivedPassengerGps = true;

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
    _hasReceivedPassengerGps = false;
  }

  Future<void> cancelTripAsDriver(String tripId) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _tripRepository.updateTripStatus(tripId, 'CANCELLED');

      _finishTrip();
    } catch (e) {
      debugPrint("Error al cancelar: $e");
      _finishTrip();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // =======================================================
  // E. MÁQUINA DE ESTADOS Y COBRO (LÓGICA CRÍTICA)
  // =======================================================

  Future<void> handleTripAction(BuildContext context) async {
    if (_activeTrip == null) return;

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

      const Distance distance = Distance();
      final double distanceInMeters = distance.as(
        LengthUnit.Meter,
        _currentPosition!,
        _activeTrip!.originLocation,
      );

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
                        backgroundColor: AppColors.primaryGreen,
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
        return;
      }
    }

    if (_activeTrip!.status == TripStatus.STARTED) {
      await _initiatePaymentFlow(context);
    } else {
      await _advanceStatusOnly();
    }
  }

  Future<void> _initiatePaymentFlow(BuildContext context) async {
    _isLoading = true;
    notifyListeners();

    try {
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

      if (context.mounted) {
        showModalBottomSheet(
          context: context,
          isDismissible: false,
          enableDrag: false,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => PaymentWaitingSheet(
            tripId: _activeTrip!.id,
            amount: _activeTrip!.price,
            paymentMethod: _activeTrip!.paymentMethod,
            onPaymentConfirmed: (Trip freshTrip) {
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

  Future<void> _finalizeTripWithWallet(
    BuildContext context,
    Trip? updatedTrip,
  ) async {
    if (_activeTrip == null && updatedTrip == null) return;

    if (updatedTrip != null) {
      _activeTrip = updatedTrip;
    }

    try {
      if (context.mounted) {
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
    _extraWaitingTimeAdded = false;

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

      _finishTrip();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Viaje cancelado con éxito")),
        );
      }
    } catch (e) {
      debugPrint("Error cancelando: $e");

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
      destination = _activeTrip!.originLocation;
    } else if (_activeTrip!.status == TripStatus.STARTED) {
      destination = _activeTrip!.destinationLocation;
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

    if (closestIndex < _routePoints.length) {
      _routePoints = _routePoints.sublist(closestIndex);
      notifyListeners();
    }
  }

  String _extractExceptionMessage(dynamic e) {
    try {
      if (e != null) {
        final dynamic error = e;

        if (error.response != null) {
          final responseData = error.response.data;
          if (responseData != null) {
            if (responseData is Map && responseData.containsKey('message')) {
              return responseData['message'].toString();
            } else if (responseData is String) {
              final decoded = json.decode(responseData);
              if (decoded is Map && decoded.containsKey('message')) {
                return decoded['message'].toString();
              }
            }
          }
        }

        if (error.message != null) {
          return error.message.toString();
        }
      }
    } catch (_) {}

    return e.toString().replaceAll("Exception: ", "");
  }

  @override
  void dispose() {
    _positionSubscription?.cancel().catchError((e) => null);
    _tripSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _stopPassengerGpsListener();
    _stopRouteRecalculationTimer();
    _waitTimer?.cancel();
    _breakTimer?.cancel();
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
