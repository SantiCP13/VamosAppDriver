class DriverDocument {
  final String id;
  final String name; // SOAT, Tecnomecánica, Póliza Contractual
  final DateTime expirationDate;
  final String status; // 'VIGENTE', 'VENCIDO', 'PENDIENTE'
  final String? url;

  DriverDocument({
    required this.id,
    required this.name,
    required this.expirationDate,
    required this.status,
    this.url,
  });

  bool get isValid =>
      status == 'VIGENTE' && expirationDate.isAfter(DateTime.now());

  factory DriverDocument.fromJson(Map<String, dynamic> json) {
    return DriverDocument(
      id: json['id'].toString(),
      name: json['tipo_documento'] ?? 'Documento',
      expirationDate: DateTime.parse(json['expira_en']),
      status: json['estado'] ?? 'PENDIENTE',
      url: json['archivo_url'],
    );
  }
}
