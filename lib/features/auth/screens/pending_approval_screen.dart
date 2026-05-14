import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import '../../../core/theme/app_colors.dart';
import 'splash_screen.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D121F),
      body: Stack(
        children: [
          // Fondo Radial Dark
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.45),
                radius: 1.8,
                colors: [Color(0xFF25335A), Color(0xFF0D121F)],
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Spacer(),

                  // Icono Central con Resplandor Verde
                  _buildAnimatedIcon(),

                  const SizedBox(height: 40),

                  Text(
                    "Perfil en Revisión",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primaryGreen,
                      letterSpacing: -1,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    "Estamos validando tus documentos y antecedentes legales. Recibirás una notificación cuando tu cuenta sea activada.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.6),
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Info Card Glassmorphism
                  _buildStatusCard(),

                  const Spacer(),

                  // Botón Entendido
                  _buildActionButton(context),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedIcon() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: const Icon(
        Icons.verified_user_rounded,
        size: 80,
        color: AppColors.primaryGreen,
      ),
    );
  }

  Widget _buildStatusCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color: AppColors.primaryGreen,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Tiempo de respuesta",
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Nuestro equipo legal revisará tu solicitud en un plazo máximo de 24 a 48 horas hábiles.",
                style: GoogleFonts.montserrat(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: () {
          // Usamos pushAndRemoveUntil para limpiar todo el historial de pantallas
          Navigator.pushAndRemoveUntil(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 600),
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const SplashScreen(
                    logoPath: 'assets/images/logo.png',
                    nextRoute:
                        '', // Al dejarlo vacío o diferente a /home /register, irá al Welcome por defecto
                    isDark: true, // Mantenemos el estilo Dark de Driver
                  ),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(opacity: animation, child: child);
                  },
            ),
            (route) => false,
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: Text(
          "VOLVER AL INICIO",
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
