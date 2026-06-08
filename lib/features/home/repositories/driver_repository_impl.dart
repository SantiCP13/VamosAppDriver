// =========================================================================
// ARCHIVO: lib/features/home/repositories/driver_repository_impl.dart
// =========================================================================

// ignore_for_file: avoid_print, unused_import

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;
import 'dart:convert'; // Resuelve el error de 'jsonEncode'

import '../../../core/models/document_model.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../core/network/api_client.dart';
import 'driver_repository.dart'; // 🟢 Importa la interfaz del Paso 1
import 'dart:io';

// ==========================================
// API REPOSITORY (Conexión Real Laravel)
// ==========================================
class ApiDriverRepository implements DriverRepository {
  final ApiClient _apiClient = ApiClient();

  @override
  Future<List<DriverDocument>> getDocuments(String driverId) async {
    return [];
  }

  @override
  Future<List<Vehicle>> getAssignedVehicles(String driverId) async {
    try {
      final response = await _apiClient.dio.get('/me');
      final userData = response.data['data'];
      if (userData == null || userData['conductor'] == null) return [];
      final List vehiclesList = userData['conductor']['vehiculos'] ?? [];
      return vehiclesList.map((e) => Vehicle.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<bool> toggleStatus({
    required bool isOnline,
    required String driverId,
    String? vehicleId,
    double? lat,
    double? lng,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/conductor/estado',
        data: {
          'esta_online': isOnline,
          'id_vehiculo': vehicleId,
          'lat': lat,
          'lng': lng,
        },
      );
      return response.data['success'] == true ||
          response.data['status'] == 'success';
    } on DioException catch (e) {
      String msg =
          e.response?.data['message'] ?? "Error de conexión con el servidor";
      throw Exception(msg);
    } catch (e) {
      throw Exception("Error inesperado: $e");
    }
  }

  @override
  Future<void> updatePosition(double lat, double lng) async {
    try {
      await _apiClient.dio.post(
        '/conductor/ubicacion',
        data: {'lat': lat, 'lng': lng},
      );
    } catch (e) {
      developer.log("Error actualizando ubicación: $e", name: "GPS");
    }
  }

  // =========================================================================
  // IMPLEMENTACIÓN DE LOS NUEVOS ENDPOINTS DE TURNOS (MULTIPART CON IMÁGENES)
  // =========================================================================

  @override
  Future<Map<String, dynamic>> iniciarTurno({
    required String idVehiculo,
    required int kilometraje,
    required File foto,
    double? lat,
    double? lng,
  }) async {
    try {
      final formData = FormData.fromMap({
        'id_vehiculo': idVehiculo,
        'kilometraje_inicial': kilometraje,
        'lat': lat,
        'lng': lng,
        'foto_tablero_inicial': await MultipartFile.fromFile(
          foto.path,
          filename: 'tablero_inicial.jpg',
        ),
      });

      final response = await _apiClient.dio.post(
        '/conductor/turno/iniciar',
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['message'] ?? "Error al iniciar el turno.",
      );
    }
  }

  @override
  Future<Map<String, dynamic>> pausarTurno({double? lat, double? lng}) async {
    try {
      final response = await _apiClient.dio.post(
        '/conductor/turno/pausar',
        data: {'lat': lat, 'lng': lng},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['message'] ?? "Error al iniciar el break.",
      );
    }
  }

  @override
  Future<Map<String, dynamic>> reanudarTurno({double? lat, double? lng}) async {
    try {
      final response = await _apiClient.dio.post(
        '/conductor/turno/reanudar',
        data: {'lat': lat, 'lng': lng},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['message'] ?? "Error al reanudar el turno.",
      );
    }
  }

  @override
  Future<Map<String, dynamic>> iniciarAlmuerzo({
    double? lat,
    double? lng,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/conductor/turno/almuerzo/iniciar',
        data: {'lat': lat, 'lng': lng},
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['message'] ?? "Error al iniciar el almuerzo.",
      );
    }
  }

  @override
  Future<Map<String, dynamic>> obtenerTurnoActivo() async {
    try {
      final response = await _apiClient.dio.get('/conductor/turno/activo');
      return response.data;
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['message'] ??
            "Error al obtener el turno activo del servidor.",
      );
    }
  }

  @override
  Future<Map<String, dynamic>> terminarTurno({
    required int kilometraje,
    required File foto,
    double? lat,
    double? lng,
    List<File>? comprobantesFotos,
    List<double>? comprobantesValores,
  }) async {
    try {
      final Map<String, dynamic> dataMap = {
        'kilometraje_final': kilometraje,
        'lat': lat,
        'lng': lng,
        'foto_tablero_final': await MultipartFile.fromFile(
          foto.path,
          filename: 'tablero_final.jpg',
        ),
      };

      if (comprobantesFotos != null && comprobantesFotos.isNotEmpty) {
        final List<MultipartFile> multipartFileList = [];
        for (var file in comprobantesFotos) {
          multipartFileList.add(
            await MultipartFile.fromFile(
              file.path,
              filename:
                  'comprobante_${DateTime.now().millisecondsSinceEpoch}.jpg',
            ),
          );
        }
        dataMap['comprobantes_fotos[]'] = multipartFileList;
      }

      if (comprobantesValores != null && comprobantesValores.isNotEmpty) {
        dataMap['comprobantes_valores'] = jsonEncode(comprobantesValores);
      }

      final formData = FormData.fromMap(dataMap);

      final response = await _apiClient.dio.post(
        '/conductor/turno/terminar',
        data: formData,
      );
      return response.data;
    } on DioException catch (e) {
      throw Exception(
        e.response?.data['message'] ?? "Error al terminar el turno.",
      );
    }
  }
}
