import '../../../core/models/document_model.dart';
import '../../../core/models/vehicle_model.dart'; // <--- Importar

abstract class DriverRepository {
  /// Obtiene la lista de documentos (SOAT, Tecno, etc.)
  Future<List<DriverDocument>> getDocuments(String driverId);

  /// NUEVO: Obtiene los vehículos asignados al conductor
  Future<List<Vehicle>> getAssignedVehicles(String driverId);

  /// ACTUALIZADO: toggleStatus ahora requiere vehicleId si se va a poner ONLINE
  Future<bool> toggleStatus({
    required bool isOnline,
    required String driverId,
    String? vehicleId, // <--- Dato obligatorio para generar FUEC
  });
}
