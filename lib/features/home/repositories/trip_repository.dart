import '../../../core/models/trip_model.dart';

abstract class TripRepository {
  Stream<Trip> listenForTrips();
  // ✅ ACTUALIZADO: Ahora la interfaz exige 3 parámetros
  Future<Trip> acceptTrip(String asignacionId, double lat, double lng);
  Future<void> rejectTrip(String tripId);
  Future<Trip> updateTripStatus(String tripId, String status, {double? lat, double? lng});
  Future<void> updateLocation(String tripId, double lat, double lng);
  Stream<double> listenForWalletUpdates(String userId);
  Future<void> confirmCashPayment(String tripId);
  Stream<void> listenForFleetChanges();
}
