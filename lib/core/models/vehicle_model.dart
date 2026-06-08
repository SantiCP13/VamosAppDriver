// lib/core/models/vehicle_model.dart

class Vehicle {
  final String id;
  final String brand; // Marca (Renault, Chevrolet)
  final String model; // Linea (Logan, Spark)
  final String plate; // PLACA (Clave para el FUEC)
  final bool enConvenio; // o en_convenio, según tu modelo

  final String color;
  final int year;
  final int capacity;
  final bool isActive; // Si la empresa lo ha habilitado

  // 🟢 CORRECCIÓN: Declaración de las propiedades de la clase (Faltaba esto arriba)
  final Map<String, dynamic>? empresaTransporte;
  final Map<String, dynamic>? empresaConvenio;

  Vehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.plate,
    required this.color,
    required this.enConvenio,

    required this.year,
    required this.capacity,
    this.isActive = true,
    this.empresaTransporte,
    this.empresaConvenio,
  });

  String get fullName => "$brand $model ($year)";

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'].toString(),
      brand: json['marca'] ?? '', // 'marca' en BD
      model:
          json['linea'] ??
          json['modelo'] ??
          '', // Mapea 'linea' en BD (ej: Duster) si existe, o 'modelo' de respaldo
      enConvenio: json['en_convenio'] ?? json['enConvenio'] ?? false,

      plate: json['placa'] ?? '', // 'placa' en BD
      color: json['color'] ?? 'N/A',
      year:
          int.tryParse(json['year'].toString()) ??
          int.tryParse(
            json['modelo'].toString(),
          ) ?? // 🟢 Fallback: usa 'modelo' de la BD si no existe 'year'
          2024,
      capacity: int.tryParse(json['capacidad'].toString()) ?? 4,
      isActive:
          json['activo'] == true ||
          json['activo'] == 1 ||
          json['activo'] == '1',
      empresaTransporte: json['empresa_transporte'] != null
          ? Map<String, dynamic>.from(json['empresa_transporte'])
          : null,
      empresaConvenio: json['empresa_convenio'] != null
          ? Map<String, dynamic>.from(json['empresa_convenio'])
          : null,
    );
  }
}
