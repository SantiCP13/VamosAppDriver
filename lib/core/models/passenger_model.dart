class Passenger {
  final String name;
  final String nationalId; // Cédula para el FUEC

  Passenger({required this.name, required this.nationalId});

  Map<String, dynamic> toJson() {
    return {'name': name, 'national_id': nationalId};
  }

  factory Passenger.fromJson(Map<String, dynamic> json) {
    return Passenger(
      name: json['name'] ?? '',
      nationalId: json['national_id'] ?? '',
    );
  }
}
