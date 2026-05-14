import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'splash_screen.dart'; // Importante
import 'dart:ui';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.checkAuthStatus();
    if (mounted) setState(() => _isLoading = false);
  }

  void _navigateTo(Widget screen) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeIn),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.darkBlue,
        body: _buildLoadingState(),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.45),
                radius: 1.8,
                colors: [Color(0xFF25335A), Color(0xFF0D121F)],
              ),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const SizedBox(
                        height: 100,
                      ), // Espaciado manual para control total
                      _buildFadeIn(
                        delay: 0,
                        child: Hero(
                          tag: 'logo',
                          // ESTO ACTIVA EL MOVIMIENTO EN CURVA:
                          createRectTween: (begin, end) {
                            return MaterialRectArcTween(begin: begin, end: end);
                          },
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 220,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                      _buildFadeIn(
                        delay: 200,
                        child: Text(
                          "Gestiona tus servicios corporativos y cumple la normativa legal con tecnología de punta.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.montserrat(
                            fontSize: 15,
                            // ignore: deprecated_member_use
                            color: Colors.white.withOpacity(0.6),
                            height: 1.6,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 80),
                      Text(
                        "PANEL DE ACCESO",
                        style: GoogleFonts.montserrat(
                          fontSize: 13, // Igualado a User
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(height: 25),
                      _buildFadeIn(
                        delay: 400,
                        child: _buildRoleButton(
                          label: "Iniciar Sesión",
                          subLabel: "Ya soy parte de la flota",
                          icon: Icons.vpn_key_rounded,
                          isPrimary: true,
                          destination: const LoginScreen(),
                        ),
                      ),
                      _buildFadeIn(
                        delay: 600,
                        child: _buildRoleButton(
                          label: "Registrarme",
                          subLabel: "Quiero unirme a Vamos",
                          icon: Icons.add_business_rounded,
                          isPrimary: false,
                          // CAMBIO AQUÍ: Enviamos a la SplashScreen
                          destination: const SplashScreen(
                            logoPath: 'assets/images/logo.png',
                            nextRoute: '/register',
                            isDark: true, // Estilo Driver
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleButton({
    required String label,
    required String subLabel,
    required IconData icon,
    required Widget destination,
    required bool isPrimary,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          if (isPrimary)
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.25),
              blurRadius: 25,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 15,
            sigmaY: 15,
          ), // Desenfoque profundo tipo iOS
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: 0.15,
                ), // Brillo en el borde
                width: 1.5,
              ),
              // GRADIENTE PARA MANTENER EL COLOR VIVO
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isPrimary
                    ? [
                        AppColors.primaryGreen.withValues(
                          alpha: 0.8,
                        ), // Arriba más vivo
                        AppColors.primaryGreen.withValues(
                          alpha: 0.6,
                        ), // Abajo más traslúcido
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.1),
                        Colors.white.withValues(alpha: 0.05),
                      ],
              ),
            ),
            child: ElevatedButton(
              onPressed: () => _navigateTo(destination),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.transparent, // Fondo manejado por el Container
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                elevation: 0,
                shadowColor: Colors.transparent,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      icon,
                      size: 26,
                      color: isPrimary ? Colors.white : AppColors.primaryGreen,
                    ),
                  ),
                  const SizedBox(width: 25),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.montserrat(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          subLabel,
                          style: GoogleFonts.montserrat(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFadeIn({required int delay, required Widget child}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 800 + delay),
      curve: Curves.easeOutExpo,
      builder: (context, val, child) => Opacity(
        opacity: val,
        child: Transform.translate(
          offset: Offset(0, 30 * (1 - val)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/images/logo.png', width: 150),
          const SizedBox(height: 50),
          SizedBox(
            // <--- QUITA EL 'const' DE AQUÍ
            width: 160,
            child: LinearProgressIndicator(
              color: AppColors.primaryGreen,
              backgroundColor: Colors.white.withValues(
                alpha: 0.1,
              ), // Esto ya no dará error
              minHeight: 2,
            ),
          ),
        ],
      ),
    );
  }
}
