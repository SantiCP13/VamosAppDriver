import 'dart:async';
import 'package:flutter/foundation.dart'; // Para usar debugPrint
import '../../../core/models/trip_model.dart';
import '../../../core/network/api_client.dart'; // Si lo usas en la parte Real
import 'trip_repository.dart';

// --- MOCK ---
class MockTripRepository implements TripRepository {
  final _streamController = StreamController<Trip>.broadcast();

  MockTripRepository() {
    // CAMBIO: Usamos periodic en lugar de Timer único
    // Enviará una oferta de viaje cada 10 segundos
    Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_streamController.isClosed) {
        debugPrint(
          "📦 [MOCK] Enviando solicitud de viaje entrante...",
        ); // LOG CLAVE
        _streamController.add(Trip.mock());
      }
    });
  }

  @override
  Stream<Trip> listenForTrips() {
    return _streamController.stream;
  }

  @override
  Future<Trip> acceptTrip(String tripId) async {
    await Future.delayed(const Duration(seconds: 1));

    // Al aceptar, simulamos que el Backend genera el FUEC
    // Retornamos un viaje con el snapshot_legal lleno
    final trip = Trip.mock();
    return trip.copyWith(
      status: TripStatus.ACCEPTED,
      legalSnapshot: {
        "fuec_number": "35002026001",
        "generated_at": DateTime.now().toIso8601String(),
        "contract": "CONTRATO_MARCO_2026",
        "driver": "Pepito Pérez",
        "vehicle": "Renault Kwid - AAA123",
      },
    );
  }

  @override
  Future<void> rejectTrip(String tripId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    debugPrint("🗑️ Viaje $tripId rechazado en Mock"); // Usar debugPrint
  }

  @override
  Future<Trip> updateTripStatus(String tripId, String status) async {
    await Future.delayed(const Duration(seconds: 1));
    // En un caso real, esto actualizaría el estado en el backend
    return Trip.mock().copyWith(status: TripStatus.values.byName(status));
  }
}

// --- REAL (LARAVEL) ---
class ApiTripRepository implements TripRepository {
  final ApiClient _apiClient = ApiClient();

  @override
  Stream<Trip> listenForTrips() async* {
    // AQUÍ CONECTAREMOS WEBSOCKETS (Pusher/Laravel Echo) MÁS ADELANTE
    // Por ahora, usaremos Polling simple (consultar cada 10s)
    while (true) {
      await Future.delayed(const Duration(seconds: 10));
      try {
        final response = await _apiClient.dio.get('/trips/available');
        if (response.data['data'] != null) {
          yield Trip.fromMap(response.data['data']);
        }
      } catch (e) {
        // Ignorar errores de red en polling para no romper el stream
      }
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
    return Trip.fromMap(response.data['data']);
  }
}
