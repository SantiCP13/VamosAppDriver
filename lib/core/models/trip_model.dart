// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import '../enums/payment_enums.dart';

enum TripStatus {
  PENDING, // <--- AÑADE ESTO

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
  final String documentType; // <--- NUEVO: CC, CE, TI, etc.
  final String? phone;

  Passenger({
    required this.name,
    required this.nationalId,
    this.documentType = 'CC', // Por defecto CC
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
      // Sincronizamos llaves con el Backend de Laravel
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
    this.status = TripStatus.REQUESTED,
    this.paymentMethod = PaymentMethod.CASH,
    this.fuecUrl,
    this.legalSnapshot,
  });

  String get passengerName =>
      passengers.isNotEmpty ? passengers.first.name : "Usuario";
  /*
  String? get fuecUrl {
    if (legalSnapshot != null && legalSnapshot!.containsKey('fuec_url')) {
      return legalSnapshot!['fuec_url'];
    }
    if (status == TripStatus.ACCEPTED ||
        status == TripStatus.ARRIVED ||
        status == TripStatus.STARTED) {
      return "https://www.ministeriodetransporte.gov.co/documentos/fuec_ejemplo.pdf";
    }
    return null;
  }
  */
  factory Trip.mock() {
    return Trip(
      id: "trip_mock",
      date: DateTime.now(),
      passengers: [Passenger(name: "Ana María", nationalId: "123")],
      price: 12500.0,
      originAddress: "Andino",
      destinationAddress: "93",
      originLocation: const LatLng(4.66, -74.05),
      destinationLocation: const LatLng(4.67, -74.04),
      distanceKm: 2.5,
    );
  }

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
    TripStatus? status,
    PaymentMethod? paymentMethod,
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
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      legalSnapshot: legalSnapshot ?? this.legalSnapshot,
    );
  }

  factory Trip.fromMap(Map<String, dynamic> map) {
    double checkDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    TripStatus calculatedStatus = _parseStatus(map['estado'] ?? map['status']);

    // --- NUEVA LÓGICA FINANCIERA DINÁMICA ---
    final desglose = map['desglose_precio'] ?? {};
    final double totalPeajes = checkDouble(desglose['total_peajes']);
    final latOri = checkDouble(map['lat_origen']);

    return Trip(
      id: (latOri == 0.0)
          ? "0"
          : (map['id'] ?? map['viaje_id'] ?? '').toString(),
      assignmentId: map['assignment_id']?.toString(),
      fuecUrl: map['fuec_url']?.toString(),
      contractId: map['id_contrato']?.toString(),
      passengers: map['pasajeros'] != null
          ? List<Passenger>.from(
              map['pasajeros'].map((x) => Passenger.fromJson(x)),
            )
          : [],

      // 1. PRECIO TOTAL (Lo que paga el usuario)
      price: checkDouble(
        map['precio_estimado'] ??
            map['total_a_cobrar_al_pasajero'] ??
            map['monto_final'],
      ),

      // 2. GANANCIA NETA (Lo que le queda al conductor después de comisión)
      driverRevenue: checkDouble(
        map['ganancia_conductor'] ?? map['tu_ganancia_neta'],
      ),

      // 3. COMISIÓN (Lo que se queda la App)
      platformFee: checkDouble(
        map['comision_app'] ?? map['comision_app_descontada'],
      ),

      originAddress: map['origen'] ?? 'Origen...',
      destinationAddress: map['destino'] ?? 'Destino...',
      distanceKm: checkDouble(map['distancia_km']),
      status: calculatedStatus,
      paymentMethod: _parsePaymentMethod(map['metodo_pago']),
      originLocation: LatLng(
        checkDouble(map['lat_origen']),
        checkDouble(map['lng_origen']),
      ),
      destinationLocation: LatLng(
        checkDouble(map['lat_destino']),
        checkDouble(map['lng_destino']),
      ),
      date: DateTime.parse(
        map['solicitado_en'] ?? DateTime.now().toIso8601String(),
      ),

      // Guardamos info extra para mostrarla en el historial
      legalSnapshot: {
        'total_peajes': totalPeajes,
        'porcentaje_comision': checkDouble(desglose['porcentaje_aplicado']),
        ...(map['snapshot_legal'] is Map ? map['snapshot_legal'] : {}),
      },
    );
  }
  static TripStatus _parseStatus(dynamic status) {
    if (status == null) {
      // CAMBIO: Si no hay estado, no es REQUESTED, es un estado nulo
      // Puedes crear un estado 'NONE' en tu Enum o manejarlo como nulo
      return TripStatus.CANCELLED; // O el estado que prefieras para "vacío"
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
