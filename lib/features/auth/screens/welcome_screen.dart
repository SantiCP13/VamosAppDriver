// lib/features/auth/screens/welcome_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart'; // 🟢 NUEVA IMPORTACIÓN
import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'splash_screen.dart';
import 'dart:ui';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoading = true;
  String _appVersion = "v0.0.0"; // 🟢 VARIABLE DINÁMICA DE VERSIÓN

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.checkAuthStatus();
    await _loadAppVersion(); // 🟢 OBTENER VERSIÓN DEL SISTEMA
    if (mounted) setState(() => _isLoading = false);
  }

  // 🟢 MÉTODO PARA LEER EL PUBSPEC DINÁMICAMENTE
  Future<void> _loadAppVersion() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion =
              "Versión ${packageInfo.version} (${packageInfo.buildNumber})";
        });
      }
    } catch (_) {}
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

  Future<void> _launchSupportWhatsApp() async {
    final Uri whatsappUri = Uri.parse(
      "https://wa.me/573112321539?text=Hola%20VAMOS,%20necesito%20soporte%20con%20la%20aplicaci%C3%B3n%20de%20Conductores.",
    );
    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        _showSupportErrorSnackBar();
      }
    } catch (e) {
      _showSupportErrorSnackBar();
    }
  }

  void _showSupportErrorSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "No se pudo abrir WhatsApp. Por favor, inténtalo de nuevo.",
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            const Spacer(flex: 2),
                            _buildFadeIn(
                              delay: 0,
                              child: Hero(
                                tag: 'logo',
                                createRectTween: (begin, end) {
                                  return MaterialRectArcTween(
                                    begin: begin,
                                    end: end,
                                  );
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
                                  color: Colors.white.withValues(alpha: 0.6),
                                  height: 1.6,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(height: 80),
                            Text(
                              "PANEL DE ACCESO",
                              style: GoogleFonts.montserrat(
                                fontSize: 13,
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
                                destination: const SplashScreen(
                                  logoPath: 'assets/images/logo.png',
                                  nextRoute: '/register',
                                  isDark: true,
                                ),
                              ),
                            ),

                            const Spacer(flex: 1),

                            _buildFadeIn(
                              delay: 800,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: TextButton.icon(
                                  onPressed: _launchSupportWhatsApp,
                                  icon: const Icon(
                                    Icons.support_agent_rounded,
                                    color: AppColors.primaryGreen,
                                    size: 22,
                                  ),
                                  label: Text(
                                    "Contactar a Soporte",
                                    style: GoogleFonts.montserrat(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Colors.white30,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 🟢 NUEVO: TEXTO DINÁMICO DE VERSIÓN AL PIE DE PÁGINA
                            Text(
                              _appVersion,
                              style: GoogleFonts.montserrat(
                                color: Colors.white30,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),

                            const Spacer(flex: 1),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
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
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isPrimary
                    ? [
                        AppColors.primaryGreen.withValues(alpha: 0.8),
                        AppColors.primaryGreen.withValues(alpha: 0.6),
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
                backgroundColor: Colors.transparent,
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
            width: 160,
            child: LinearProgressIndicator(
              color: AppColors.primaryGreen,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              minHeight: 2,
            ),
          ),
        ],
      ),
    );
  }
}
