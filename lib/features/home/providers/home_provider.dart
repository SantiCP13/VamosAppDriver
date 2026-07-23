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
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../../core/services/background_gps_service.dart'; // Ajusta la ruta si es necesario
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
import '../../auth/providers/auth_provider.dart';
import '../../maps/services/route_service.dart';

class HomeProvider extends ChangeNotifier {
  // 1. INYECCIÓN DE DEPENDENCIAS
  final LocationService _locationService = sl<LocationService>();
  final StorageService _storageService = sl<StorageService>();
  final DriverRepository _driverRepository = sl<DriverRepository>();
  final TripRepository _tripRepository = sl<TripRepository>();
  final RouteService _routeService = RouteService();
  // 🟢 INSTANCIA Y MÉTODOS DE NOTIFICACIÓN LOCAL
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  void initLocalNotifications() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );
    await _localNotifications.initialize(initSettings);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  bool _hasPendingWaitingDecision = false;
  bool get hasPendingWaitingDecision => _hasPendingWaitingDecision;

  void dismissWaitingDecision() {
    _hasPendingWaitingDecision = false;
    notifyListeners();
  }

  StreamSubscription? _turnoSubscription;
  PusherChannelsClient? _turnoPusherClient;
  // ⏰ [SOCKET TURNO] Escucha en segundo plano si la administración finaliza nuestro turno de forma remota
  void _startListeningTurnoUpdates(String userId) async {
    _turnoSubscription?.cancel();
    _turnoPusherClient?.disconnect();

    const storage = FlutterSecureStorage();
    final token = await storage.read(key: 'auth_token');
    if (token == null) return;

    _turnoPusherClient = PusherChannelsClient.websocket(
      options: PusherChannelsOptions.fromHost(
        scheme: 'wss',
        host: 'api.vamosapp.com.co',
        port: 443,
        key: '06exymiubefjjglwmvqe',
      ),
      connectionErrorHandler: (exception, trace, client) {
        debugPrint("🚨 Error de Sockets en Turno Conductor: $exception");
      },
    );

    _turnoPusherClient!.eventStream.listen((event) {
      if (event.name == 'pusher:connection_established') {
        final channel = _turnoPusherClient!.privateChannel(
          'private-conductor.$userId',
          authorizationDelegate: DriverPusherAuth(token: token),
        );

        channel.subscribe();

        _turnoSubscription = channel
            .bind(
              'App\\Events\\TurnoEstadoActualizadoEvent',
            ) // 🟢 CORREGIDO: Sin el punto inicial
            .listen((e) {
              if (e.data != null) {
                try {
                  final data = json.decode(e.data!);
                  final String nuevoEstado = data['estado'].toString();

                  debugPrint(
                    "⏰ [SOCKET TURNO] Actualización de estado recibida: $nuevoEstado",
                  );

                  if (nuevoEstado == 'FINALIZADO' || nuevoEstado == 'OFFLINE') {
                    _turnoEstado = 'OFFLINE';
                    _isOnline = false;

                    // Limpieza absoluta e instantánea de estados
                    _stopBreakTimer();
                    _stopLunchTimer();
                    _stopListeningTrips();
                    _stopHeartbeat();
                    _activeTrip = null;
                    _routePoints = [];
                    _storageService.clearCurrentTrip();

                    notifyListeners();

                    // Dispara una alerta en primer plano al chofer
                    showLocalNotification(
                      "Turno Finalizado",
                      "Tu turno ha sido cerrado de forma remota por la administración.",
                    );
                  }
                } catch (ex) {
                  debugPrint("Error procesando WebSocket de Turno: $ex");
                }
              }
            });
        channel.bind('ConductorDespertadoEvent').listen((e) {
          debugPrint(
            "⚡ [SOCKET DESPERTAR] ¡Señal de despertar recibida de la Torre de Control!",
          );

          // Emite una alerta nativa en el centro de notificaciones del celular
          showLocalNotification(
            "Sincronización GPS ⚡",
            "Señal de localización en vivo recibida de la Torre de Control.",
          );

          forzarReporteGpsInmediato();
        });
      }
    });

    _turnoPusherClient!.connect();
  }

  void showLocalNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'vamos_driver_status_channel',
          'Alertas de Servicio',
          importance: Importance.max,
          priority: Priority.high,
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

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
  // 🟢 Nueva variable para registrar el tiempo del último envío al backend
  DateTime? _lastBackendTransmissionTime;
  Trip? _incomingTrip;
  Trip? _activeTrip;
  set activeTrip(Trip? trip) {
    _updateActiveTripWithPreservation(trip);
    notifyListeners();
  }

  int _proposedNewDurationMinutes = 0;
  int get proposedNewDurationMinutes => _proposedNewDurationMinutes;
  bool _hasPendingLateAlert = false;
  bool get hasPendingLateAlert => _hasPendingLateAlert;

  Trip? _lateTrip;
  Trip? get lateTrip => _lateTrip;

  void dismissLateAlert() {
    _hasPendingLateAlert = false;
    _lateTrip = null;
    notifyListeners();
  }

  int _proposedFinalSegmentMinutes = 0;
  int get proposedFinalSegmentMinutes => _proposedFinalSegmentMinutes;
  // --- VARIABLES DE ROBUSTEZ Y CONEXIÓN (Estilo Uber/DiDi) ---
  // --- VARIABLES DE ROBUSTEZ Y CONEXIÓN (Estilo Uber/DiDi) ---
  bool _isNetworkDisconnected = false;
  bool get isNetworkDisconnected => _isNetworkDisconnected;

  bool _isGpsSignalLost = false;
  bool get isGpsSignalLost => _isGpsSignalLost;

  // NUEVO: Almacenamiento temporal de puntos GPS en zonas sin cobertura
  final List<Map<String, dynamic>> _offlineTrackingBuffer = [];
  bool _isSyncingBuffer = false;

  // 🟢 TEMPORIZADORES DE VIGILANCIA EN TIEMPO REAL
  Timer? _reconnectionWatchdog;
  Timer? _gpsWatchdog;
  DateTime? _lastValidGpsTimestamp;

  // 🟢 CONTADOR PARA FILTRAR EL COLD START (ARRANQUE EN FRÍO) DEL GPS
  int _consecutiveInaccurateGpsCount = 0;
  // --- NUEVAS VARIABLES PARA EL CONTROL DE TURNOS (3 ESTADOS) ---
  String _turnoEstado = 'OFFLINE';
  int _breakSecondsRemaining = 900;
  Timer? _breakTimer;
  DateTime? _breakStartTime;

  bool _alreadyHadLunch = false;
  bool get alreadyHadLunch => _alreadyHadLunch;
  String get turnoEstado => _turnoEstado;
  int get breakSecondsRemaining => _breakSecondsRemaining;
  // 🟢 TEMPORIZADORES DE VIGILANCIA EN TIEMPO REAL

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
  double _proposedLatDestino = 0.0;
  double get proposedLatDestino => _proposedLatDestino;

  double _proposedLngDestino = 0.0;
  double get proposedLngDestino => _proposedLngDestino;
  List<Vehicle> _myVehicles = [];
  Vehicle? _selectedVehicle;
  List<DriverDocument> _documents = [];

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription? _tripSubscription;

  double _incomingDistance = 0;
  double _incomingTollsTotal = 0.0;
  double get incomingTollsTotal => _incomingTollsTotal;

  List<dynamic> _incomingTollsDetails = [];
  List<dynamic> get incomingTollsDetails => _incomingTollsDetails;
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
  double _proposedNewTolls = 0.0;
  double get proposedNewTolls => _proposedNewTolls;
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

  void _setNetworkDisconnected(bool value) {
    if (_isNetworkDisconnected != value) {
      _isNetworkDisconnected = value;
      notifyListeners();

      if (_isNetworkDisconnected) {
        // Si nos quedamos sin red, arranca la vigilancia automática de reconexión
        _startReconnectionWatchdog();
      } else {
        // Si recuperamos la red, apagamos la vigilancia para ahorrar batería
        _reconnectionWatchdog?.cancel();
        _reconnectionWatchdog = null;

        // 🟢 NUEVO: Forzamos la recarga automática de todo el estado del servidor
        recargarEstadoCompleto();

        // Sincronizar coordenadas en buffer offline
        if (_offlineTrackingBuffer.isNotEmpty) {
          _syncOfflineTrackingBuffer();
        }
      }
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

        // =====================================================================
        // 🟢 CORREGIDO: Apagar los relojes y de-programar notificaciones locales
        // =====================================================================
        _stopBreakTimer();
        _stopLunchTimer();

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

  // 🟢 MÉTODO: Monitorea activamente el internet en segundo plano cuando se cae la señal
  void _startReconnectionWatchdog() {
    _reconnectionWatchdog?.cancel();
    _reconnectionWatchdog = Timer.periodic(const Duration(seconds: 4), (
      timer,
    ) async {
      if (!_isNetworkDisconnected) {
        _reconnectionWatchdog?.cancel();
        return;
      }
      try {
        // Intentamos una petición ultra ligera al endpoint público /empresas usando ApiClient
        final dio = ApiClient().dio;
        final response = await dio
            .get('/empresas')
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          _setNetworkDisconnected(false);
        }
      } catch (_) {
        // Sigue sin internet, reintentará en el próximo ciclo de 4 segundos
      }
    });
  }

  // 🛰️ [AUTO-HEALING WATCHDOG] Reinicia el temporizador de alerta del GPS (Despierta el stream en segundo plano)
  void _resetGpsWatchdog() {
    _gpsWatchdog?.cancel();

    if (_currentProfile == TrackingProfile.onlineIdle ||
        _currentProfile == TrackingProfile.activeTrip) {
      _gpsWatchdog = Timer(const Duration(seconds: 35), () async {
        debugPrint(
          "🛰️ [GPS WATCHDOG] ¡35 segundos sin coordenadas! Ejecutando auto-reparación...",
        );

        bool gpsHardwareEnabled = await Geolocator.isLocationServiceEnabled();

        if (!gpsHardwareEnabled) {
          if (!_isGpsSignalLost) {
            _isGpsSignalLost = true;
            notifyListeners();
            debugPrint(
              "🛰️ [GPS WATCHDOG] Sensor GPS apagado por hardware. Alerta mostrada.",
            );
          }
        } else {
          // El sensor físico está encendido pero el hilo de Flutter se durmió por el sistema operativo.
          // Forzamos un reinicio del canal de ubicación (Auto-Healing) para forzar su despertar.
          debugPrint(
            "🛰️ [GPS WATCHDOG] Reiniciando canal de ubicación de forma activa...",
          );
          _startTracking();
        }
      });
    }
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
        _alreadyHadLunch = turnoData['ya_almorzo'] ?? false;

        // 🟢 SINCRO DE CONEXIÓN ACTIVA:
        // Si el servidor confirma el turno activo, forzamos '_isOnline = true'
        // para que el Menú Lateral (SideMenu) y la cabecera reaccionen de inmediato.
        if (_turnoEstado == 'ACTIVO') {
          _isOnline = true;

          // Levantamos escuchas de sockets y de tracking en segundo plano en caso de caída
          _startListeningTrips();
          _startTracking();
        } else {
          _isOnline = false;
          _stopListeningTrips();
        }

        // 🟢 RESTAURACIÓN DE VEHÍCULO RE-DISEÑADA:
        // Obtenemos el id del vehículo que el servidor tiene registrado en el turno
        final serverVehicleId = turnoData['id_vehiculo']?.toString();

        // Si la lista de vehículos local está vacía, la cargamos primero
        if (_myVehicles.isEmpty) {
          await loadVehicles();
        }

        // Buscamos dentro de la flota el vehículo que tiene el turno activo en el servidor
        if (serverVehicleId != null && _myVehicles.isNotEmpty) {
          try {
            _selectedVehicle = _myVehicles.firstWhere(
              (v) => v.id.toString() == serverVehicleId,
            );
          } catch (_) {
            // Fallback preventivo si el vehículo no coincide con la lista local
            if (_selectedVehicle == null) {
              await loadVehicles();
            }
          }
        } else if (_selectedVehicle == null) {
          await loadVehicles();
        }
      } else {
        _turnoEstado = 'OFFLINE';
        _isOnline = false;
        _stopListeningTrips();
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
    _routeRecalculateTimer = Timer.periodic(const Duration(seconds: 30), (
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
    _waitSeconds = 300; // 5 minutos de cortesía (300 segundos)

    _waitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _waitSeconds--;

      // 🚨 Al llegar exactamente a 0, activamos el gatillo lógico para el diálogo interactivo
      if (_waitSeconds == 0) {
        _hasPendingWaitingDecision = true;
      }
      notifyListeners();
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

      // === COMPROBACIÓN DE MODIFICACIÓN DE RUTA ===
      final bool routeModified =
          oldTrip.destinationAddress != newTrip.destinationAddress ||
          oldTrip.desglosePrecio?['paradas'] !=
              newTrip.desglosePrecio?['paradas'];

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

      if (statusChanged || routeModified) {
        _routePoints = [];
        _totalRouteDistanceMeters = 0.0;
        _totalRouteDurationSeconds = 0.0;

        // Forzamos el recalculo inmediato en caliente
        _calculateRouteForCurrentStatus();
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

      // 🟢 ALMACENAMOS LOS PEAJES DETECTADOS DE CAMINO A RECOGER AL PASAJERO
      _incomingTollsTotal = routeResult.totalTolls;
      _incomingTollsDetails = routeResult.tollsDetails;

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
    initLocalNotifications(); // 🟢 INICIALIZAR ALERTAS LOCALES
    BackgroundGpsService.init();

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
      _startListeningTurnoUpdates(authProvider.user!.id);

      try {
        final turnoData = await _driverRepository.obtenerTurnoActivo();
        if (turnoData['status'] == 'success' &&
            turnoData['tiene_turno_activo'] == true) {
          _turnoEstado = turnoData['estado'];
          _alreadyHadLunch = turnoData['ya_almorzo'] ?? false;

          // 🟢 NUEVO: SINCRONIZAR VEHÍCULO ACTIVO CON LA FLOTA AL ARRANCAR
          final serverVehicleId = turnoData['id_vehiculo']?.toString();
          if (serverVehicleId != null && _myVehicles.isNotEmpty) {
            try {
              _selectedVehicle = _myVehicles.firstWhere(
                (v) => v.id.toString() == serverVehicleId,
              );
            } catch (_) {
              // Si falla la búsqueda, mantiene el vehículo pre-seleccionado
            }
          }

          if (_turnoEstado == 'ACTIVO') {
            _isOnline = true;
            _startListeningTrips();
            _startTracking();
            _startRouteRecalculationTimer();
          } else if (_turnoEstado == 'BREAK') {
            // ... (mantiene tu lógica de break de 15 min)
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
        _setNetworkDisconnected(true);
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
        _setNetworkDisconnected(true);
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
          }
        }
      } catch (e) {
        debugPrint(
          "Error buscando viaje activo de respaldo offline en inicio: $e",
        );
        _setNetworkDisconnected(true);
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

  // 🟢 NUEVO MÉTODO: Fuerza el reporte de coordenadas inmediato al servidor
  Future<void> forzarReporteGpsInmediato() async {
    try {
      debugPrint("🛰️ [SOCKET DESPERTAR] Iniciando geolocalización forzada...");
      final position = await _locationService.getCurrentLocation();
      if (position != null) {
        await _driverRepository.updatePosition(
          position.latitude,
          position.longitude,
        );
        _currentPosition = LatLng(position.latitude, position.longitude);
        notifyListeners();
        debugPrint(
          "✅ [SOCKET DESPERTAR] Reporte GPS forzado enviado con éxito.",
        );
      }
    } catch (e) {
      debugPrint("❌ [SOCKET DESPERTAR] Error en reporte forzado: $e");
    }
  }

  // 1. Añade esta propiedad en la sección de estado de HomeProvider
  TrackingProfile _currentProfile = TrackingProfile.offline;
  TrackingProfile get currentProfile => _currentProfile;

  // 2. Método auxiliar para evaluar cuál es el perfil que la aplicación exige en este instante
  TrackingProfile _determineRequiredProfile() {
    if (_activeTrip != null) {
      return TrackingProfile.activeTrip;
    }
    // 🟢 CORRECCIÓN: El GPS del conductor nunca se apaga para que el mapa responda siempre en tiempo real
    return TrackingProfile.onlineIdle;
  }

  void _startTracking() {
    final requiredProfile = _determineRequiredProfile();
    debugPrint("🔋 [GPS CONTROL] Solicitando perfil: ${requiredProfile.name}");

    // Si ya estamos transmitiendo bajo este perfil exacto, evitamos sobrecargar el hardware
    if (_positionSubscription != null && _currentProfile == requiredProfile) {
      return;
    }

    _currentProfile = requiredProfile;

    _positionSubscription?.cancel().catchError((error) {
      debugPrint("ℹ️ Silenciando reinicio de canal de GPS: $error");
    });

    _positionSubscription = _locationService
        .getPositionStream(profile: _currentProfile)
        .listen((pos) {
          _updatePosition(pos);
        });

    // =====================================================================
    // 🟢 NUEVO: CONTROL DEL SERVICIO EN SEGUNDO PLANO SEGÚN EL PERFIL
    // =====================================================================
    if (_currentProfile == TrackingProfile.activeTrip) {
      BackgroundGpsService.start(
        title: "Servicio de Conducción Activo 🏎️",
        message: "Navegación en tiempo real activa para guiar tu viaje.",
      );
    } else if (_currentProfile == TrackingProfile.onlineIdle) {
      BackgroundGpsService.start(
        title: "Conductor en Línea",
        message: "VAMOS está conectado esperando asignaciones de viaje.",
      );
    } else {
      // Si el conductor se desconecta o pasa a offline, apagamos el servicio nativo
      BackgroundGpsService.stop();
    }

    // Si está en línea, iniciamos también el reporte periódico de presencia
    if (_isOnline) {
      _startHeartbeat();
    } else {
      _stopHeartbeat();
    }
  }

  void _updatePosition(Position pos) async {
    // 1. Reiniciamos el temporizador de alerta (el sensor GPS de hardware sigue vivo)
    _resetGpsWatchdog();

    final newLocation = LatLng(pos.latitude, pos.longitude);

    // 2. CONTROL DE PRECISIÓN DE ALTA TOLERANCIA
    // Ignoramos saltos masivos (celdas de red móvil > 250m) para evitar brincos bruscos en el mapa.
    if (pos.accuracy > 250.0) {
      _consecutiveInaccurateGpsCount++;

      // Solo activamos el banner si recibimos 3 o más lecturas imprecisas consecutivas
      if (_consecutiveInaccurateGpsCount >= 3) {
        if (!_isGpsSignalLost) {
          _isGpsSignalLost = true;
          notifyListeners();
          debugPrint(
            "🛰️ [GPS ACCURACY] Señal inestable consecutiva (${pos.accuracy}m). Activando alerta.",
          );
        }
      }
      return; // Ignoramos únicamente este punto ruidoso para evitar saltos en el mapa
    }

    // 3. SEÑAL SALUDABLE (Coordenada precisa recibida)
    _consecutiveInaccurateGpsCount = 0;
    _lastValidGpsTimestamp = DateTime.now();

    if (_isGpsSignalLost) {
      _isGpsSignalLost = false;
      notifyListeners();
      debugPrint(
        "🛰️ [GPS ACCURACY] Excelente precisión restaurada (${pos.accuracy}m). Desactivando alerta.",
      );
    }

    // Guardamos la última posición en disco local como respaldo inmediato de UI
    try {
      await _storageService.saveLastPosition(pos.latitude, pos.longitude);
    } catch (ex) {
      debugPrint("🚨 [GPS STORAGE] Fallo de persistencia rápida: $ex");
    }

    // C. CÁLCULO DE DESPLAZAMIENTO REAL
    if (_currentPosition != null) {
      const Distance distance = Distance();
      final double dist = distance.as(
        LengthUnit.Meter,
        _currentPosition!,
        newLocation,
      );

      // FILTRO DE MOVIMIENTO INTELIGENTE CON LATIDO (HEARTBEAT) ESTÁTICO:
      final bool estaInmovil = pos.speed < 0.25 && dist < 2.0;

      // Evaluar si ya pasaron 10 segundos desde el último envío
      final bool debeEnviarLatido =
          _lastBackendTransmissionTime == null ||
          DateTime.now().difference(_lastBackendTransmissionTime!).inSeconds >=
              10;

      if (!estaInmovil || debeEnviarLatido) {
        // =====================================================================
        // CORRECCIÓN LOGÍSTICA: CALCULAR EL RUMBO ANTES DE TRANSMITIR AL BACKEND
        // Evita el lag de rotación en el mapa del pasajero
        // =====================================================================
        if (dist > 1.8) {
          _currentHeading = _calculateBearing(_currentPosition!, newLocation);
          debugPrint(
            "🧭 [GPS BEARING] Rumbo recalculado por distancia: $_currentHeading",
          );
        } else if (pos.heading > 0) {
          _currentHeading = pos.heading;
          debugPrint(
            "🧭 [GPS BEARING] Rumbo tomado desde hardware nativo: $_currentHeading",
          );
        }

        // 1. Reporte en estado de espera (Online pero sin viaje)
        if (_isOnline &&
            _activeTrip == null &&
            (dist > 12.0 || debeEnviarLatido)) {
          _sendPositionToBackend(pos.latitude, pos.longitude);
          _lastBackendTransmissionTime = DateTime.now();
        }

        // 2. Reporte en viaje activo
        if (_activeTrip != null) {
          final bool enServicioActivo =
              _activeTrip!.status == TripStatus.ACCEPTED ||
              _activeTrip!.status == TripStatus.ARRIVED ||
              _activeTrip!.status == TripStatus.STARTED;

          if (enServicioActivo && (dist > 3.0 || debeEnviarLatido)) {
            _sendTripLocationToBackend(
              _activeTrip!.id,
              pos.latitude,
              pos.longitude,
              pos.speed,
            );
            _lastBackendTransmissionTime = DateTime.now();
          }
        }
      }
    }

    _currentPosition = newLocation;
    notifyListeners();
  }

  // 🟢 Diálogo Premium de finalización de viaje con éxito para el Conductor
  void _showTripSuccessDialog(BuildContext context, double amount) {
    final currency = _formatCurrency(amount);
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
                  // ignore: deprecated_member_use
                  color: AppColors.primaryGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primaryGreen,
                  size: 40,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                "¡Viaje Finalizado con Éxito!",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "El servicio ha concluido exitosamente.",
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  color: Colors.grey[400],
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Monto total cobrado:",
                      style: GoogleFonts.montserrat(
                        color: Colors.grey[400],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      currency,
                      style: GoogleFonts.montserrat(
                        color: AppColors.primaryGreen,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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

        // 🟢 NUEVO: DETECTAR SI LA PROPUESTA FUE RECHAZADA POR TIMEOUT O ACEPTADA (CERRAR MODAL EN CHOFER)
        final String currentStatus = trip.status.toString().split('.').last;
        if (currentStatus == 'ROUTE_CHANGE_REJECTED' ||
            currentStatus == 'ROUTE_MODIFIED') {
          debugPrint(
            "⏰ [SOCKET] Propuesta de ruta resuelta ($currentStatus). Limpiando modal flotante del chofer.",
          );
          _hasPendingRouteChangeProposal = false;
          notifyListeners();

          if (currentStatus == 'ROUTE_CHANGE_REJECTED') {
            return; // Si es rechazo o timeout, cerramos el diálogo y detenemos la ejecución de este evento
          }
        }

        // 🟢 NUEVO: DISPARAR ALERTAS LOCALES DEL CHOFER SEGÚN EL ESTADO
        if (trip.status == TripStatus.PENDING) {
          if (_lastRejectedTripId != trip.id) {
            showLocalNotification(
              "¡Nueva Oferta de Viaje!",
              "Tienes una nueva solicitud de servicio disponible cerca.",
            );
          }
        } else if (trip.status == TripStatus.STARTED) {
          showLocalNotification(
            "¡Viaje Iniciado!",
            "Dirígete hacia el destino final de forma segura. El código ha sido verificado con éxito.",
          );
        } else if (trip.status == TripStatus.CANCELLED) {
          showLocalNotification(
            "Viaje Cancelado",
            "El pasajero ha cancelado el servicio activo.",
          );
        } else if (trip.status.name == 'ROUTE_CHANGE_PROPOSED') {
          showLocalNotification(
            "Propuesta de Cambio de Ruta",
            "El pasajero ha propuesto modificar las paradas o el destino.",
          );
        }
        // 🟢 NUEVO: DETECTAR ALERTA DE RETRASO EN VIAJES PROGRAMADOS
        if (trip.status == TripStatus.SCHEDULED_LATE_ALERT) {
          debugPrint(
            "⏰ [SOCKET] Alerta de retraso recibida para el viaje #${trip.id}",
          );
          _lateTrip = trip;
          _hasPendingLateAlert = true;

          try {
            // Emite una alerta local en el centro de notificaciones por si la app está en segundo plano
            NotificationService.showNotification(
              id: 777,
              title: "¡Estás retrasado para un viaje!",
              body:
                  "Tu viaje programado ya debió iniciar. Por favor, comunícate con el pasajero de inmediato para evitar que cancele.",
            );
          } catch (e) {
            debugPrint("Error mostrando notificación local de retraso: $e");
          }

          notifyListeners();
          return;
        }
        // 🟢 SOLUCIÓN: Si el servidor notifica que la ruta fue modificada (ROUTE_MODIFIED)
        final String sName = trip.status.toString().split('.').last;
        if (sName == 'ROUTE_MODIFIED' || trip.status == TripStatus.STARTED) {
          debugPrint(
            "🔄 [SOCKET] Sincronizando nueva ruta y precio modificado en caliente...",
          );

          final fullTrip = await _tripRepository.getActiveTrip();
          if (fullTrip != null) {
            _updateActiveTripWithPreservation(fullTrip);
            await _storageService.saveCurrentTrip(_activeTrip!);
          }
          notifyListeners();
          return;
        }

        if (trip.status.name == 'NO_DISPONIBLE' &&
            _incomingTrip?.id == trip.id) {
          debugPrint("🧹 [SOCKET] Limpiando alerta: viaje tomado por otro.");
          _incomingTrip = null;
          notifyListeners();
          return;
        }

        if (trip.status == TripStatus.COMPLETED) {
          debugPrint("🛑 [SOCKET] Viaje completado recibido por Reverb.");

          // 🟢 CORRECCIÓN: Quitamos el '\$' manual porque _formatCurrency ya lo incluye
          showLocalNotification(
            "¡Viaje Finalizado con Éxito!",
            "El servicio ha concluido exitosamente. Valor: ${_formatCurrency(trip.price)}",
          );

          _finishTrip();
          return;
        }

        if (trip.status == TripStatus.CANCELLED) {
          debugPrint("🛑 [SOCKET] Cancelación recibida por Reverb.");
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
        }

        // === NUEVO: DETECTAR PROPUESTA DE CAMBIO DE RUTA EN TIEMPO REAL ===
        // === NUEVO: DETECTAR PROPUESTA DE CAMBIO DE RUTA EN TIEMPO REAL ===
        if (trip.status.name == 'ROUTE_CHANGE_PROPOSED') {
          _proposedNewPrice =
              double.tryParse(
                trip.desglosePrecio?['precio_nuevo']?.toString() ?? '0',
              ) ??
              0.0;
          _proposedPriceIncrement =
              double.tryParse(
                trip.desglosePrecio?['incremento_tarifa']?.toString() ?? '0',
              ) ??
              0.0;
          _proposedNewDriverRevenue =
              double.tryParse(
                trip.desglosePrecio?['nueva_ganancia']?.toString() ?? '0',
              ) ??
              0.0;
          _proposedDriverRevenueIncrement =
              double.tryParse(
                trip.desglosePrecio?['incremento_ganancia']?.toString() ?? '0',
              ) ??
              0.0;
          _proposedNewDestination =
              trip.desglosePrecio?['destino'] ?? 'Nuevo Destino';
          _proposedNewStops = trip.desglosePrecio?['paradas'] ?? [];

          // 🟢 NUEVOS CAMPOS DE DURACIÓN DE VIAJE COMPLETO Y TRAMOS
          _proposedNewDurationMinutes =
              int.tryParse(
                trip.desglosePrecio?['duracion_total_minutos']?.toString() ??
                    '0',
              ) ??
              0;
          _proposedFinalSegmentMinutes =
              int.tryParse(
                trip.desglosePrecio?['tiempo_tramo_final_minutos']
                        ?.toString() ??
                    '0',
              ) ??
              0;
          _proposedLatDestino =
              double.tryParse(
                trip.desglosePrecio?['lat_destino']?.toString() ?? '0.0',
              ) ??
              0.0;
          _proposedLngDestino =
              double.tryParse(
                trip.desglosePrecio?['lng_destino']?.toString() ?? '0.0',
              ) ??
              0.0;
          _proposedNewTolls =
              double.tryParse(
                trip.desglosePrecio?['peajes_nuevos']?.toString() ?? '0',
              ) ??
              0.0;
          _hasPendingRouteChangeProposal = true;
          notifyListeners();
        } else if (trip.status == TripStatus.PENDING) {
          if (_lastRejectedTripId == trip.id) {
            debugPrint(
              "⚠️ [SOCKET] Ignorando evento PENDING de viaje recientemente rechazado.",
            );
            return;
          }

          // 🟢 EXCLUSIÓN DE VIAJES PROGRAMADOS EN EL OVERLAY EN TIEMPO REAL
          if (trip.scheduledAt != null) {
            debugPrint(
              "⏰ [SOCKET] Omitiendo oferta programada del overlay en caliente. Se procesará vía notificación.",
            );
            showLocalNotification(
              "¡Viaje Programado Asignado!",
              "Revisa la sección de 'Viajes Programados' para iniciar tu próximo servicio.",
            );
            notifyListeners();
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

  // 🟢 Formateador de moneda para uso interno del Provider
  String _formatCurrency(double amount) {
    return "\$${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}";
  }

  // === VARIABLES PARA LA PROPUESTA DE CAMBIO DE RUTA EN CURSO ===
  bool _hasPendingRouteChangeProposal = false;
  bool get hasPendingRouteChangeProposal => _hasPendingRouteChangeProposal;

  double _proposedNewPrice = 0.0;
  double get proposedNewPrice => _proposedNewPrice;

  double _proposedPriceIncrement = 0.0;
  double get proposedPriceIncrement => _proposedPriceIncrement;

  double _proposedNewDriverRevenue = 0.0;
  double get proposedNewDriverRevenue => _proposedNewDriverRevenue;

  double _proposedDriverRevenueIncrement = 0.0;
  double get proposedDriverRevenueIncrement => _proposedDriverRevenueIncrement;

  String _proposedNewDestination = '';
  String get proposedNewDestination => _proposedNewDestination;

  List<dynamic> _proposedNewStops = [];
  List<dynamic> get proposedNewStops => _proposedNewStops;

  /// Envía la respuesta del conductor (aceptar o rechazar) al servidor
  Future<bool> responderPropuestaRuta(bool aceptar) async {
    if (_activeTrip == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      final dio = ApiClient().dio;
      final response = await dio.post(
        "/viajes/${_activeTrip!.id}/responder-propuesta-ruta",
        data: {'respuesta': aceptar ? 'aceptar' : 'rechazar'},
      );

      if (response.statusCode == 200) {
        _hasPendingRouteChangeProposal = false;

        // 🟢 SOLUCIÓN: Si aceptó, extraemos de inmediato el viaje actualizado de la respuesta HTTP
        if (aceptar) {
          final freshTripMap = response.data['viaje'];
          if (freshTripMap != null) {
            final freshTrip = Trip.fromMap(freshTripMap);
            _updateActiveTripWithPreservation(freshTrip);

            // Guardamos localmente en memoria persistente
            await _storageService.saveCurrentTrip(_activeTrip!);
          }
        }

        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error al responder propuesta de ruta: $e");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

  // 🟢 CORREGIDO: Llama al endpoint de ir al encuentro programado usando la ruta real
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
      final dio = ApiClient().dio;

      // 🟢 RUTA CORREGIDA: /viajes/{id}/ir-al-encuentro
      final response = await dio.post(
        '/viajes/${trip.id}/ir-al-encuentro',
        data: {
          'lat': _currentPosition?.latitude,
          'lng': _currentPosition?.longitude,
        },
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final freshTripMap = response.data['viaje'];
        if (freshTripMap != null) {
          final freshTrip = Trip.fromMap(freshTripMap);
          _updateActiveTripWithPreservation(freshTrip);
          await _storageService.saveCurrentTrip(_activeTrip!);
        }

        _passengerLocation = _activeTrip!.originLocation;

        _startListeningTrips();
        _startPassengerGpsListener(_activeTrip!.id);
        _startRouteRecalculationTimer();

        _isLoading = false;
        notifyListeners();
        return true;
      }

      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _activeTrip = null;
      _isLoading = false;
      notifyListeners();
      debugPrint("🚨 Error al iniciar ruta al origen con viaje programado: $e");
      // 🟢 CORRECCIÓN: Extraemos el string limpio del backend antes de elevar el error
      throw Exception(_extractExceptionMessage(e));
    }
  }

  // 🟢 CORREGIDO: Sincronizado para usar la ruta real al iniciar encuentro desde la Home Card
  Future<void> iniciarRutaAlOrigen() async {
    if (_activeTrip == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final dio = ApiClient().dio;

      // 🟢 RUTA CORREGIDA: /viajes/{id}/ir-al-encuentro
      final response = await dio.post(
        '/viajes/${_activeTrip!.id}/ir-al-encuentro',
        data: {
          'lat': _currentPosition?.latitude,
          'lng': _currentPosition?.longitude,
        },
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final freshTripMap = response.data['viaje'];
        if (freshTripMap != null) {
          final freshTrip = Trip.fromMap(freshTripMap);
          _updateActiveTripWithPreservation(freshTrip);
          await _storageService.saveCurrentTrip(_activeTrip!);
        }

        _passengerLocation = _activeTrip!.originLocation;
        _startListeningTrips();
        _startPassengerGpsListener(_activeTrip!.id);
        _startRouteRecalculationTimer();
      }
    } catch (e) {
      debugPrint("🚨 Error al iniciar ruta al origen desde la Home Card: $e");
      // 🟢 CORRECCIÓN: Extraemos el string limpio del backend antes de elevar el error
      throw Exception(_extractExceptionMessage(e));
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

    _isLoading = true;
    notifyListeners();

    // 🟢 1. COMPROBACIÓN INSTANTÁNEA DE INTERNET (Bypass por DNS a nivel de OS - Latencia de ~80ms)
    try {
      final lookup = await InternetAddress.lookup(
        'api.vamosapp.com.co',
      ).timeout(const Duration(milliseconds: 800));
      if (lookup.isEmpty || lookup.first.rawAddress.isEmpty) {
        _setNetworkDisconnected(true);
      } else {
        _setNetworkDisconnected(false);
      }
    } catch (_) {
      _setNetworkDisconnected(true);
    }

    // 🟢 2. COMPROBACIÓN INSTANTÁNEA DE GPS
    bool gpsHardwareEnabled = await Geolocator.isLocationServiceEnabled();
    final bool isGpsOutdated =
        _lastValidGpsTimestamp == null ||
        DateTime.now().difference(_lastValidGpsTimestamp!).inSeconds > 15;

    if (!gpsHardwareEnabled || isGpsOutdated) {
      _isGpsSignalLost = true;
      notifyListeners();
    }

    _isLoading = false;
    notifyListeners();

    // 🟢 ESCUDO CONTRA GAP ASÍNCRONO: Validamos que la pantalla siga activa
    if (!context.mounted) return;

    // 🟢 3. EVALUACIÓN Y RESTRICCIÓN INMEDIATA DE VIAJE SIN RED
    if (_isNetworkDisconnected && _routePoints.isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
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
                    color: Colors.redAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.redAccent,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  "Sin Conexión",
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Debes conectarte a internet para calcular la ruta e iniciar el servicio correctamente.",
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

      return; // Detiene la acción inmediatamente
    }

    // 🟢 4. EVALUACIÓN Y RESTRICCIÓN DE VIAJE SIN GPS ACTIVO
    if (_isGpsSignalLost && _activeTrip!.status == TripStatus.ACCEPTED) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "⚠️ Esperando señal de GPS estable para poder registrar tu ubicación de llegada en el sitio.",
          ),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return; // Detiene la acción
    }

    // If passes safety checks above, continue with standard button logic:
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

      // 🟢 RESTRICCIÓN DE DISTANCIA REMOVIDA:
      // El conductor ahora puede avanzar de estado sin importar la distancia al origen.
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

      // 🟢 ELIMINADO: La hoja emergente (showModalBottomSheet) ha sido removida con éxito.
      // Al actualizar _activeTrip!.status a DROPPED_OFF, el build del Home_Screen interceptará
      // el estado y pintará la pantalla de cobro a pantalla completa de forma inmune a hot-reloads.
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

  Future<void> finalizeTripWithWallet(
    BuildContext context,
    Trip? updatedTrip,
  ) async {
    if (_activeTrip == null && updatedTrip == null) return;

    if (updatedTrip != null) {
      _activeTrip = updatedTrip;
    }

    // 🟢 SOLUCIÓN: Mostramos el valor neto real cobrado (con descuento) en el diálogo de éxito del Conductor
    final double priceToDisplay = _activeTrip?.passengerCashToPay ?? 0.0;

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

        // 🟢 INYECCIÓN: Mostramos el modal de éxito con el valor recolectado
        _showTripSuccessDialog(context, priceToDisplay);
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

      notifyListeners();
      return _activeTrip;
    } catch (e) {
      debugPrint("Error actualizando estado: $e");
      rethrow;
    }
  }

  // 🟢 MÉTODO: Re-sincroniza todo el estado de forma silenciosa en segundo plano sin interrumpir la conducción
  Future<void> recargarEstadoCompleto() async {
    // 1. SILENT RE-SYNC: Si el conductor tiene un viaje en curso, mantenemos '_isLoading' en false
    // para evitar spinners de carga, parpadeos o reinicios visuales molestos en el mapa de navegación.
    final bool tieneViajeActivoLocal = _activeTrip != null;
    if (!tieneViajeActivoLocal) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      debugPrint(
        "🔄 [RECONEXIÓN] Iniciando sincronización silenciosa desde segundo plano...",
      );

      // A. Sincronizar el turno en segundo plano
      await verificarTurnoActivoConServidor();

      // B. Consultar el viaje activo real al servidor con un timeout preventivo
      final tripReal = await _tripRepository.getActiveTrip().timeout(
        const Duration(seconds: 4),
      );

      if (tripReal != null) {
        _updateActiveTripWithPreservation(tripReal);
        await _storageService.saveCurrentTrip(_activeTrip!);
        _passengerLocation = tripReal.originLocation;

        _startPassengerGpsListener(_activeTrip!.id);
        _startRouteRecalculationTimer();
      } else {
        // 🟢 BLINDAJE DE SEGURIDAD EXTREMO:
        // Si el servidor no responde o da nulo, pero el conductor SÍ tiene un viaje local en marcha
        // (ACCEPTED, ARRIVED, STARTED, DROPPED_OFF), NO lo borramos bajo ninguna circunstancia.
        // El conductor continuará guiándose y cobrando con el estado guardado localmente.
        if (!tieneViajeActivoLocal) {
          _activeTrip = null;
          _routePoints = [];
          await _storageService.clearCurrentTrip();
          _stopPassengerGpsListener();
          _stopRouteRecalculationTimer();
        }
      }
    } catch (e) {
      // Cualquier fallo de red durante la reconexión se silencia para no interferir con la navegación del viaje activo
      debugPrint(
        "🚨 Error en recarga de reconexión (Silenciado para conservar el viaje activo): $e",
      );
    } finally {
      if (!tieneViajeActivoLocal) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  void _finishTrip() {
    debugPrint("DEBUG: _finishTrip ejecutado.");

    _stopPassengerGpsListener();
    _stopRouteRecalculationTimer();

    _activeTrip = null;
    _routePoints = [];
    _extraWaitingTimeAdded = false;
    _hasPendingRouteChangeProposal = false; // Reset de propuesta

    _storageService.clearCurrentTrip();
    _startListeningTrips();

    // 🟢 NUEVO: Cancela y remueve todas las notificaciones locales activas en la barra de estado del teléfono
    _localNotifications.cancelAll();

    notifyListeners();
  }

  // 🟢 NUEVO: Apaga por completo el GPS y sockets al cerrar sesión (Evita fugas de batería)
  void stopTracking() {
    _positionSubscription?.cancel().catchError((e) => null);
    _positionSubscription = null;
    _currentProfile = TrackingProfile.offline;
    _stopHeartbeat();
    _stopListeningTrips();
    _stopPassengerGpsListener();
    _stopRouteRecalculationTimer();
    BackgroundGpsService.stop();

    _turnoEstado = 'OFFLINE';
    _isOnline = false;
    _activeTrip = null;
    _routePoints = [];
    _storageService.clearCurrentTrip();

    notifyListeners();
    debugPrint(
      "🔌 [GPS CONTROL] Rastreador y sockets apagados de forma segura por cierre de sesión.",
    );
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

    // =====================================================================
    // 🟢 OPTIMIZACIÓN: EVITAR RUTA SI YA SE LLEGÓ AL SITIO DE ENCUENTRO
    // =====================================================================
    if (_activeTrip!.status == TripStatus.ARRIVED) {
      if (_routePoints.isNotEmpty) {
        _routePoints = [];
        notifyListeners();
      }
      debugPrint(
        "🚗 [ROUTE] Conductor en el sitio (ARRIVED). Omitiendo cálculo de ruta hacia el origen.",
      );
      return;
    }

    // Protección offline de rutas
    if (_isNetworkDisconnected && _routePoints.isEmpty) {
      return;
    }
    if (_isNetworkDisconnected && _routePoints.isNotEmpty) {
      return;
    }
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
        // Reemplazar la primera llamada a getRoute:
        final routeResult = await _routeService
            .getRoute(
              _currentPosition!,
              destination,
              // 🟢 CORRECCIÓN: Solo enviar paradas intermedias si el viaje está en curso (STARTED)
              paradas: (_activeTrip!.status == TripStatus.STARTED)
                  ? _activeTrip?.intermediateStops
                  : null,
            )
            .timeout(const Duration(seconds: 10));

        _routePoints = routeResult.points;
        _totalRouteDistanceMeters = routeResult.distanceMeters.toDouble();
        _totalRouteDurationSeconds = routeResult.durationSeconds.toDouble();
        notifyListeners();
      } catch (e) {
        debugPrint("Error obteniendo ruta inicial del viaje (Conductor): $e");

        // 🟢 Marcamos al conductor como desconectado de inmediato si la petición de mapa falló por red
        _setNetworkDisconnected(true);
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

    if (minDistanceToRoute > 500.0) {
      try {
        // Reemplazar la segunda llamada a getRoute (dentro del bloque de recalculación por desvío):
        final routeResult = await _routeService
            .getRoute(
              _currentPosition!,
              destination,
              // 🟢 CORRECCIÓN: Solo enviar paradas intermedias si el viaje está en curso (STARTED)
              paradas: (_activeTrip!.status == TripStatus.STARTED)
                  ? _activeTrip?.intermediateStops
                  : null,
            )
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
    _turnoSubscription?.cancel(); // <--- 🟢 NUEVO
    _turnoPusherClient?.disconnect(); // <--- 🟢 NUEVO
    _heartbeatTimer?.cancel();
    _reconnectionWatchdog?.cancel();
    _gpsWatchdog?.cancel();
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
