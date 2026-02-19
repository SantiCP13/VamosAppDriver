// lib/core/models/user_model.dart

// ignore_for_file: constant_identifier_names

/// ESTADO DE VERIFICACIÓN
enum UserVerificationStatus {
  PENDING, // Registrado, email no verificado
  CREATED, // Email verificado, faltan datos
  DOCS_UPLOADED, // (Para conductores principalmente)
  UNDER_REVIEW, // (Para conductores o validación manual de empresas)
  VERIFIED, // PUEDE PEDIR VIAJES / CONDUCIR
  REJECTED, // Rechazado por datos inválidos o falta de documentos
  REVOKED, // BLOQUEADO por mal uso o fraude
}

/// ROL DEL USUARIO
enum UserRole {
  NATURAL, // Usuario particular
  EMPLEADO, // Usuario corporativo
  DRIVER, // Nuevo: Conductor
}

/// MODO DE OPERACIÓN
enum AppMode { PERSONAL, CORPORATE }

/// MODELO DE BENEFICIARIO (PASAJERO ADICIONAL)
class Beneficiary {
  final String id;
  final String name;
  final String documentNumber;

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

  // Variables mutables
  String? idPassenger;
  String? idResponsable; // FK manager_id
  String? photoUrl;

  final String email;
  final String name;
  final String phone;

  /// Cédula para FUEC.
  final String documentNumber;

  final String address;

  // --- DATOS CORPORATIVOS ---
  final String? companyUuid;
  String empresa;
  String nitEmpresa;

  // --- ESTADOS Y ROL ---
  UserRole role;
  UserVerificationStatus verificationStatus;
  AppMode appMode;

  // Lista para selección rápida en "Quién viaja?"
  List<Beneficiary> beneficiaries;

  // Autenticación
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
        AppMode.PERSONAL, // Default a PERSONAL para evitar errores en Driver
    this.token,
  });

  bool get isCorporateMode => appMode == AppMode.CORPORATE;
  bool get isEmployee => role == UserRole.EMPLEADO || idResponsable != null;
  bool get isDriver => role == UserRole.DRIVER; // Helper útil

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id']?.toString() ?? '',
      idPassenger: map['passenger_id']?.toString() ?? map['id_pasajero'],
      idResponsable: map['manager_id']?.toString() ?? map['id_responsable'],
      email: map['email'] ?? '',
      name: map['name'] ?? map['nombre'] ?? '',
      photoUrl: map['photo_url'],
      phone: map['phone'] ?? map['telefono'] ?? '',
      documentNumber: map['document_number'] ?? map['documento'] ?? '',
      address: map['address'] ?? map['direccion'] ?? '',

      // Empresa
      empresa: map['company_name'] ?? map['empresa'] ?? '',
      nitEmpresa: map['company_nit'] ?? map['nit_empresa'] ?? '',
      companyUuid: map['company_id'],

      // --- CORRECCIÓN EN ROL ---
      role: _parseRole(map['role'] ?? map['role_id']),

      verificationStatus: _parseStatus(map['status']),

      appMode: (map['app_mode'] == 'CORPORATE')
          ? AppMode.CORPORATE
          : AppMode.PERSONAL,

      beneficiaries:
          (map['beneficiaries'] as List<dynamic>?)
              ?.map((e) => Beneficiary.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],

      token: map['access_token'],
    );
  }

  // Helper para parsear Roles
  static UserRole _parseRole(dynamic input) {
    if (input == 'DRIVER' || input == 'CONDUCTOR') return UserRole.DRIVER;
    if (input == 'EMPLEADO' || input == 2) return UserRole.EMPLEADO;
    return UserRole.NATURAL; // Default
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
    // Helper simple para convertir el Enum a String
    String roleStr;
    switch (role) {
      case UserRole.DRIVER:
        roleStr = 'DRIVER';
        break;
      case UserRole.EMPLEADO:
        roleStr = 'EMPLEADO';
        break;
      default:
        roleStr = 'NATURAL';
    }

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
      'role': roleStr, // Guardamos el rol correcto
      'status': verificationStatus.name,
      'app_mode': appMode == AppMode.CORPORATE ? 'CORPORATE' : 'PERSONAL',
      'beneficiaries': beneficiaries.map((b) => b.toJson()).toList(),
    };
  }
}
