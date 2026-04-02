import '../../../../core/models/trip_model.dart'; // Corregido: 4 niveles hacia atrás

abstract class HistoryRepository {
  /// Obtiene los viajes finalizados por el conductor con su ganancia
  Future<List<Trip>> getTripHistory(); // Cambiado de TripModel a Trip
}
