// lib/core/models/user_model.dart

// ignore_for_file: constant_identifier_names

/// ESTADO DE VERIFICACIÓN
///
/// Controla si el usuario puede pedir viajes.
/// Mapea a la columna 'verification_status' en la tabla USERS.
enum UserVerificationStatus {
  PENDING, // Registrado, email no verificado
  CREATED, // Email verificado, faltan datos
  DOCS_UPLOADED, // (Para conductores principalmente)
  UNDER_REVIEW, // (Para conductores o validación manual de empresas)
  VERIFIED, // PUEDE PEDIR VIAJES
  REJECTED, // Rechazado por datos inválidos o falta de documentos
  REVOKED, // BLOQUEADO por mal uso o fraude (Solo admins pueden cambiar a este estado)
}

/// ROL DEL USUARIO
enum UserRole {
  NATURAL, // Usuario particular
  EMPLEADO, // Usuario corporativo (Asociado a una COMPANY)
}

/// MODO DE OPERACIÓN
///
/// Controla la UI y el flujo de pago.
/// PERSONAL: Paga en efectivo/wallet.
/// CORPORATE: El cobro va a la factura de la empresa.
enum AppMode { PERSONAL, CORPORATE }

/// MODELO DE BENEFICIARIO (PASAJERO ADICIONAL)

/// RESPONSABILIDADES:
/// 1. Llenar el 'Manifiesto de Pasajeros'
/// 2. Proveer nombre y CÉDULA para el payload del FUEC.
class Beneficiary {
  final String id; // PK
  final String name;
  final String documentNumber; // Requerido por ley para el FUEC.

  Beneficiary({
    required this.id,
    required this.name,
    required this.documentNumber,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'document_number': documentNumber,
  };

  factory Beneficiary.fromJson(Map<String, dynamic> json) {
    return Beneficiary(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      documentNumber: json['document_number'] ?? json['documentNumber'] ?? '',
    );
  }
}

/// MODELO DE USUARIO

class User {
  final String id; // PK (UUID)

  // Variables mutables (pueden cambiar en edición de perfil)
  String? idPassenger;
  String? idResponsable; // FK manager_id
  String? photoUrl;

  final String email; // Unique Login
  final String name;
  final String phone;

  /// Cédula para FUEC.
  /// Mapea a 'document_number' en USERS.
  final String documentNumber;

  final String address;

  // --- DATOS CORPORATIVOS (RELACIÓN CON COMPANIES) ---

  /// FK: ID de la empresa en BD.
  /// Vital para buscar el 'moviltrack_contract_id' cuando appMode = CORPORATE.
  final String? companyUuid;

  // Datos visuales de la empresa (Join simple)
  String empresa;
  String nitEmpresa;

  // --- ESTADOS Y CONTROL DE FLUJO ---

  UserRole role;
  UserVerificationStatus verificationStatus;

  /// Define si la solicitud de viaje incluye 'company_uuid' o no.
  AppMode appMode;

  // Lista para selección rápida en "Quién viaja?"
  List<Beneficiary> beneficiaries;

  // Autenticación (No se guarda en BD, solo en sesión local)
  String? token;

  User({
    required this.id,
    this.idPassenger,
    this.idResponsable,
    required this.email,
    required this.name,
    required this.phone,
    this.documentNumber = '',
    this.address = '',
    this.photoUrl,
    required this.role,
    this.empresa = '',
    this.nitEmpresa = '',
    this.companyUuid,
    this.verificationStatus = UserVerificationStatus.CREATED,
    required this.beneficiaries,
    this.appMode =
        AppMode.CORPORATE, // Por defecto intenta ser corporativo si es empleado
    this.token,
  });

  // Helpers de lógica de negocio
  bool get isCorporateMode => appMode == AppMode.CORPORATE;
  bool get isEmployee => role == UserRole.EMPLEADO || idResponsable != null;

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id']?.toString() ?? '',

      // Mapeo flexible para ids que vienen del backend
      idPassenger: map['passenger_id']?.toString() ?? map['id_pasajero'],
      idResponsable: map['manager_id']?.toString() ?? map['id_responsable'],

      email: map['email'] ?? '',
      name: map['name'] ?? map['nombre'] ?? '',
      photoUrl: map['photo_url'],
      phone: map['phone'] ?? map['telefono'] ?? '',
      documentNumber: map['document_number'] ?? map['documento'] ?? '',
      address: map['address'] ?? map['direccion'] ?? '',

      // --- MAPEADO DE EMPRESA ---

      // El backend debe hacer JOIN con COMPANIES para llenar esto
      empresa: map['company_name'] ?? map['empresa'] ?? '',
      nitEmpresa: map['company_nit'] ?? map['nit_empresa'] ?? '',
      companyUuid: map['company_id'], // FK Critical

      role: (map['role'] == 'EMPLEADO' || map['role_id'] == 2)
          ? UserRole.EMPLEADO
          : UserRole.NATURAL,

      verificationStatus: _parseStatus(map['status']),

      // Determina el modo inicial basado en la preferencia guardada o el rol
      appMode: (map['app_mode'] == 'PERSONAL')
          ? AppMode.PERSONAL
          : AppMode.CORPORATE,

      // Carga de beneficiarios (Tabla BENEFICIARIES)
      beneficiaries:
          (map['beneficiaries'] as List<dynamic>?)
              ?.map((e) => Beneficiary.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],

      token: map['access_token'], // JWT de Laravel Sanctum
    );
  }

  static UserVerificationStatus _parseStatus(String? status) {
    if (status == null) return UserVerificationStatus.CREATED;
    switch (status.toUpperCase()) {
      case 'ACTIVE':
      case 'VERIFIED':
        return UserVerificationStatus.VERIFIED;
      case 'PENDING':
      case 'UNVERIFIED':
        return UserVerificationStatus.PENDING;
      case 'UNDER_REVIEW':
        return UserVerificationStatus.UNDER_REVIEW;
      case 'DOCS_UPLOADED':
        return UserVerificationStatus.DOCS_UPLOADED;
      case 'REJECTED':
        return UserVerificationStatus.REJECTED;
      case 'REVOKED':
        return UserVerificationStatus.REVOKED;
      default:
        return UserVerificationStatus.CREATED;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'document_number': documentNumber,
      'address': address,
      'company_name': empresa,
      'company_nit': nitEmpresa,
      'company_id': companyUuid,
      'role': role == UserRole.EMPLEADO ? 'EMPLEADO' : 'NATURAL',
      'status': verificationStatus.name,
      'app_mode': appMode == AppMode.CORPORATE ? 'CORPORATE' : 'PERSONAL',
      'beneficiaries': beneficiaries.map((b) => b.toJson()).toList(),
    };
  }
}
