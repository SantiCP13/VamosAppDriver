// ignore_for_file: constant_identifier_names
import 'dart:convert';
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
}

class Passenger {
  final String name;
  final String nationalId;
  final String documentType; // CC, CE, TI, etc.
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
  final double price;
  final double driverRevenue;
  final double platformFee;
  final String originAddress;
  final String destinationAddress;
  final LatLng originLocation;
  final LatLng destinationLocation;
  final DateTime date;
  final double distanceKm;
  final double duration;
  final String?
  passengerPhone; // <--- NUEVO CAMPO PARA GUARDAR EL TELÉFONO DE LA BD

  final TripStatus status;
  final PaymentMethod paymentMethod;
  final String? fuecUrl;
  final Map<String, dynamic>? legalSnapshot;

  Trip({
    required this.id,
    this.assignmentId,
    this.contractId,
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
    this.passengerPhone, // <--- INICIALIZACIÓN

    this.status = TripStatus.REQUESTED,
    this.paymentMethod = PaymentMethod.CASH,
    this.fuecUrl,
    this.legalSnapshot,
  });

  String get passengerName =>
      passengers.isNotEmpty ? passengers.first.name : "Usuario";

  Trip copyWith({
    String? id,
    String? contractId,
    String? companyId,
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
    String? passengerPhone, // <--- SOPORTE COPYWITH

    TripStatus? status,
    PaymentMethod? paymentMethod,
    String? fuecUrl, // <--- AGREGADO AQUÍ

    Map<String, dynamic>? legalSnapshot,
  }) {
    return Trip(
      id: id ?? this.id,
      date: date ?? this.date,
      contractId: contractId ?? this.contractId,
      companyId: companyId ?? this.companyId,
      passengers: passengers ?? this.passengers,
      price: price ?? this.price,
      driverRevenue: driverRevenue ?? this.driverRevenue,
      platformFee: platformFee ?? this.platformFee,
      originAddress: originAddress ?? this.originAddress,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      originLocation: originLocation ?? this.originLocation,
      destinationLocation: destinationLocation ?? this.destinationLocation,
      distanceKm: distanceKm ?? this.distanceKm,
      duration: duration ?? this.duration,
      passengerPhone: passengerPhone ?? this.passengerPhone, // <--- RETORNO

      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      fuecUrl: fuecUrl ?? this.fuecUrl, // <--- AGREGADO AQUÍ

      legalSnapshot: legalSnapshot ?? this.legalSnapshot,
    );
  }

  factory Trip.fromMap(Map<String, dynamic> map) {
    // ignore: avoid_print
    print("DEBUG_DATOS_JSON_RECIBIDOS: $map");

    final v = map.containsKey('viaje')
        ? map['viaje']
        : (map.containsKey('asignacion') ? map['asignacion']['viaje'] : map);

    double checkDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    final desglose = (v['desglose_precio'] ?? map['desglose_precio'] ?? {});
    final double totalPeajes = checkDouble(desglose['total_peajes']);
    final TripStatus calculatedStatus = _parseStatus(
      map['estado'] ?? map['status'],
    );

    // --- EXTRACTOR DE TELÉFONO DE PASAJERO MULTICAPA A PRUEBA DE FALLOS ---
    String? extractedPhone;
    try {
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
    } catch (e) {
      // ignore: avoid_print
      print("Error parseando teléfono: $e");
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

      price: checkDouble(map['precio_estimado'] ?? v['precio_estimado'] ?? 0),
      driverRevenue: checkDouble(
        map['ganancia_neta'] ?? map['tu_ganancia_neta'] ?? 0,
      ),
      platformFee: checkDouble(map['comision_app'] ?? 0),

      originAddress: map['origen'] ?? v['origen'] ?? 'Origen...',
      destinationAddress: map['destino'] ?? v['destino'] ?? 'Destino...',

      distanceKm: checkDouble(
        map['asignacion']?['viaje']?['distancia_km'] ??
            map['distancia_km'] ??
            desglose['distancia_km'] ??
            0.0,
      ),
      duration: checkDouble(
        map['asignacion']?['viaje']?['duracion_minutos'] ??
            map['duracion_minutos'] ??
            desglose['duracion_minutos'] ??
            0.0,
      ),

      passengerPhone:
          extractedPhone, // <--- ALMACENAMIENTO DE TELÉFONO DE LA BD

      status: calculatedStatus,
      paymentMethod: _parsePaymentMethod(map['metodo_pago']),

      originLocation: LatLng(
        checkDouble(
          map['lat_origen'] ??
              (map.containsKey('viaje')
                  ? map['viaje']['lat_origen']
                  : (map.containsKey('asignacion')
                        ? map['asignacion']['viaje']['lat_origen']
                        : 0)),
        ),
        checkDouble(
          map['lng_origen'] ??
              (map.containsKey('viaje')
                  ? map['viaje']['lng_origen']
                  : (map.containsKey('asignacion')
                        ? map['asignacion']['viaje']['lng_origen']
                        : 0)),
        ),
      ),
      destinationLocation: LatLng(
        checkDouble(v['lat_destino'] ?? map['lat_destino'] ?? 0),
        checkDouble(v['lng_destino'] ?? map['lng_destino'] ?? 0),
      ),
      date: DateTime.parse(
        map['solicitado_en'] ?? DateTime.now().toIso8601String(),
      ),

      legalSnapshot: {
        'total_peajes': totalPeajes,
        'porcentaje_comision': checkDouble(desglose['porcentaje_aplicado']),
        ...(map['snapshot_legal'] is Map ? map['snapshot_legal'] : {}),
      },
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
