import '../../../core/models/document_model.dart';

abstract class DriverRepository {
  /// Obtiene la lista de documentos (SOAT, Tecno, etc.)
  Future<List<DriverDocument>> getDocuments(String driverId);

  /// Intenta cambiar el estado.
  /// Lanza una Exception si el conductor no cumple los requisitos.
  Future<bool> toggleStatus({required bool isOnline, required String driverId});
}
