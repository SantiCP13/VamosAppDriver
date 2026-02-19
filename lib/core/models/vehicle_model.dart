class Vehicle {
  final String id;
  final String brand; // Marca (Renault, Chevrolet)
  final String model; // Linea (Logan, Spark)
  final String plate; // PLACA (Clave para el FUEC)
  final String color;
  final int year;
  final int capacity;
  final bool isActive; // Si la empresa lo ha habilitado

  Vehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.plate,
    required this.color,
    required this.year,
    required this.capacity,
    this.isActive = true,
  });

  String get fullName => "$brand $model ($year)";

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'].toString(),
      brand: json['marca'] ?? '',
      model: json['modelo'] ?? '',
      plate: json['placa'] ?? '',
      color: json['color'] ?? '',
      year: int.tryParse(json['anio'].toString()) ?? 2020,
      capacity: int.tryParse(json['capacidad'].toString()) ?? 4,
      isActive: json['activo'] == true || json['activo'] == 1,
    );
  }

  // Mock para pruebas inmediatas
  static List<Vehicle> getMocks() {
    return [
      Vehicle(
        id: 'v1',
        brand: 'Renault',
        model: 'Kwid',
        plate: 'WEM-123',
        color: 'Blanco',
        year: 2023,
        capacity: 4,
      ),
      Vehicle(
        id: 'v2',
        brand: 'Chevrolet',
        model: 'Joy',
        plate: 'SOP-987',
        color: 'Gris',
        year: 2022,
        capacity: 4,
      ),
    ];
  }
}
