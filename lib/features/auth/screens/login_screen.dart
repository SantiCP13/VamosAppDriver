import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';

// Pantallas destino
import '../../home/screens/home_screen.dart';
import 'verification_check_screen.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/services/storage_service.dart';
import 'splash_screen.dart';
import '../../../core/utils/device_helper.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  final _authService = DriverAuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isBioAvailable = false;
  bool _hasSavedCredentials = false;
  bool _isEmailVerified = false;
  bool _checkingEmail = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
    _checkBioSupport();
  }

  Future<void> _checkBioSupport() async {
    final isAvailable = await sl<BiometricService>().isAvailable();

    if (mounted) {
      setState(() {
        _isBioAvailable = isAvailable;
      });
    }
  }

  Future<void> _loadSavedEmail() async {
    final savedEmail = await sl<StorageService>().getBiometricEmail();
    // 🟢 CORREGIDO: Evitamos pre-rellenar o marcar la casilla si el valor guardado es vacío
    if (savedEmail != null && savedEmail.isNotEmpty && mounted) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      _showSnack("Ingresa tu correo", isError: true);
      return;
    }

    // PASO 1: VERIFICAR CUENTA EN EL BACKEND
    if (!_isEmailVerified) {
      setState(() => _checkingEmail = true);
      try {
        final deviceId = await DeviceHelper.getId();
        await _authService.checkAccount(email, deviceId);

        final storage = sl<StorageService>();
        // 🟢 CONSULTA POR CUENTA ESPECÍFICA
        final savedPass = await storage.getAccountPassword(email);
        final bioEnabled = await storage.isBiometricEnabledForAccount(email);

        setState(() {
          _isEmailVerified = true;
          _checkingEmail = false;
          _hasSavedCredentials = (savedPass != null && bioEnabled == true);
        });
      } catch (e) {
        setState(() => _checkingEmail = false);
        _showSnack(e.toString().replaceAll('Exception: ', ''), isError: true);
      }
      return;
    }

    // PASO 2: LOGIN MANUAL
    if (_passwordController.text.isEmpty) {
      _showSnack("Ingresa tu contraseña", isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final password = _passwordController.text.trim();
      final deviceName = await DeviceHelper.getName();
      final deviceId = await DeviceHelper.getId();

      final user = await _authService.login(
        email,
        password,
        deviceId,
        deviceName,
      );

      final storage = sl<StorageService>();

      // 🟢 SE GUARDA SIEMPRE LA CONTRASEÑA EN EL DISPOSITIVO (ENCRIPTADA)
      // Esto asegura que si el usuario activa la huella desde el perfil,
      // la app ya tiene su credencial enlazada y el botón biométrico funcionará.
      await storage.saveAccountPassword(email, password);

      if (_rememberMe) {
        await storage.saveBiometricEmail(email);
        await storage.setBiometricEnabledForAccount(email, true);
      } else {
        await storage.saveBiometricEmail("");
        await storage.setBiometricEnabledForAccount(email, false);
      }

      if (!mounted) return;
      _navigateBasedOnStatus(user);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleBiometricLogin() async {
    final storage = sl<StorageService>();
    final bioService = sl<BiometricService>();

    final enteredEmail = _emailController.text.trim();
    // 🟢 OPTIMIZADO: SE EXTRAE LA CONTRASEÑA ENLAZADA ESTRICTAMENTE A ESTE EMAIL
    final savedPass = await storage.getAccountPassword(enteredEmail);

    if (savedPass == null || enteredEmail.isEmpty) {
      _showSnack("Error de credenciales. Usa tu contraseña.", isError: true);
      return;
    }

    final authenticated = await bioService.authenticate();
    if (authenticated) {
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SplashScreen(
            logoPath: 'assets/images/logo.png',
            isLoader: true,
            isDark: true,
          ),
        ),
      );

      try {
        final deviceId = await DeviceHelper.getId();
        final deviceName = await DeviceHelper.getName();

        final user = await _authService.login(
          enteredEmail,
          savedPass,
          deviceId,
          deviceName,
        );

        if (!mounted) return;
        Navigator.pop(context);
        _navigateBasedOnStatus(user);
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context);
        _showSnack(
          "Sesión expirada. Por favor usa tu contraseña.",
          isError: true,
        );
      }
    }
  }

  void _navigateBasedOnStatus(User user) {
    if (user.verificationStatus == UserVerificationStatus.VERIFIED) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else if (user.verificationStatus == UserVerificationStatus.PENDING ||
        user.verificationStatus == UserVerificationStatus.UNDER_REVIEW ||
        user.verificationStatus == UserVerificationStatus.DOCS_UPLOADED) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const VerificationCheckScreen()),
        (route) => false,
      );
    } else {
      _showSnack(
        "Tu cuenta requiere revisión. Contacta a soporte.",
        isError: true,
      );
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.montserrat(color: Colors.white)),
        backgroundColor: isError ? Colors.redAccent : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D121F),
      body: Stack(
        children: [
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
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Spacer(flex: 2),
                            Hero(
                              tag: 'logo',
                              createRectTween: (begin, end) {
                                return MaterialRectArcTween(
                                  begin: begin,
                                  end: end,
                                );
                              },
                              child: Image.asset(
                                'assets/images/logo.png',
                                height: 120,
                              ),
                            ),
                            const SizedBox(height: 40),
                            Text(
                              "BIENVENIDO CONDUCTOR",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.montserrat(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryGreen,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Ingresa tus credenciales para continuar",
                              style: GoogleFonts.montserrat(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 50),
                            _buildLoginForm(),
                            const SizedBox(height: 40),
                            _buildLoginButton(),
                            const SizedBox(height: 30),
                            _buildLegalNote(),
                            const Spacer(flex: 3),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                style: IconButton.styleFrom(
                  // ignore: deprecated_member_use
                  backgroundColor: Colors.white.withOpacity(0.1),
                  padding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              _buildDarkInput(
                controller: _emailController,
                label: "Correo Electrónico",
                icon: Icons.email_outlined,
                readOnly: _isEmailVerified,
                keyboardType: TextInputType.emailAddress,
                suffixIcon: _isEmailVerified
                    ? IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.white54,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _isEmailVerified = false;
                            _hasSavedCredentials = false;
                            _passwordController.clear();
                          });
                        },
                      )
                    : null,
              ),

              if (_isEmailVerified) ...[
                const SizedBox(height: 15),
                _buildDarkInput(
                  controller: _passwordController,
                  label: "Contraseña",
                  icon: Icons.lock_outline,
                  isPassword: true,
                  obscure: _obscurePassword,
                  focusNode: _passwordFocusNode,
                  onToggle: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          transitionDuration: const Duration(milliseconds: 600),
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  SplashScreen(
                                    logoPath: 'assets/images/logo.png',
                                    nextRoute: '/forgot_password',
                                    email: _emailController.text.trim(),
                                    isDark: true,
                                  ),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                        ),
                      );
                    },
                    child: Text(
                      "¿Olvidaste tu contraseña?",
                      style: GoogleFonts.montserrat(
                        color: AppColors.primaryGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],

              if (!_isEmailVerified) ...[
                const SizedBox(height: 15),
                Row(
                  children: [
                    Theme(
                      data: ThemeData(unselectedWidgetColor: Colors.white54),
                      child: Checkbox(
                        value: _rememberMe,
                        activeColor: AppColors.primaryGreen,
                        onChanged: (val) => setState(() => _rememberMe = val!),
                      ),
                    ),
                    Text(
                      "Recordar correo",
                      style: GoogleFonts.montserrat(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Colors.white12),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegisterScreen(),
                      ),
                    );
                  },
                  child: Text.rich(
                    TextSpan(
                      text: "¿No tienes cuenta? ",
                      style: GoogleFonts.montserrat(
                        color: Colors.white60,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(
                          text: "Regístrate aquí",
                          style: TextStyle(
                            color: AppColors.primaryGreen,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryGreen.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
              ),
              child: _isLoading || _checkingEmail
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                      _isEmailVerified ? "INICIAR SESIÓN" : "CONTINUAR",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 1.5,
                      ),
                    ),
            ),
          ),
        ),
        if (_isEmailVerified && _isBioAvailable && _hasSavedCredentials) ...[
          const SizedBox(width: 15),
          GestureDetector(
            onTap: _isLoading ? null : _handleBiometricLogin,
            child: Container(
              height: 62,
              width: 62,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primaryGreen.withValues(alpha: 0.2),
                ),
              ),
              child: const Icon(
                Icons.fingerprint,
                color: AppColors.primaryGreen,
                size: 32,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLegalNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text.rich(
        TextSpan(
          text: "Al iniciar sesión, aceptas nuestra ",
          children: [
            TextSpan(
              text: "Política de Tratamiento de Datos",
              style: TextStyle(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
            const TextSpan(text: " y los "),
            TextSpan(
              text: "Términos de Servicio",
              style: TextStyle(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        style: GoogleFonts.montserrat(
          // ignore: deprecated_member_use
          color: Colors.white.withOpacity(0.4),
          fontSize: 11,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildDarkInput({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggle,
    TextInputType? keyboardType,
    FocusNode? focusNode,
    bool readOnly = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          focusNode: focusNode,
          keyboardType: keyboardType,
          readOnly: readOnly,
          style: GoogleFonts.montserrat(color: Colors.white),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.primaryGreen, size: 20),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white38,
                    ),
                    onPressed: onToggle,
                  )
                : suffixIcon,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 18,
              horizontal: 15,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: AppColors.primaryGreen,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
