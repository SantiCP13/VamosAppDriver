import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dart_pusher_channels/dart_pusher_channels.dart'; // <--- NUEVA LIBRERÍA
import '../../../core/enums/payment_enums.dart';

class PaymentSocketService {
  // 🚩 SWITCH: Cambia a 'false' cuando el backend en Laravel esté listo.
  static const bool useMock = true;

  final _paymentController = StreamController<PaymentStatus>.broadcast();
  Stream<PaymentStatus> get paymentStream => _paymentController.stream;

  PusherChannelsClient? _client;
  StreamSubscription? _subscription;

  Future<void> connectToTripPayment(String tripId, {String? methodName}) async {
    if (useMock) {
      _simulateWaitingForPayment(tripId, methodName ?? "Digital");
      return;
    }

    // =========================================================
    // LÓGICA REAL PARA LARAVEL (PURO DART)
    // =========================================================
    try {
      final options = PusherChannelsOptions.fromHost(
        scheme: 'ws',
        host: '10.0.2.2',
        port: 8080,
        key: '06exymiubefjjglwmvqe',
      );

      // 🔥 CORRECCIÓN: Se añade el manejador de errores obligatorio
      _client = PusherChannelsClient.websocket(
        options: options,
        connectionErrorHandler: (exception, trace, client) {
          debugPrint("❌ SOCKET PAGO Error: $exception");
        },
      );

      final channel = _client!.publicChannel("trip.$tripId");

      _subscription = channel.bind("PaymentApprovedEvent").listen((event) {
        debugPrint("✅ SOCKET REAL: ¡Pago confirmado!");
        _paymentController.add(PaymentStatus.APPROVED);
      });

      _client!.connect();
      debugPrint("🔌 SOCKET: Escuchando pago de viaje $tripId...");
    } catch (e) {
      debugPrint("❌ SOCKET Error: $e");
    }
  }

  void _simulateWaitingForPayment(String tripId, String methodName) {
    debugPrint("🛠️ MOCK SOCKET: Simulando conexión al viaje $tripId...");
    Future.delayed(const Duration(seconds: 4), () {
      debugPrint("✅ MOCK SOCKET: ¡Pago aprobado!");
      if (!_paymentController.isClosed) {
        _paymentController.add(PaymentStatus.APPROVED);
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    _client?.disconnect();
    _paymentController.close();
  }
}
