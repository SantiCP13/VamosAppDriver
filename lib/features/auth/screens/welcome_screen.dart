import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // ✅ AHORA SÍ VA A FUNCIONAR
import 'login_screen.dart';
import 'register_screen.dart';

// 🎨 COLORES DEL ECOSISTEMA DRIVER
class AppColors {
  static const Color primaryDark = Color(0xFF021526); // Fondo Oscuro
  static const Color primaryGreen = Color(0xFF7BCC29); // Verde Marca
  static const Color textWhite = Colors.white;
  static const Color textGrey = Color(0xFFB0BEC5);
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // --- CONTENIDO PRINCIPAL ---
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // 1. BRANDING
                  Hero(
                    tag: 'logo',
                    child: Image.asset(
                      'assets/logo.png',
                      height: 220, // Ajusta el tamaño aquí
                      fit: BoxFit.contain,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 2. PROPUESTA DE VALOR (CON POPPINS ✅)
                  Text(
                    "VAMOS APP Driver",
                    style: GoogleFonts.poppins(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Gestiona tus viajes y cumple la normativa legal colombiana con seguridad.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: const Color.fromARGB(255, 53, 53, 53),
                      height: 1.5,
                    ),
                  ),

                  const Spacer(flex: 3),

                  Text(
                    "SELECCIONA UNA OPCIÓN",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: const Color.fromARGB(255, 1, 5, 39),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- BOTONES DE ACCIÓN ---

                  // OPCIÓN A: INICIAR SESIÓN
                  _buildRoleButton(
                    context,
                    label: "Iniciar Sesión",
                    subLabel: "Ya tengo cuenta activa",
                    icon: Icons.login_rounded,
                    isPrimary: true,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // OPCIÓN B: REGISTRO
                  _buildRoleButton(
                    context,
                    label: "Registrarme",
                    subLabel: "Quiero unirme a la flota",
                    icon: Icons.person_add_alt_1_rounded,
                    isPrimary: false,
                    // 👇 CAMBIA EL COLOR AQUÍ
                    backgroundColor: const Color.fromARGB(255, 8, 2, 53),
                    textColor: Colors.white,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegisterScreen(),
                      ),
                    ),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Botón de Selección de Rol
  Widget _buildRoleButton(
    BuildContext context, {
    required String label,
    required String subLabel,
    required IconData icon,
    required VoidCallback onPressed,
    required bool isPrimary,
    // ✨ NUEVOS PARÁMETROS OPCIONALES
    Color? backgroundColor,
    Color? textColor,
  }) {
    // Si pasas un color, lo usa. Si no, usa la lógica original de isPrimary.
    final finalBgColor =
        backgroundColor ?? (isPrimary ? AppColors.primaryGreen : Colors.white);
    final finalFgColor =
        textColor ?? (isPrimary ? Colors.white : AppColors.primaryDark);

    // El borde solo aparece si no es primary y no tiene color de fondo personalizado
    final borderSide = (isPrimary || backgroundColor != null)
        ? BorderSide.none
        : const BorderSide(color: AppColors.primaryGreen, width: 0);

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: finalBgColor, // Usamos el color calculado
          foregroundColor: finalFgColor, // Usamos el texto calculado
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          elevation: isPrimary ? 3 : 0,
          side: borderSide,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                // Ajustamos el fondo del ícono según el color del botón
                color: finalFgColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 24, color: finalFgColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: finalFgColor, // Forzamos color de texto
                    ),
                  ),
                  Text(
                    subLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      // Hacemos el subtítulo un poco más transparente
                      color: finalFgColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: finalFgColor,
            ),
          ],
        ),
      ),
    );
  }
}
