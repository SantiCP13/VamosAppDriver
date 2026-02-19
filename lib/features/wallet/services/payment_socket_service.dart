import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import '../../../core/enums/payment_enums.dart';

class PaymentSocketService {
  // 🚩 SWITCH: Cambia a 'false' cuando el backend en Laravel esté listo.
  static const bool useMock = true;

  final _paymentController = StreamController<PaymentStatus>.broadcast();
  Stream<PaymentStatus> get paymentStream => _paymentController.stream;

  PusherChannelsFlutter? _pusher;
  String? _currentChannel;

  /// Método principal: Decide si usar simulación o conexión real
  Future<void> connectToTripPayment(String tripId, {String? methodName}) async {
    if (useMock) {
      _simulateWaitingForPayment(tripId, methodName ?? "Digital");
      return;
    }

    // =========================================================
    // LÓGICA REAL PARA LARAVEL (PUSHER / REVERB)
    // =========================================================
    try {
      _currentChannel = "trip.$tripId";
      _pusher = PusherChannelsFlutter.getInstance();

      debugPrint(
        "🔌 SOCKET: Iniciando conexión a Pusher/Reverb para viaje $tripId...",
      );

      await _pusher!.init(
        apiKey: "TU_PUSHER_APP_KEY", // Te lo dará el Backend (del archivo .env)
        cluster: "TU_PUSHER_CLUSTER", // Te lo dará el Backend
        // authEndpoint: "https://tu-api.com/api/broadcasting/auth", // Si usan canales privados
        onConnectionStateChange: (currentState, previousState) {
          debugPrint("🔄 SOCKET Estado: $currentState");
        },
        onError: (message, code, error) {
          debugPrint("❌ SOCKET Error: $message");
        },
        onEvent: (event) {
          debugPrint("🔔 SOCKET Evento recibido: ${event.eventName}");

          // Escuchamos el evento de Laravel
          if (event.eventName == "PaymentApprovedEvent" ||
              event.eventName == "App\\Events\\PaymentApprovedEvent") {
            debugPrint("✅ SOCKET REAL: ¡Pago confirmado por el backend!");
            _paymentController.add(PaymentStatus.APPROVED);
          }
        },
      );

      await _pusher!.subscribe(channelName: _currentChannel!);
      await _pusher!.connect();
      debugPrint(
        "✅ SOCKET: Suscrito y escuchando en el canal $_currentChannel",
      );
    } catch (e) {
      debugPrint("❌ SOCKET Error de inicialización: $e");
    }
  }

  // =========================================================
  // LÓGICA MOCK (SIMULACIÓN PARA DESARROLLO)
  // =========================================================
  void _simulateWaitingForPayment(String tripId, String methodName) {
    // <--- Recibe el método
    debugPrint("🛠️ MOCK SOCKET: Simulando conexión al viaje $tripId...");
    debugPrint(
      "⏳ MOCK SOCKET: Esperando 4 segundos para aprobar pago vía...",
    ); // <--- LOG MEJORADO

    Future.delayed(const Duration(seconds: 4), () {
      debugPrint(
        "✅ MOCK SOCKET: ¡Evento PAYMENT_APPROVED simulado para $methodName!",
      );
      if (!_paymentController.isClosed) {
        _paymentController.add(PaymentStatus.APPROVED);
      }
    });
  }

  void dispose() async {
    if (!useMock && _pusher != null && _currentChannel != null) {
      await _pusher!.unsubscribe(channelName: _currentChannel!);
      await _pusher!.disconnect();
    }
    _paymentController.close();
  }
}
