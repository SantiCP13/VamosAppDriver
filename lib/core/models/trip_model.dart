// ignore_for_file: constant_identifier_names
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import '../enums/payment_enums.dart';

enum TripStatus { REQUESTED, ACCEPTED, ARRIVED, STARTED, COMPLETED, CANCELLED }

class Passenger {
  final String name;
  final String nationalId;

  Passenger({required this.name, required this.nationalId});

  Map<String, dynamic> toJson() => {'name': name, 'national_id': nationalId};

  factory Passenger.fromJson(Map<String, dynamic> json) {
    return Passenger(
      name: json['name'] ?? '',
      nationalId: json['national_id'] ?? json['cedula'] ?? '',
    );
  }
}

class Trip {
  final String id;
  final String? contractId;
  final String? companyId;
  final List<Passenger> passengers;
  final double price;
  final double? driverCommission;
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
    this.driverCommission,
    required this.originAddress,
    required this.destinationAddress,
    required this.originLocation,
    required this.destinationLocation,
    required this.distanceKm,
    this.status = TripStatus.REQUESTED,
    this.paymentMethod = PaymentMethod.CASH,
    this.legalSnapshot,
  });

  String get passengerName =>
      passengers.isNotEmpty ? passengers.first.name : "Usuario";

  factory Trip.mock() {
    return Trip(
      id: "trip_${DateTime.now().millisecondsSinceEpoch}",
      contractId: "contrato_marco_2026",
      companyId: null,
      passengers: [
        Passenger(name: "Ana María Pérez", nationalId: "10203040"),
        Passenger(name: "Juanito (Hijo)", nationalId: "TI987654"),
      ],
      price: 12500.0,
      driverCommission: 10000.0,
      originAddress: "Centro Comercial Andino",
      destinationAddress: "Parque de la 93",
      originLocation: const LatLng(4.6668, -74.0526),
      destinationLocation: const LatLng(4.6766, -74.0483),
      distanceKm: 2.5,
      paymentMethod: PaymentMethod.DIGITAL,
    );
  }

  // --- SOLUCIÓN AQUÍ ---
  Trip copyWith({
    String? id,
    List<Passenger>? passengers,
    double? price,
    TripStatus? status,
    Map<String, dynamic>? legalSnapshot,
  }) {
    return Trip(
      // Se mantiene 'this.id' porque existe un parámetro 'id'
      id: id ?? this.id,
      // Se quita 'this.' porque NO hay parámetro 'contractId' en copyWith
      contractId: contractId,
      companyId: companyId,
      passengers: passengers ?? this.passengers,
      price: price ?? this.price,
      driverCommission: driverCommission,
      originAddress: originAddress,
      destinationAddress: destinationAddress,
      originLocation: originLocation,
      destinationLocation: destinationLocation,
      distanceKm: distanceKm,
      status: status ?? this.status,
      paymentMethod: paymentMethod,
      legalSnapshot: legalSnapshot ?? this.legalSnapshot,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uuid': id,
      'contrato_id': contractId,
      'passengers': passengers.map((x) => x.toJson()).toList(),
      'precio_estimado': price,
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
      price: (map['precio_estimado'] ?? map['price'])?.toDouble() ?? 0.0,
      driverCommission: (map['comision_conductor'])?.toDouble(),
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
