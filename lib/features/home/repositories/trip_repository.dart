import '../../../core/models/trip_model.dart';

abstract class TripRepository {
  /// Escucha ofertas de viajes en tiempo real (Socket o Polling)
  Stream<Trip> listenForTrips();

  /// Acepta un viaje y retorna el Trip actualizado con el FUEC (snapshot_legal)
  Future<Trip> acceptTrip(String tripId);

  /// Rechaza un viaje
  Future<void> rejectTrip(String tripId);

  /// Actualiza el estado del viaje (En sitio, Iniciado, Finalizado)
  Future<Trip> updateTripStatus(String tripId, String status);

  /// Confirma al backend que el conductor ya recibió el dinero en efectivo/transferencia manual
  Future<void> confirmCashPayment(String tripId);

  /// Envía la ubicación actual al backend para el Tracking del pasajero
  Future<void> updateLocation(String tripId, double lat, double lng);
}
