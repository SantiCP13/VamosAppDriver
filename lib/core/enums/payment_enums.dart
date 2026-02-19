// ignore_for_file: constant_identifier_names

enum PaymentMethod {
  CASH, // Efectivo físico (Manual)
  NEQUI, // Transferencia P2P a la cuenta del conductor (Manual)
  DAVIPLATA, // Transferencia P2P a la cuenta del conductor (Manual)
  WOMPI, // Pasarela de pago (Automático)
  WALLET, // Saldo virtual dentro de la app (Automático)
  CREDIT_CARD, // Tarjeta de crédito (Automático)
  DIGITAL, // Genérico/Legado por si el backend aún lo manda así
}

enum PaymentStatus { PENDING, APPROVED, REJECTED }

// NUEVO: Extensión para manejar la lógica de la UI y los Sockets
extension PaymentMethodExtension on PaymentMethod {
  // Define si el conductor debe hundir un botón para confirmar (No usa Socket)
  bool get isManual {
    return this == PaymentMethod.CASH ||
        this == PaymentMethod.NEQUI ||
        this == PaymentMethod.DAVIPLATA;
  }

  // Define el nombre bonito que verá el conductor en pantalla
  String get displayName {
    switch (this) {
      case PaymentMethod.CASH:
        return 'Efectivo';
      case PaymentMethod.NEQUI:
        return 'Nequi';
      case PaymentMethod.DAVIPLATA:
        return 'DaviPlata';
      case PaymentMethod.WOMPI:
        return 'Wompi';
      case PaymentMethod.WALLET:
        return 'Billetera Virtual';
      case PaymentMethod.CREDIT_CARD:
        return 'Tarjeta de Crédito';
      case PaymentMethod.DIGITAL:
        return 'Pago Digital';
    }
  }
}
