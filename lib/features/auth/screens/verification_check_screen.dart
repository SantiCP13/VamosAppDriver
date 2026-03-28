import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/user_model.dart';

import '../services/driver_auth_service.dart';
import '../../home/screens/home_screen.dart';
import 'welcome_screen.dart';

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
    _checkStatusSilent();
  }

  Future<void> _checkStatusSilent() async {
    try {
      // CORRECCIÓN AQUÍ: Llamamos a la nueva función que creamos en el auth_service
      final status = await _authService.verifySessionAndGetStatus();
      if (!mounted) return;

      // Si es null, significa que no hay token válido o fue revocado en backend
      if (status == null) {
        await _handleBackToStart();
        return;
      }

      if (status == UserVerificationStatus.VERIFIED) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else if (status == UserVerificationStatus.REJECTED) {
        _showSnackBar(
          'Documentos rechazados. Contacta a soporte.',
          isError: true,
        );
      }
    } catch (e) {
      debugPrint("Error verificando estado: $e");
    }
  }

  Future<void> _handleBackToStart() async {
    setState(() => _isLoading = true);
    await _authService.logout();
    if (!mounted) return;

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
      // SOLUCIÓN A PRUEBA DE BALAS PARA EL SCROLL
      body: RefreshIndicator(
        onRefresh: _checkStatusSilent,
        color: Colors.green,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icono
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
                      child: const Icon(
                        Icons.inventory_rounded,
                        size: 80,
                        color: Color.fromARGB(255, 10, 4, 74),
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
                      "Hemos recibido tus documentos. El equipo administrativo validará la información para habilitarte en la plataforma.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(8),
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

                    const SizedBox(height: 48),

                    // Botón
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _handleBackToStart,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: Color.fromARGB(255, 7, 3, 54),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
