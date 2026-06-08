// lib/features/home/screens/support_screen.dart

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  final String whatsappNumber =
      "+573112321539"; // Reemplaza por tu número de conductor soporte
  final String supportEmail = "gerencia@vamosapp.com.co";
  final Color darkBg = const Color(0xFF0B0F19);
  final Color cardColor = const Color(0xFF161B2E);

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('No se pudo abrir $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      body: Stack(
        children: [
          // Fondo decorativo con resplandor superior sutil
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryGreen.withValues(alpha: 0.05),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildCustomAppBar(context),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),

                        // Header ilustrativo
                        _buildSupportHeader(),

                        const SizedBox(height: 40),

                        _sectionLabel("CANALES DE CONTACTO"),
                        const SizedBox(height: 15),

                        // Tarjeta WhatsApp
                        _buildGlassSupportCard(
                          title: "Chat de Conductores",
                          subtitle: "Asistencia técnica vía WhatsApp",
                          caption: "Respuesta en < 5 min",
                          icon: Icons.chat_bubble_rounded,
                          accentColor: AppColors.primaryGreen,
                          onTap: () => _launchURL(
                            "https://wa.me/$whatsappNumber?text=Hola VAMOS, necesito ayuda con mi cuenta de conductor.",
                          ),
                          isLive: true,
                        ),

                        const SizedBox(height: 16),

                        // Tarjeta Email
                        _buildGlassSupportCard(
                          title: "Correo Electrónico",
                          subtitle: supportEmail,
                          caption: "Casos de facturación y turnos",
                          icon: Icons.alternate_email_rounded,
                          accentColor: AppColors.primaryGreen,
                          onTap: () => _launchURL("mailto:$supportEmail"),
                        ),

                        const SizedBox(height: 40),

                        // Nota de seguridad estilo banner
                        _buildSecurityNote(),

                        const SizedBox(height: 50),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(12),
            ),
          ),
          Text(
            "CENTRO DE AYUDA",
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSupportHeader() {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
            const Icon(
              Icons.headset_mic_rounded,
              size: 60,
              color: AppColors.primaryGreen,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          "¿Cómo podemos\nayudarte hoy?",
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Nuestro equipo de soporte técnico está disponible\npara ayudarte a optimizar tus turnos y ganancias.",
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white54),
        ),
      ],
    );
  }

  Widget _sectionLabel(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: GoogleFonts.montserrat(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.primaryGreen,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildGlassSupportCard({
    required String title,
    required String subtitle,
    required String caption,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
    bool isLive = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: accentColor, size: 28),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          if (isLive) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF25D366),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        caption,
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white30,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Colors.white30,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.primaryGreen),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Nunca solicitaremos tus contraseñas o códigos de seguridad para liberar turnos o pagos.",
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.white54,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
