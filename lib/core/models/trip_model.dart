// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import '../enums/payment_enums.dart';

enum TripStatus {
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
  final String? phone; // Nuevo campo para WhatsApp

  Passenger({required this.name, required this.nationalId, this.phone});

  Map<String, dynamic> toJson() => {
    'name': name,
    'national_id': nationalId,
    'phone': phone,
  };

  factory Passenger.fromJson(Map<String, dynamic> json) {
    return Passenger(
      name: json['name'] ?? '',
      nationalId: json['national_id'] ?? json['cedula'] ?? '',
      // Manejo robusto de diferentes nombres de campo del backend
      phone: json['phone'] ?? json['telefono'] ?? json['celular'],
    );
  }
}

class Trip {
  final String id;
  final String? contractId;
  final String? companyId;
  final List<Passenger> passengers;
  final double price;
  final double driverRevenue; // Lo que realmente recibe el conductor
  final double platformFee; // La comisión de la App
  final String originAddress;
  final String destinationAddress;
  final LatLng originLocation;
  final LatLng destinationLocation;

  final double distanceKm;
  final TripStatus status;
  final PaymentMethod paymentMethod;
  final Map<String, dynamic>? legalSnapshot;

  Trip({
    required this.id,
    this.contractId,
    this.companyId,
    required this.passengers,
    required this.price,
    this.driverRevenue = 0.0,
    this.platformFee = 0.0,
    required this.originAddress,
    required this.destinationAddress,
    required this.originLocation,
    required this.destinationLocation,
    required this.distanceKm,
    this.status = TripStatus.REQUESTED,
    this.paymentMethod = PaymentMethod.CASH,
    this.legalSnapshot,
  });

  // Helpers
  String get passengerName =>
      passengers.isNotEmpty ? passengers.first.name : "Usuario";

  // LOGICA FUEC: Extrae la URL del PDF del snapshot legal
  String? get fuecUrl {
    if (legalSnapshot != null && legalSnapshot!.containsKey('fuec_url')) {
      return legalSnapshot!['fuec_url'];
    }
    // Fallback Mock para pruebas si el estado lo permite
    if (status == TripStatus.ACCEPTED ||
        status == TripStatus.ARRIVED ||
        status == TripStatus.STARTED) {
      return "https://www.ministeriodetransporte.gov.co/documentos/fuec_ejemplo.pdf";
    }
    return null;
  }

  // Factory Mock para pruebas
  factory Trip.mock() {
    return Trip(
      id: "trip_${DateTime.now().millisecondsSinceEpoch}",
      contractId: "contrato_marco_2026",
      companyId: null,
      passengers: [
        Passenger(
          name: "Ana María Pérez",
          nationalId: "10203040",
          phone: "3001234567", // Teléfono para probar WhatsApp
        ),
      ],
      price: 12500.0,
      driverRevenue: 10000.0,
      platformFee: 2500.0,
      originAddress: "Centro Comercial Andino",
      destinationAddress: "Parque de la 93",
      originLocation: const LatLng(4.6668, -74.0526),
      destinationLocation: const LatLng(4.6766, -74.0483),
      distanceKm: 2.5,
      paymentMethod: PaymentMethod.DIGITAL,
      status: TripStatus.REQUESTED,
      legalSnapshot: {
        'fuec_url':
            'https://www.ministeriodetransporte.gov.co/documentos/fuec_ejemplo.pdf',
      },
    );
  }

  // Método copyWith para inmutabilidad
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
    LatLng? originLocation,
    LatLng? destinationLocation,
    double? distanceKm,
    TripStatus? status,
    PaymentMethod? paymentMethod,
    Map<String, dynamic>? legalSnapshot,
  }) {
    return Trip(
      id: id ?? this.id,
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

  Map<String, dynamic> toMap() {
    return {
      'uuid': id,
      'contrato_id': contractId,
      'passengers': passengers.map((x) => x.toJson()).toList(),
      'precio_total': price,
      'ganancia_conductor': driverRevenue,
      'comision_app': platformFee,
      'origen_direccion': originAddress,
      'destino_direccion': destinationAddress,
      'lat_origen': originLocation.latitude,
      'lng_origen': originLocation.longitude,
      'lat_destino': destinationLocation.latitude,
      'lng_destino': destinationLocation.longitude,
      'estado': status.name,
      'metodo_pago': paymentMethod.name,
      'snapshot_legal': legalSnapshot,
    };
  }

  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      id: map['uuid'] ?? map['id'],
      contractId: map['contrato_id'],
      passengers: map['passengers'] != null
          ? List<Passenger>.from(
              map['passengers'].map((x) => Passenger.fromJson(x)),
            )
          : [],
      price: (map['precio_total'] ?? map['price'] ?? 0.0).toDouble(),
      driverRevenue: (map['ganancia_conductor'] ?? map['driver_revenue'] ?? 0.0)
          .toDouble(),
      platformFee: (map['comision_app'] ?? map['platform_fee'] ?? 0.0)
          .toDouble(),
      originAddress: map['origen_direccion'] ?? map['originAddress'],
      destinationAddress: map['destino_direccion'] ?? map['destinationAddress'],
      originLocation: LatLng(
        map['lat_origen'] ?? map['originLat'],
        map['lng_origen'] ?? map['originLng'],
      ),
      destinationLocation: LatLng(
        map['lat_destino'] ?? map['destLat'],
        map['lng_destino'] ?? map['destLng'],
      ),
      distanceKm: (map['distanceKm'] ?? 0.0).toDouble(),
      status: TripStatus.values.byName(map['estado'] ?? map['status']),
      paymentMethod: map['metodo_pago'] != null
          ? PaymentMethod.values.byName(map['metodo_pago'])
          : PaymentMethod.CASH,
      legalSnapshot: map['snapshot_legal'],
    );
  }

  String toJson() => json.encode(toMap());
  factory Trip.fromJson(String source) => Trip.fromMap(json.decode(source));
}
