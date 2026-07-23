// ignore_for_file: use_null_aware_elements

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:dio/dio.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/models/trip_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import 'trip_repository.dart';
import '../../../core/enums/payment_enums.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
      data: {'respuesta': 'aceptar', 'lat': lat, 'lng': lng},
    );

    if (response.data['viaje'] != null) {
      return Trip.fromMap(response.data['viaje']);
    }
    throw Exception("No se recibió el viaje");
  }

  @override
  Future<String> checkAssignmentStatus(String assignmentId) async {
    try {
      final response = await _api.dio.get(
        '/viajes/verificar-asignacion/$assignmentId',
      );
      return response.data['status']
          .toString(); // Retornará 'ACTIVE' o 'CANCELLED'
    } catch (e) {
      return 'CANCELLED'; // Si falla, asumimos que ya no sirve
    }
  }

  @override
  Future<Trip?> getActiveTrip() async {
    try {
      final response = await _api.dio.get('/conductor/viaje-activo');
      if (response.data['data'] != null) {
        return Trip.fromMap(response.data['data']);
      }
    } catch (e) {
      debugPrint("No hay viaje activo o error: $e");
    }
    return null;
  }

  @override
  Stream<Trip> listenForTrips() {
    final user = sl<AuthProvider>().user;
    if (user == null) return const Stream.empty();

    final String idParaSocket = user.id.toString();
    debugPrint("🚨 ID REAL PARA SOCKET: $idParaSocket");

    final controller = StreamController<Trip>();
    _initSocket(controller, idParaSocket, sl<StorageService>());
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

      final String host = dotenv.env['REVERB_HOST'] ?? 'api.vamosapp.com.co';
      final String key = dotenv.env['REVERB_KEY'] ?? '06exymiubefjjglwmvqe';

      final int port = 443;
      final String scheme = 'wss';

      debugPrint("🚀 Conectando a $scheme://$host:$port con key: $key");

      _client = PusherChannelsClient.websocket(
        options: PusherChannelsOptions.fromHost(
          scheme: scheme,
          host: host,
          port: port,
          key: key,
        ),
        connectionErrorHandler: (exception, trace, client) =>
            debugPrint("❌ Error Socket: $exception"),
      );

      _client!.eventStream.listen((event) {
        if (event.name == 'pusher:connection_established') {
          debugPrint("✅ Conectado al Socket. Configurando canal...");

          final myChannel = _client!.privateChannel(
            'private-conductor.$userId',
            authorizationDelegate: MyPusherAuth(token: token, dio: Dio()),
          );

          // 🔥 LÓGICA BLINDADA DE DECODIFICACIÓN
          void procesarNuevaAsignacion(dynamic e) {
            debugPrint("🚨 [PASO 1] EVENTO RECIBIDO EN FLUTTER. Procesando...");
            if (e.data != null) {
              try {
                // 1. Parseo seguro de String a Mapa
                Map<String, dynamic> rawData;
                if (e.data is String) {
                  rawData = json.decode(e.data!);
                } else {
                  rawData = Map<String, dynamic>.from(e.data);
                }

                // 2. Extracción de Asignación y Viaje
                final Map<String, dynamic> data =
                    rawData.containsKey('asignacion')
                    ? Map<String, dynamic>.from(rawData['asignacion'])
                    : rawData;

                final String assignmentId = data['id'].toString();
                final Map<String, dynamic> tripData = Map<String, dynamic>.from(
                  data['viaje'],
                );
                tripData['assignment_id'] = assignmentId;

                debugPrint(
                  "✅ [PASO 2] Viaje Extraído. Ajustando tipos de datos...",
                );

                // 3. ESCUDO PROTECTOR (Evita crash de Int vs Double)
                if (tripData['precio_estimado'] is int) {
                  tripData['precio_estimado'] =
                      (tripData['precio_estimado'] as int).toDouble();
                }
                if (tripData['lat_origen'] is int) {
                  tripData['lat_origen'] = (tripData['lat_origen'] as int)
                      .toDouble();
                }
                if (tripData['lng_origen'] is int) {
                  tripData['lng_origen'] = (tripData['lng_origen'] as int)
                      .toDouble();
                }
                if (tripData['lat_destino'] is int) {
                  tripData['lat_destino'] = (tripData['lat_destino'] as int)
                      .toDouble();
                }
                if (tripData['lng_destino'] is int) {
                  tripData['lng_destino'] = (tripData['lng_destino'] as int)
                      .toDouble();
                }

                // 4. Inyección de valores requeridos que el Backend no mandó
                if (!tripData.containsKey('estado') &&
                    !tripData.containsKey('status')) {
                  tripData['estado'] = 'PENDING';
                }

                debugPrint(
                  "✅ [PASO 3] Tipos ajustados. Convirtiendo a TripModel...",
                );

                // 5. Conversión Final
                final Trip newTrip = Trip.fromMap(tripData);

                debugPrint(
                  "✅ [PASO 4] Modelo Creado Correctamente (Viaje ID: ${newTrip.id}). Notificando al Provider...",
                );

                controller.add(newTrip);

                debugPrint(
                  "🚀 [PASO 5] ¡ORDEN ENVIADA CON ÉXITO! El Modal debería aparecer ahora.",
                );
              } catch (ex, stacktrace) {
                // Ahora si explota, nos dirá la línea exacta del error
                debugPrint("❌ CRÍTICO: Error decodificando el modelo: $ex");
                debugPrint("❌ Stacktrace: $stacktrace");
              }
            }
          }
          // En ApiTripRepository.dart, dentro de _initSocket:

          void procesarNoDisponible(dynamic e) {
            if (e.data != null) {
              try {
                final Map<String, dynamic> data = e.data is String
                    ? json.decode(e.data!)
                    : Map<String, dynamic>.from(e.data);

                final String idViajeNoDisponible =
                    (data['viaje_id'] ?? data['id']).toString();

                debugPrint(
                  "🚨 [SOCKET] VIAJE YA NO DISPONIBLE: $idViajeNoDisponible. Cerrando alerta...",
                );

                // Enviamos un objeto con estado 'NO_DISPONIBLE' para que el Provider cierre el modal
                controller.add(
                  Trip.fromMap({
                    'id': idViajeNoDisponible,
                    'estado': 'NO_DISPONIBLE',
                  }),
                );
              } catch (ex) {
                debugPrint("❌ Error procesando ViajeNoDisponible: $ex");
              }
            }
          }

          // En ApiTripRepository.dart, dentro de procesarCancelacion:
          void procesarCancelacion(dynamic e) {
            if (e.data != null) {
              try {
                final Map<String, dynamic> data = e.data is String
                    ? json.decode(e.data!)
                    : Map<String, dynamic>.from(e.data);

                final String idCancelado = (data['viaje_id'] ?? data['id'])
                    .toString();

                debugPrint(
                  "🚨[SOCKET] FORZANDO ELIMINACIÓN DE VIAJE: $idCancelado",
                );

                // Enviamos un objeto que fuerce al HomeProvider a ejecutar _finishTrip()
                controller.add(
                  Trip.fromMap({
                    'id': idCancelado,
                    'estado':
                        'CANCELLED', // O 'status' dependiendo de tu modelo
                    'status': 'CANCELLED',
                    'mensaje': 'Viaje cancelado por el usuario',
                  }),
                );
              } catch (ex) {
                debugPrint("❌ Error procesando cancelación: $ex");
              }
            }
          }

          // 🟢 NUEVO PROCESADOR PARA VIAJE ESTADO
          void procesarViajeEstado(dynamic e) {
            debugPrint(
              "🚨 [SOCKET] ESTADO DE VIAJE RECIBIDO EN CONDUCTOR: ${e.data}",
            );
            if (e.data != null) {
              try {
                final Map<String, dynamic> rawData = e.data is String
                    ? json.decode(e.data!)
                    : Map<String, dynamic>.from(e.data);

                final Map<String, dynamic> viajeData =
                    rawData.containsKey('viaje')
                    ? Map<String, dynamic>.from(rawData['viaje'])
                    : rawData;

                // Asegurar compatibilidad de campos requeridos
                if (rawData.containsKey('estado') &&
                    !viajeData.containsKey('estado')) {
                  viajeData['estado'] = rawData['estado'];
                }

                // Ajustes de tipos double por seguridad
                if (viajeData['precio_estimado'] is int) {
                  viajeData['precio_estimado'] =
                      (viajeData['precio_estimado'] as int).toDouble();
                }

                final Trip updatedTrip = Trip.fromMap(viajeData);
                controller.add(updatedTrip);
              } catch (ex, stacktrace) {
                debugPrint("❌ Error procesando ViajeEstado en conductor: $ex");
                debugPrint("❌ Stacktrace: $stacktrace");
              }
            }
          }

          myChannel.bind('nueva.asignacion').listen(procesarNuevaAsignacion);
          myChannel.bind('.nueva.asignacion').listen(procesarNuevaAsignacion);
          myChannel
              .bind('App\\Events\\NuevaAsignacion')
              .listen(procesarNuevaAsignacion);
          // 🟢 NUEVOS BINDS PARA ESCUCHAR ESTADOS DE VIAJE (COMO PROPUESTAS DE RUTA EN CURSO)
          myChannel.bind('ViajeEstado').listen(procesarViajeEstado);
          myChannel.bind('.ViajeEstado').listen(procesarViajeEstado);
          myChannel
              .bind('App\\Events\\ViajeEstadoEvent')
              .listen(procesarViajeEstado);
          myChannel.bind('ViajeCancelado').listen(procesarCancelacion);
          myChannel.bind('.ViajeCancelado').listen(procesarCancelacion);
          myChannel
              .bind('App\\Events\\ViajeCancelado')
              .listen(procesarCancelacion);
          // Busca donde tienes los otros bind (al final de la configuración del socket)
          myChannel.bind('ViajeNoDisponible').listen(procesarNoDisponible);
          myChannel.bind('.ViajeNoDisponible').listen(procesarNoDisponible);
          myChannel
              .bind('App\\Events\\ViajeNoDisponibleEvent')
              .listen(procesarNoDisponible);
          myChannel.subscribe();
          debugPrint(
            "✅ Suscripción enviada al canal: private-conductor.$userId",
          );
        }
      });

      _client!.connect();
    } catch (e) {
      debugPrint("🚨 Error en _initSocket: $e");
    }
  }

  @override
  Future<Trip> updateTripStatus(
    String tripId,
    String status, {
    double? lat,
    double? lng,
  }) async {
    String? subPath;
    if (status == 'CANCELLED') {
      final response = await _api.dio.post('/viajes/$tripId/cancelar');
      if (response.data['status'] == 'success') {
        return Trip.fromMap({'id': tripId, 'estado': 'CANCELLED'});
      }
      throw Exception("No se pudo cancelar en el servidor");
    }

    if (status == 'ARRIVED') {
      subPath = '/llegada';
    } else if (status == 'STARTED')
      // ignore: curly_braces_in_flow_control_structures
      subPath = '/iniciar';
    else if (status == 'DROPPED_OFF')
      // ignore: curly_braces_in_flow_control_structures
      subPath = '/llegada-destino';

    if (subPath == null) return Trip.fromMap({'id': tripId, 'estado': status});

    final response = await _api.dio.post(
      '/viajes/$tripId$subPath',
      data: {if (lat != null) 'lat': lat, if (lng != null) 'lng': lng},
    );

    if (response.data['viaje'] == null) throw Exception("Error del servidor.");
    return Trip.fromMap(response.data['viaje']);
  }

  @override
  Future<void> rejectTrip(String tripId) async {
    try {
      await _api.dio.post(
        '/asignaciones/$tripId/responder',
        data: {'respuesta': 'rechazar'},
      );
    } on DioException catch (e) {
      // SOLO registramos el error, NO lanzamos un throw.
      // Esto evita que el Provider se rompa y que el ApiClient reaccione mal.
      debugPrint(
        "🚨 [REPOSITORY] El rechazo retornó estado: ${e.response?.statusCode}",
      );
    } catch (e) {
      debugPrint("🚨 [REPOSITORY] Error inesperado al rechazar: $e");
    }
  }

  @override
  Future<void> updateLocation(
    String tripId,
    double lat,
    double lng, {
    double? speed,
    double? bearing,
  }) async => await _api.dio.post(
    '/viajes/$tripId/tracking',
    data: {
      'lat': lat,
      'lng': lng,
      if (speed != null) 'velocidad': speed,
      if (bearing != null) 'bearing': bearing,
    },
  );
  @override
  Future<Trip> confirmCashPayment(String tripId, PaymentMethod method) async {
    String backendMethod = 'EFECTIVO';
    if (method == PaymentMethod.WOMPI || method == PaymentMethod.CREDIT_CARD) {
      backendMethod = 'TARJETA';
    } else if (method == PaymentMethod.WALLET)
      // ignore: curly_braces_in_flow_control_structures
      backendMethod = 'CORPORATIVO';

    final response = await _api.dio.post(
      '/viajes/$tripId/finalizar',
      data: {'metodo_pago': backendMethod},
    );

    if (response.data['viaje'] != null) {
      return Trip.fromMap(response.data['viaje']);
    }
    throw Exception("No se pudo confirmar el pago.");
  }

  void dispose() {
    _eventSubscription?.cancel();
    _client?.disconnect();
    _fleetUpdateController.close();
    _walletUpdateController.close();
  }
}

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
      final String apiUrl =
          dotenv.env['API_URL'] ?? 'https://api.vamosapp.com.co/api';

      final response = await dio.post(
        '$apiUrl/broadcasting/auth', // Construcción dinámica
        data: {'socket_id': socketId, 'channel_name': channelName},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );
      return PrivateChannelAuthorizationData(
        authKey: response.data['auth'] ?? '',
      );
    } catch (e) {
      debugPrint("❌ Falló la petición de auth: $e");
      return const PrivateChannelAuthorizationData(authKey: '');
    }
  }
}
