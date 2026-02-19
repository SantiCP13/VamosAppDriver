import 'dart:async';
import 'package:flutter/foundation.dart'; // Para usar debugPrint
import '../../../core/models/trip_model.dart';
import '../../../core/network/api_client.dart'; // Si lo usas en la parte Real
import 'trip_repository.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import '../../../core/enums/payment_enums.dart';

// --- MOCK ---
// --- MOCK ---
class MockTripRepository implements TripRepository {
  final _streamController = StreamController<Trip>.broadcast();

  // NUEVO: Guardamos el viaje actual en memoria para que no pierda
  // su método de pago (Efectivo/Nequi) cuando cambie de estado.
  Trip? _currentMockTrip;

  MockTripRepository() {
    // Genera una solicitud cada 10 seg
    Timer.periodic(const Duration(seconds: 10), (timer) {
      // FIX CLAVE: Solo enviamos ofertas si el conductor ESTÁ ONLINE (hasListener)
      // y si no hay ya un viaje en pantalla esperando ser aceptado (_currentMockTrip == null).
      if (!_streamController.isClosed &&
          _streamController.hasListener &&
          _currentMockTrip == null) {
        debugPrint("📦 Enviando solicitud de viaje entrante...");

        final methods = PaymentMethod.values;
        final random = Random();
        final randomMethod = methods[random.nextInt(methods.length)];

        _currentMockTrip = Trip.mock().copyWith(
          price: 15000.0,
          originAddress: "Parque de la 93",
          destinationAddress: "Centro Comercial Andino",
          paymentMethod: randomMethod,
        );

        _streamController.add(_currentMockTrip!);
      }
    });
  }
  @override
  Future<void> confirmCashPayment(String tripId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint("✅ Cobro manual confirmado en MOCK");
  }

  @override
  Future<void> updateLocation(String tripId, double lat, double lng) async {}
  @override
  Stream<Trip> listenForTrips() {
    return _streamController.stream;
  }

  @override
  Future<Trip> acceptTrip(String tripId) async {
    await Future.delayed(const Duration(seconds: 1));
    debugPrint("✅ Aceptando viaje $tripId y generando FUEC...");

    // AL ACEPTAR, actualizamos el viaje que ya tenemos en memoria (no creamos uno nuevo)
    // Así conservamos el método de pago original
    _currentMockTrip = (_currentMockTrip ?? Trip.mock()).copyWith(
      id: tripId,
      status: TripStatus.ACCEPTED,
      price: 20000.0,
      originLocation: const LatLng(4.6768, -74.0483),
      destinationLocation: const LatLng(4.6668, -74.0526),
      legalSnapshot: {
        "fuec_number": "35002026001",
        "generated_at": DateTime.now().toIso8601String(),
        "contract": "CONTRATO_MARCO_2026",
        "driver": "Pepito Pérez",
        "vehicle": "Renault Kwid - AAA123",
      },
    );

    return _currentMockTrip!;
  }

  @override
  Future<void> rejectTrip(String tripId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint("🗑️ Viaje $tripId rechazado");
    _currentMockTrip = null; // Liberamos memoria
  }

  @override
  Future<Trip> updateTripStatus(String tripId, String status) async {
    await Future.delayed(const Duration(seconds: 1));

    final newStatus = TripStatus.values.byName(status);

    double calculatedRevenue = 0.0;
    double calculatedFee = 0.0;

    // Asegurarnos de tener un viaje en memoria
    _currentMockTrip ??= Trip.mock().copyWith(id: tripId, price: 20000.0);

    if (newStatus == TripStatus.COMPLETED) {
      // AQUÍ simulamos el Ledger de Laravel: 15% comisión
      calculatedFee = _currentMockTrip!.price * 0.15;
      calculatedRevenue = _currentMockTrip!.price - calculatedFee;
    }

    // Actualizamos el estado y los valores financieros en el viaje de memoria
    _currentMockTrip = _currentMockTrip!.copyWith(
      status: newStatus,
      driverRevenue: calculatedRevenue,
      platformFee: calculatedFee,
    );

    // Si el viaje termina, guardamos el resultado final y limpiamos la memoria
    // para que empiecen a llegar nuevas ofertas.
    if (newStatus == TripStatus.COMPLETED ||
        newStatus == TripStatus.CANCELLED) {
      final finalResult = _currentMockTrip!;
      _currentMockTrip = null;
      return finalResult;
    }

    return _currentMockTrip!;
  }
}

// --- REAL (LARAVEL) ---
class ApiTripRepository implements TripRepository {
  final ApiClient _apiClient = ApiClient();

  // NUEVAS VARIABLES PARA EL POLLING CONTROLADO
  final StreamController<Trip> _tripStreamController =
      StreamController<Trip>.broadcast();
  Timer? _pollingTimer;

  @override
  Stream<Trip> listenForTrips() {
    // Apagamos cualquier polling anterior
    _pollingTimer?.cancel();

    // Polling optimizado cada 30 segundos (No bloquea el hilo principal)
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        final response = await _apiClient.dio.get('/trips/available');
        if (response.data != null) {
          _tripStreamController.add(Trip.fromMap(response.data));
        }
      } catch (e) {
        // Ignorar errores de red silenciosamente
      }
    });

    return _tripStreamController.stream;
  }

  @override
  Future<void> confirmCashPayment(String tripId) async {
    await _apiClient.dio.post('/trips/$tripId/confirm-cash');
  }

  @override
  Future<void> updateLocation(String tripId, double lat, double lng) async {
    try {
      await _apiClient.dio.post(
        '/trips/$tripId/location',
        data: {'lat': lat, 'lng': lng},
      );
    } catch (e) {
      // Ignorar errores menores de tracking
    }
  }

  @override
  Future<Trip> acceptTrip(String tripId) async {
    final response = await _apiClient.dio.post('/trips/$tripId/accept');
    // El backend debe retornar el viaje actualizado CON el snapshot_legal
    return Trip.fromMap(response.data['data']);
  }

  @override
  Future<void> rejectTrip(String tripId) async {
    await _apiClient.dio.post('/trips/$tripId/reject');
  }

  @override
  Future<Trip> updateTripStatus(String tripId, String status) async {
    final response = await _apiClient.dio.patch(
      '/trips/$tripId/status',
      data: {'status': status},
    );
    // Laravel debe retornar el objeto Trip con 'ganancia_conductor' calculado
    return Trip.fromMap(response.data['data']);
  }
}
