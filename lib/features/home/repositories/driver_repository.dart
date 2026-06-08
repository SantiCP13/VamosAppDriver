// =========================================================================
// ARCHIVO: lib/features/home/repositories/driver_repository.dart
// =========================================================================
import 'dart:io';
import '../../../core/models/document_model.dart';
import '../../../core/models/vehicle_model.dart';

abstract class DriverRepository {
  Future<List<DriverDocument>> getDocuments(String driverId);
  Future<List<Vehicle>> getAssignedVehicles(String driverId);

  // Métodos de compatibilidad
  Future<bool> toggleStatus({
    required bool isOnline,
    required String driverId,
    String? vehicleId,
    double? lat,
    double? lng,
  });
  Future<void> updatePosition(double lat, double lng);

  // --- ACCIONES DEL TURNO EN 3 ESTADOS ---
  Future<Map<String, dynamic>> iniciarTurno({
    required String idVehiculo,
    required int kilometraje,
    required File foto,
    double? lat,
    double? lng,
  });
  Future<Map<String, dynamic>> obtenerTurnoActivo();
  Future<Map<String, dynamic>> pausarTurno({double? lat, double? lng});

  Future<Map<String, dynamic>> reanudarTurno({double? lat, double? lng});

  // 🟢 NUEVO: Firma para iniciar el almuerzo
  Future<Map<String, dynamic>> iniciarAlmuerzo({double? lat, double? lng});

  // 🟢 CORREGIDO: Firma de terminarTurno con los nuevos parámetros opcionales
  Future<Map<String, dynamic>> terminarTurno({
    required int kilometraje,
    required File foto,
    double? lat,
    double? lng,
    List<File>? comprobantesFotos,
    List<double>? comprobantesValores,
  });
}
