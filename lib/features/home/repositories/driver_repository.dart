import '../../../core/models/document_model.dart';
import '../../../core/models/vehicle_model.dart';

abstract class DriverRepository {
  Future<List<DriverDocument>> getDocuments(String driverId);
  Future<List<Vehicle>> getAssignedVehicles(String driverId);

  // Agregamos lat y lng aquí para que coincida con el backend
  Future<bool> toggleStatus({
    required bool isOnline,
    required String driverId,
    String? vehicleId,
    double? lat,
    double? lng,
  });

  // Este es el método que faltaba implementar
  Future<void> updatePosition(double lat, double lng);
}
