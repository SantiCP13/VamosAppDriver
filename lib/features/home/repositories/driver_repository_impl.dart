// ignore_for_file: avoid_print, unused_import

import 'dart:async';
import 'package:dio/dio.dart'; // <--- IMPORTANTE: Esto quita el error de DioException
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

import '../../../core/models/document_model.dart';
import '../../../core/models/vehicle_model.dart';
import '../../../core/network/api_client.dart';
import 'driver_repository.dart';

// ==========================================
// 1. MOCK REPOSITORY (Para pruebas)
// ==========================================
class MockDriverRepository implements DriverRepository {
  @override
  Future<List<DriverDocument>> getDocuments(String driverId) async => [];

  @override
  Future<List<Vehicle>> getAssignedVehicles(String driverId) async =>
      Vehicle.getMocks();

  @override
  Future<bool> toggleStatus({
    required bool isOnline,
    required String driverId,
    String? vehicleId,
    double? lat,
    double? lng,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return true;
  }

  @override
  Future<void> updatePosition(double lat, double lng) async {}
}

// ==========================================
// 2. API REPOSITORY (Conexión Real Laravel)
// ==========================================
class ApiDriverRepository implements DriverRepository {
  final ApiClient _apiClient = ApiClient();

  @override
  Future<List<DriverDocument>> getDocuments(String driverId) async {
    // Implementación pendiente si el backend tiene un endpoint de docs
    return [];
  }

  @override
  Future<List<Vehicle>> getAssignedVehicles(String driverId) async {
    try {
      final response = await _apiClient.dio.get('/me');

      // ESTA LÍNEA ES PARA DEBUG:
      print("RESPUESTA BACKEND: ${response.data}");

      final userData = response.data['data'];
      if (userData == null || userData['conductor'] == null) {
        print("No se encontró objeto conductor en el JSON");
        return [];
      }

      final List vehiclesList = userData['conductor']['vehiculos'] ?? [];
      print("CANTIDAD DE VEHÍCULOS ENCONTRADOS: ${vehiclesList.length}");

      return vehiclesList.map((e) => Vehicle.fromJson(e)).toList();
    } catch (e) {
      print("ERROR EN REPOSITORIO: $e");
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
      // Laravel suele devolver success: true o status: 'success'
      return response.data['success'] == true ||
          response.data['status'] == 'success';
    } on DioException catch (e) {
      // Capturamos errores 403, 401 o validaciones del Backend
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
}
