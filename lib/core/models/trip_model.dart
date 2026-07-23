// lib/core/models/trip_model.dart

// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../enums/payment_enums.dart';

enum TripStatus {
  PENDING,
  REQUESTED,
  ACCEPTED,
  ARRIVED,
  STARTED,
  DROPPED_OFF,
  PAYMENT_PENDING,
  COMPLETED,
  CANCELLED,
  SCHEDULED_ASSIGNED,
  ROUTE_CHANGE_PROPOSED,
  SCHEDULED_LATE_ALERT, // 🟢 NUEVA LÍNEA: Estado para la alerta de retraso de viajes programados
}

class Passenger {
  final String name;
  final String nationalId;
  final String documentType;
  final String? phone;

  Passenger({
    required this.name,
    required this.nationalId,
    this.documentType = 'CC',
    this.phone,
  });

  Map<String, dynamic> toJson() => {
    'nombre_completo': name,
    'numero_documento': nationalId,
    'tipo_documento': documentType,
    'phone': phone,
  };

  factory Passenger.fromJson(Map<String, dynamic> json) {
    return Passenger(
      name: json['nombre_completo'] ?? json['name'] ?? 'Pasajero',
      nationalId:
          json['numero_documento'] ??
          json['national_id'] ??
          json['cedula'] ??
          '',
      documentType: json['tipo_documento'] ?? json['document_type'] ?? 'CC',
      phone: json['phone'] ?? json['telefono'] ?? json['celular'],
    );
  }
}

class Trip {
  final String id;
  final String? assignmentId;
  final String? contractId;
  final String? companyId;
  final List<Passenger> passengers;
  final double price; // Tarifa base original
  final double driverRevenue;
  final double platformFee;
  final String originAddress;
  final String destinationAddress;
  final LatLng originLocation;
  final LatLng destinationLocation;
  final DateTime date;
  final double distanceKm;
  final double duration;
  final String? passengerPhone;
  final String?
  passengerPhotoUrl; // 🟢 SOLUCIÓN: VARIABLE AGREGADA CORRECTAMENTE A LA CLASE
  final double waitingFee; // costo_espera_excedida
  final int waitingMinutes; // minutos_espera_excedidos
  final double basePrice; // tarifa_base_viaje
  final TripStatus status;
  final PaymentMethod paymentMethod;
  final String? fuecUrl;
  final Map<String, dynamic>? legalSnapshot;
  final DateTime? scheduledAt;

  // 🏷️ NUEVOS CAMPOS DE DESCUENTO (CONDUCTOR)
  final String? promotionId;
  final double discount;
  final String? vehicleId; // 🟢 NUEVO CAMPO
  final Map<String, dynamic>?
  desglosePrecio; // 🟢 NUEVA VARIABLE MAESTRA PEAJES

  Trip({
    required this.id,
    this.assignmentId,
    this.contractId,
    this.vehicleId,
    this.passengerPhotoUrl,
    this.companyId,
    required this.passengers,
    required this.price,
    this.driverRevenue = 0.0,
    this.platformFee = 0.0,
    required this.originAddress,
    required this.destinationAddress,
    required this.date,
    required this.originLocation,
    required this.destinationLocation,
    required this.distanceKm,
    required this.duration,
    this.passengerPhone,
    this.status = TripStatus.REQUESTED,
    this.paymentMethod = PaymentMethod.CASH,
    this.fuecUrl,
    this.legalSnapshot,
    this.scheduledAt,
    this.promotionId,
    this.discount = 0.0,
    this.desglosePrecio,
    this.waitingFee = 0.0, // 🟢 Inyectado
    this.waitingMinutes = 0, // 🟢 Inyectado
    this.basePrice = 0.0, // 🟢 Inyectado
  });

  String get passengerName =>
      passengers.isNotEmpty ? passengers.first.name : "Usuario";

  // 🟢 NUEVO GETTER: Extrae las paradas intermedias de forma segura
  List<Map<String, dynamic>>? get intermediateStops {
    if (desglosePrecio != null && desglosePrecio!['paradas'] != null) {
      try {
        return List<Map<String, dynamic>>.from(desglosePrecio!['paradas']);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // --- GETTERS EXCLUSIVOS PARA CONDUCTOR (TRANSPARENCIA) ---
  bool get hasDiscount => discount > 0.0;

  // Lo que el pasajero debe pagar físicamente en efectivo
  double get passengerCashToPay => price - discount;

  String get formattedPrice {
    final currency = NumberFormat("#,##0", "es_CO");
    return "\$ ${currency.format(price)}";
  }

  String get formattedPassengerCashToPay {
    final currency = NumberFormat("#,##0", "es_CO");
    return "\$ ${currency.format(passengerCashToPay)}";
  }

  String get formattedDiscount {
    final currency = NumberFormat("#,##0", "es_CO");
    return "\$ ${currency.format(discount)}";
  }

  String get formattedDriverRevenue {
    final currency = NumberFormat("#,##0", "es_CO");
    return "\$ ${currency.format(driverRevenue)}";
  }

  Trip copyWith({
    String? id,
    String? contractId,
    String? companyId,
    String? vehicleId,
    String? passengerPhotoUrl,
    List<Passenger>? passengers,
    double? price,
    double? driverRevenue,
    double? platformFee,
    String? originAddress,
    String? destinationAddress,
    DateTime? date,
    LatLng? originLocation,
    LatLng? destinationLocation,
    double? distanceKm,
    double? duration,
    String? passengerPhone,
    TripStatus? status,
    PaymentMethod? paymentMethod,
    String? fuecUrl,
    Map<String, dynamic>? legalSnapshot,
    DateTime? scheduledAt,
    String? promotionId,
    double? discount,
    Map<String, dynamic>? desglosePrecio,
  }) {
    return Trip(
      id: id ?? this.id,
      date: date ?? this.date,
      contractId: contractId ?? this.contractId,
      companyId: companyId ?? this.companyId,
      vehicleId: vehicleId ?? this.vehicleId,
      passengerPhotoUrl: passengerPhotoUrl ?? this.passengerPhotoUrl,
      passengers: passengers ?? this.passengers,
      price: price ?? this.price,
      driverRevenue: driverRevenue ?? this.driverRevenue,
      platformFee: platformFee ?? this.platformFee,

      // 🟢 CORRECCIÓN NULL-SAFETY: Verificación rigurosa que impide asignar valores nulos a propiedades obligatorias
      originAddress: _isNewTripPartial(originAddress)
          ? this.originAddress
          : originAddress!,
      destinationAddress: _isNewTripPartial(destinationAddress)
          ? this.destinationAddress
          : destinationAddress!,
      originLocation: originLocation ?? this.originLocation,
      destinationLocation: destinationLocation ?? this.destinationLocation,

      // 🟢 CORRECCIÓN: ASIGNAR LAS VARIABLES FALTANTES EN EL CONSTRUCTOR
      distanceKm: distanceKm ?? this.distanceKm,
      duration: duration ?? this.duration,

      passengerPhone: passengerPhone ?? this.passengerPhone,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      fuecUrl: fuecUrl ?? this.fuecUrl,
      legalSnapshot: legalSnapshot ?? this.legalSnapshot,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      promotionId: promotionId ?? this.promotionId,
      discount: discount ?? this.discount,
      desglosePrecio: desglosePrecio ?? this.desglosePrecio,
    );
  }

  // 🟢 HELPER ÚNICO DE SOPORTE PARA EVITAR DUPLICIDADES Y TYPOS
  static bool _isNewTripPartial(String? address) =>
      address == null || address == 'Origen...' || address.isEmpty;

  factory Trip.fromMap(Map<String, dynamic> map) {
    // ignore: avoid_print
    print("DEBUG_DATOS_JSON_RECIBIDOS: $map");

    // 🟢 EXTRACTOR ROBUSTO: Asegura capturar el objeto del viaje sin importar cómo venga anidado en el socket
    final dynamic v = (map.containsKey('viaje') && map['viaje'] != null)
        ? map['viaje']
        : ((map.containsKey('asignacion') &&
                  map['asignacion'] != null &&
                  map['asignacion']['viaje'] != null)
              ? map['asignacion']['viaje']
              : map);
    double checkDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // 🟢 DECODIFICADOR ROBUSTO: Decodifica de forma segura si la base de datos envía un JSON String o un Map
    final desgloseRaw =
        v['desglose_precio'] ??
        map['desglose_precio'] ??
        (v['conductores_online'] is Map ? v['conductores_online'] : null);
    Map<String, dynamic> desgloseMap = {};
    if (desgloseRaw != null) {
      if (desgloseRaw is String) {
        try {
          desgloseMap = json.decode(desgloseRaw);
        } catch (_) {}
      } else if (desgloseRaw is Map) {
        desgloseMap = Map<String, dynamic>.from(desgloseRaw);
      }
    }
    // Agrega estas líneas de parseo dentro de Trip.fromMap antes del return Trip(...):
    int checkInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    final double waitingFeeVal = checkDouble(
      v['costo_espera_excedida'] ?? map['costo_espera_excedida'] ?? 0.0,
    );
    final int waitingMinutesVal = checkInt(
      v['minutos_espera_excedidos'] ?? map['minutos_espera_excedidos'] ?? 0,
    );
    final double basePriceVal = checkDouble(
      v['tarifa_base_viaje'] ?? map['tarifa_base_viaje'] ?? 0.0,
    );
    final double totalPriceRecalculated = checkDouble(
      v['precio_total_recalculado'] ??
          map['precio_total_recalculado'] ??
          v['precio_estimado'] ??
          map['precio_estimado'] ??
          0.0,
    );
    final double totalPeajes = checkDouble(desgloseMap['total_peajes']);
    final TripStatus calculatedStatus = _parseStatus(
      map['estado'] ?? map['status'],
    );

    String? extractedPhone;
    String? extractedPhoto; // 🟢 VARIABLE DE FOTO DE PASAJERO DECLARADA

    try {
      // 1. Extraer Teléfono
      if (map['telefono_pasajero'] != null) {
        extractedPhone = map['telefono_pasajero'].toString();
      } else if (v['telefono_pasajero'] != null) {
        extractedPhone = v['telefono_pasajero'].toString();
      } else if (map['usuario'] != null && map['usuario']['telefono'] != null) {
        extractedPhone = map['usuario']['telefono'].toString();
      } else if (v['usuario'] != null && v['usuario']['telefono'] != null) {
        extractedPhone = v['usuario']['telefono'].toString();
      } else if (map['usuario'] != null && map['usuario']['phone'] != null) {
        extractedPhone = map['usuario']['phone'].toString();
      } else if (map['pasajeros'] != null &&
          map['pasajeros'] is List &&
          (map['pasajeros'] as List).isNotEmpty) {
        final firstPas = (map['pasajeros'] as List).first;
        if (firstPas is Map) {
          extractedPhone =
              (firstPas['phone'] ??
                      firstPas['telefono'] ??
                      firstPas['celular'] ??
                      '')
                  .toString();
        }
      }

      // =====================================================================
      // 2. 🟢 EXTRACCIÓN SEGURA Y AUTO-REPARACIÓN DE FOTO DE PASAJERO
      // =====================================================================
      final dynamic userMap = map['usuario'] ?? v['usuario'];
      if (userMap != null && userMap is Map) {
        extractedPhoto =
            userMap['foto_perfil']?.toString() ??
            userMap['selfie']?.toString() ??
            userMap['photo_url']?.toString();

        // 🟢 AUTO-REPARACIÓN: Si la ruta es relativa, anteponemos el almacenamiento público del backend
        if (extractedPhoto != null && !extractedPhoto.startsWith('http')) {
          extractedPhoto =
              'https://api.vamosapp.com.co/storage/$extractedPhoto';
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print("Error parseando teléfono o foto de pasajero: $e");
    }

    return Trip(
      id: (map['id'] ?? v['id'] ?? '').toString(),
      assignmentId:
          (map['assignment_id'] ??
                  (isset(map['asignacion']) ? map['asignacion']['id'] : '') ??
                  '')
              .toString(),
      fuecUrl: map['fuec_url']?.toString(),
      contractId: map['id_contrato']?.toString(),
      passengers: (map['pasajeros'] ?? v['pasajeros']) != null
          ? List<Passenger>.from(
              (map['pasajeros'] ?? v['pasajeros']).map(
                (x) => Passenger.fromJson(x),
              ),
            )
          : [],
      price:
          totalPriceRecalculated, // 🟢 Sincronizado para usar el total con recargo incluido
      driverRevenue: checkDouble(
        map['ganancia_neta'] ??
            map['tu_ganancia_neta'] ??
            v['ganancia_conductor'] ??
            map['ganancia_conductor'] ??
            0,
      ),
      platformFee: checkDouble(
        map['comision_app'] ??
            v['comision_aplicada'] ??
            map['comision_aplicada'] ??
            0,
      ),
      originAddress: map['origen'] ?? v['origen'] ?? 'Origen...',
      destinationAddress: map['destino'] ?? v['destino'] ?? 'Destino...',
      distanceKm: checkDouble(
        map['asignacion']?['viaje']?['distancia_km'] ??
            map['distancia_km'] ??
            desgloseMap['distancia_km'] ??
            0.0,
      ),
      duration: checkDouble(
        map['asignacion']?['viaje']?['duracion_minutos'] ??
            map['duracion_minutos'] ??
            desgloseMap['duracion_minutos'] ??
            0.0,
      ),
      passengerPhone: extractedPhone,
      passengerPhotoUrl: extractedPhoto,
      status: calculatedStatus,
      paymentMethod: _parsePaymentMethod(map['metodo_pago']),
      originLocation: LatLng(
        checkDouble(
          v['lat_origen'] ??
              v['origen_lat'] ??
              map['lat_origen'] ??
              map['origen_lat'] ??
              0.0,
        ),
        checkDouble(
          v['lng_origen'] ??
              v['origen_lng'] ??
              map['lng_origen'] ??
              map['origen_lng'] ??
              0.0,
        ),
      ),
      destinationLocation: LatLng(
        checkDouble(
          v['lat_destino'] ??
              v['destino_lat'] ??
              map['lat_destino'] ??
              map['destino_lat'] ??
              0.0,
        ),
        checkDouble(
          v['lng_destino'] ??
              v['destino_lng'] ??
              map['lng_destino'] ??
              map['origen_lng'] ??
              0.0,
        ),
      ),
      date: DateTime.parse(
        map['solicitado_en'] ?? DateTime.now().toIso8601String(),
      ),
      legalSnapshot: {
        'total_peajes': totalPeajes,
        'porcentaje_comision': checkDouble(desgloseMap['porcentaje_aplicado']),
        ...(map['snapshot_legal'] is Map ? map['snapshot_legal'] : {}),
      },
      scheduledAt: (v['programado_para'] ?? map['programado_para']) != null
          ? DateTime.parse(
              (v['programado_para'] ?? map['programado_para']).toString(),
            ).toLocal()
          : null,
      promotionId: (map['id_promocion'] ?? v['id_promocion'])?.toString(),
      // 🟢 DETECTOR DE DESCUENTO MAESTRO: Extrae el monto del cupón buscando en todos los niveles posibles del JSON
      discount: checkDouble(
        v['monto_descuento'] ??
            map['monto_descuento'] ??
            v['discount'] ??
            map['discount'] ??
            ((map.containsKey('asignacion') &&
                    map['asignacion'] != null &&
                    map['asignacion']['viaje'] != null)
                ? map['asignacion']['viaje']['monto_descuento']
                : 0.0),
      ),
      vehicleId: (map['id_vehiculo'] ?? v['id_vehiculo'])?.toString(),
      desglosePrecio: desgloseMap,
      waitingFee: waitingFeeVal, // 🟢 Mapeado
      waitingMinutes: waitingMinutesVal, // 🟢 Mapeado
      basePrice: basePriceVal, // 🟢 Mapeado
    );
  }

  static bool isset(dynamic map) => map != null && map is Map;
  static TripStatus _parseStatus(dynamic status) {
    if (status == null) {
      return TripStatus.CANCELLED;
    }

    final s = status.toString().toUpperCase();

    if (s == 'ACEPTADO' || s == 'ACCEPTED') return TripStatus.ACCEPTED;
    if (s == 'LLEGADO' || s == 'ARRIVED') return TripStatus.ARRIVED;
    if (s == 'INICIADO' || s == 'STARTED') return TripStatus.STARTED;
    if (s == 'FINALIZADO' || s == 'COMPLETED') return TripStatus.COMPLETED;
    if (s == 'CANCELADO' || s == 'CANCELLED') return TripStatus.CANCELLED;

    if (s == 'SCHEDULED_ASSIGNED') return TripStatus.SCHEDULED_ASSIGNED;
    if (s == 'SCHEDULED_LATE_ALERT') {
      return TripStatus.SCHEDULED_LATE_ALERT;
    }

    try {
      return TripStatus.values.byName(s);
    } catch (_) {
      return TripStatus.REQUESTED;
    }
  }

  static PaymentMethod _parsePaymentMethod(dynamic method) {
    if (method == null) return PaymentMethod.CASH;
    try {
      return PaymentMethod.values.byName(method.toString().toUpperCase());
    } catch (_) {
      return PaymentMethod.CASH;
    }
  }

  Map<String, dynamic> toMap() => {'id': id};
  String toJson() => json.encode(toMap());
  factory Trip.fromJson(String source) => Trip.fromMap(json.decode(source));
}
