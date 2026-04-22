// ignore_for_file: use_null_aware_elements

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
// IMPORTANTE: Estos 3 imports de Pusher son vitales para que no haya errores de tipo
import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:dio/dio.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/models/trip_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import 'trip_repository.dart';
import '../../../core/enums/payment_enums.dart'; // <--- 1. AGREGA ESTA LÍNEA

class ApiTripRepository implements TripRepository {
  final ApiClient _api = ApiClient();
  final StreamController<void> _fleetUpdateController =
      StreamController<void>.broadcast();
  final StreamController<double> _walletUpdateController =
      StreamController<double>.broadcast();

  PusherChannelsClient? _client;
  StreamSubscription? _eventSubscription;

  @override
  Stream<void> listenForFleetChanges() => _fleetUpdateController.stream;
  @override
  Stream<double> listenForWalletUpdates(String userId) =>
      _walletUpdateController.stream;

  @override
  Future<Trip> acceptTrip(String asignacionId, double lat, double lng) async {
    final response = await _api.dio.post(
      '/asignaciones/$asignacionId/responder',
      data: {
        'respuesta': 'aceptar',
        'lat': lat, // ✅ Enviamos ubicación actual del conductor
        'lng': lng,
      },
    );

    if (response.data['viaje'] != null) {
      return Trip.fromMap(response.data['viaje']);
    }
    throw Exception("No se recibió el viaje");
  }

  @override
  Stream<Trip> listenForTrips() {
    final user = sl<AuthProvider>().user;
    if (user == null) return const Stream.empty();
    final controller = StreamController<Trip>();
    _initSocket(controller, user.id, sl<StorageService>());
    return controller.stream;
  }

  void _initSocket(
    StreamController<Trip> controller,
    String userId,
    StorageService storage,
  ) async {
    debugPrint("🚀 INICIALIZANDO SOCKET PRIVADO PARA CONDUCTOR: $userId");
    final token = await storage.getToken();
    if (token == null) return;

    try {
      if (_client != null) {
        await _client!.disconnect();
        _eventSubscription?.cancel();
      }
      _client = PusherChannelsClient.websocket(
        options: PusherChannelsOptions.fromHost(
          scheme: 'ws',
          host: '10.0.2.2', // IP para emulador
          port: 8080,
          key: '06exymiubefjjglwmvqe',
        ),
        // ✅ Quitamos el authorizationDelegate de aquí (error línea 67)
        connectionErrorHandler: (exception, trace, client) =>
            debugPrint("❌ Error Socket: $exception"),
      );

      _client!.eventStream.listen((event) {
        debugPrint("DEBUG PUSHER: Evento -> ${event.name}");

        if (event.name == 'pusher:connection_established') {
          debugPrint("✅ Conectado. Suscribiendo...");

          // ✅ Lo ponemos AQUÍ (donde es obligatorio según el error de la línea 78)
          final myChannel = _client!.privateChannel(
            'private-conductor.$userId', // Nombre completo del canal
            authorizationDelegate: MyPusherAuth(token: token, dio: Dio()),
          );

          myChannel.subscribe();

          // Busca esta parte dentro de _initSocket en trip_repository_impl.dart
          _eventSubscription = myChannel.bind('nueva.asignacion').listen((e) {
            if (e.data != null) {
              try {
                final Map<String, dynamic> data = json.decode(e.data!);

                // Obtenemos el ID de la asignación
                final String assignmentId = data['asignacion']['id'].toString();

                // Obtenemos los datos del viaje
                final Map<String, dynamic> tripData =
                    data['asignacion']['viaje'];

                // 🔥 CAMBIO CLAVE: NO sobreescribas el ID del viaje.
                // Guarda el ID de asignación en otra llave para usarla al aceptar.
                tripData['assignment_id'] = assignmentId;

                controller.add(Trip.fromMap(tripData));
              } catch (ex) {
                debugPrint("❌ Error: $ex");
              }
            }
          });
          // 🔥 NUEVO: Escuchar si el viaje es cancelado mientras está en oferta o en curso
          // 🔥 MEJORADO: Ahora sí lee el ID real que manda el servidor
          myChannel.bind('ViajeCancelado').listen((e) {
            if (e.data != null) {
              try {
                final Map<String, dynamic> data = json.decode(e.data!);
                debugPrint("🚨 Cancelación para viaje ID: ${data['id']}");

                // Enviamos al controlador el ID real con estado CANCELLED
                controller.add(
                  Trip.fromMap({
                    'id': data['id'].toString(), // ID real del viaje cancelado
                    'estado': 'CANCELLED',
                    'mensaje': data['mensaje'] ?? 'El usuario canceló el viaje',
                  }),
                );
              } catch (ex) {
                debugPrint("❌ Error decodificando cancelación: $ex");
              }
            }
          });
        }
      });

      _client!.connect();
    } catch (e) {
      debugPrint("🚨 Error: $e");
    }
  }

  // Corregimos los avisos de las llaves {} en este método también
  @override
  Future<Trip> updateTripStatus(
    String tripId,
    String status, {
    double? lat,
    double? lng,
  }) async {
    String? subPath;

    // 🔥 NUEVA LÓGICA: Si es cancelar, usamos la ruta dedicada que creamos en Laravel
    if (status == 'CANCELLED') {
      final response = await _api.dio.post('/viajes/$tripId/cancelar');
      if (response.data['status'] == 'success') {
        return Trip.fromMap({'id': tripId, 'estado': 'CANCELLED'});
      }
      throw Exception("No se pudo cancelar en el servidor");
    }

    if (status == 'ARRIVED') {
      subPath = '/llegada';
    } else if (status == 'STARTED') {
      subPath = '/iniciar';
    } else if (status == 'DROPPED_OFF') {
      subPath = '/llegada-destino';
    }

    if (subPath == null) {
      // ✅ CORRECCIÓN: Eliminamos _activeTrip y devolvemos un objeto básico
      // Esto solo ocurre si se llama al método con un estado no soportado por esta función.
      return Trip.fromMap({'id': tripId, 'estado': status});
    }

    final response = await _api.dio.post(
      '/viajes/$tripId$subPath',
      data: {if (lat != null) 'lat': lat, if (lng != null) 'lng': lng},
    );

    if (response.data['viaje'] == null) {
      throw Exception("El servidor no devolvió los datos del viaje.");
    }

    return Trip.fromMap(response.data['viaje']);
  }

  @override
  Future<void> rejectTrip(String tripId) async => await _api.dio.post(
    '/asignaciones/$tripId/responder',
    data: {'respuesta': 'rechazar'},
  );

  @override
  Future<void> updateLocation(String tripId, double lat, double lng) async =>
      await _api.dio.post(
        '/viajes/$tripId/tracking',
        data: {'lat': lat, 'lng': lng},
      );

  @override
  Future<Trip> confirmCashPayment(String tripId, PaymentMethod method) async {
    // MAPEADOR: Traducimos el Enum de Flutter a lo que Laravel entiende
    String backendMethod = 'EFECTIVO';
    if (method == PaymentMethod.WOMPI || method == PaymentMethod.CREDIT_CARD) {
      backendMethod = 'TARJETA';
    } else if (method == PaymentMethod.WALLET) {
      backendMethod = 'CORPORATIVO';
    }
    // Nota: CASH, NEQUI y DAVIPLATA se reportan como 'EFECTIVO' porque el conductor recibió el valor físico.

    final response = await _api.dio.post(
      '/viajes/$tripId/finalizar',
      data: {'metodo_pago': backendMethod},
    );

    if (response.data['viaje'] != null) {
      return Trip.fromMap(response.data['viaje']);
    }
    throw Exception("No se pudo confirmar el pago en el servidor");
  }

  void dispose() {
    _eventSubscription?.cancel();
    _client?.disconnect();
    _fleetUpdateController.close();
    _walletUpdateController.close();
  }
}

// ESTA CLASE DEBE ESTAR EXACTAMENTE ASÍ PARA EVITAR ERRORES DE FIRMA
class MyPusherAuth
    implements
        EndpointAuthorizableChannelAuthorizationDelegate<
          PrivateChannelAuthorizationData
        > {
  final String token;
  final Dio dio;

  MyPusherAuth({required this.token, required this.dio});

  @override
  EndpointAuthFailedCallback? get onAuthFailed => (exception, trace) {
    debugPrint("❌ Error de Autenticación Pusher: $exception");
  };

  @override
  Future<PrivateChannelAuthorizationData> authorizationData(
    String socketId,
    String channelName,
  ) async {
    try {
      final response = await dio.post(
        'http://10.0.2.2:8000/api/broadcasting/auth',
        data: {'socket_id': socketId, 'channel_name': channelName},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );
      // Retornamos el formato que la librería espera
      return PrivateChannelAuthorizationData(
        authKey: response.data['auth'] ?? '',
      );
    } catch (e) {
      debugPrint("❌ Falló la petición de auth: $e");
      return const PrivateChannelAuthorizationData(authKey: '');
    }
  }
}

class MockTripRepository implements TripRepository {
  @override
  // ✅ ACTUALIZADO: Para que coincida con la interfaz
  Future<Trip> acceptTrip(String asignacionId, double lat, double lng) async =>
      throw UnimplementedError();

  @override
  Stream<Trip> listenForTrips() => const Stream.empty();
  @override
  Future<void> rejectTrip(String tripId) async {}
  @override
  Future<Trip> updateTripStatus(
    String tripId,
    String status, {
    double? lat,
    double? lng,
  }) async => throw UnimplementedError();
  @override
  Future<void> updateLocation(String tripId, double lat, double lng) async {}
  @override
  Future<Trip> confirmCashPayment(String tripId, PaymentMethod method) async {
    throw UnimplementedError();
  }

  @override
  Stream<void> listenForFleetChanges() => const Stream.empty();
  @override
  Stream<double> listenForWalletUpdates(String userId) => const Stream.empty();
}
