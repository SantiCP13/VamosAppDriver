import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/user_model.dart';

import '../services/driver_auth_service.dart';
import '../../home/screens/home_screen.dart';
import 'welcome_screen.dart'; // Asegúrate de que este import exista

class VerificationCheckScreen extends StatefulWidget {
  const VerificationCheckScreen({super.key});

  @override
  State<VerificationCheckScreen> createState() =>
      _VerificationCheckScreenState();
}

class _VerificationCheckScreenState extends State<VerificationCheckScreen> {
  final DriverAuthService _authService = DriverAuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Consultamos el estado al entrar, pero sin bloquear la UI agresivamente
    _checkStatusSilent();
  }

  /// Consulta el estado real al Backend/Mock sin interacción del usuario
  Future<void> _checkStatusSilent() async {
    try {
      final status = await _authService.checkStatus();

      if (!mounted) return;

      // Si por alguna razón el admin ya lo aprobó en el backend:
      if (status == UserVerificationStatus.VERIFIED) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
      // Si fue rechazado:
      else if (status == UserVerificationStatus.REJECTED) {
        _showSnackBar(
          'Documentos rechazados. Contacta a soporte.',
          isError: true,
        );
      }
      // Si sigue PENDING, no hacemos nada, se queda en esta pantalla.
    } catch (e) {
      // Errores silenciosos en init
      debugPrint("Error verificando estado: $e");
    }
  }

  Future<void> _handleBackToStart() async {
    setState(() => _isLoading = true);
    // Cerramos sesión para limpiar tokens y estado
    await _authService.logout();

    if (!mounted) return;

    // Volvemos a la pantalla de bienvenida (Login/Registro)
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Solicitud Enviada",
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: RefreshIndicator(
        onRefresh: _checkStatusSilent,
        color: Colors.green,
        child: LayoutBuilder(
          // Usamos LayoutBuilder para obtener la altura real disponible
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Container(
                // CAMBIO 1: Altura completa (constraints.maxHeight) en lugar de * 0.8
                height: constraints.maxHeight,
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // CAMBIO 2: Spacer arriba para empujar el contenido al centro
                    const Spacer(),

                    // Icono de Estado
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(
                          255,
                          4,
                          24,
                          67,
                        ).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.inventory_rounded,
                        size: 80,
                        color: const Color.fromARGB(255, 10, 4, 74),
                      ),
                    ),

                    const SizedBox(height: 32),

                    Text(
                      "Documentación en Revisión",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      "Hemos recibido tus documentos (Cédula y Licencia). El equipo administrativo validará la información para habilitarte en la plataforma.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Nota informativa
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              "Te notificaremos cuando tu cuenta esté activa.",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(), // Spacer existente (empuja el botón abajo)
                    // Botón "Volver al Inicio"
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _handleBackToStart,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: const Color.fromARGB(255, 7, 3, 54),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                "Volver al Inicio",
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(
                      height: 30,
                    ), // Espacio extra al final para que no pegue al borde
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
