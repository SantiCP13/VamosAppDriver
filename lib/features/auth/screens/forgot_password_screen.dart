import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../services/driver_auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? emailPreloadded;

  const ForgotPasswordScreen({super.key, this.emailPreloadded});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final PageController _pageController = PageController();
  final _authService = DriverAuthService();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePass = true;
  int _currentStep = 0;
  int _resendTimer = 0;
  bool _canResend = true;

  @override
  void initState() {
    super.initState();
    if (widget.emailPreloadded != null) {
      _emailController.text = widget.emailPreloadded!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passController.dispose();
    _confirmPassController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _resendTimer = 60;
      _canResend = false;
    });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendTimer--);
      if (_resendTimer <= 0) {
        setState(() => _canResend = true);
        return false;
      }
      return true;
    });
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.montserrat(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: isError ? Colors.redAccent : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // --- LÓGICA DE NEGOCIO ---

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnack("Ingresa un correo válido", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService.sendPasswordResetCode(email);
      _startResendTimer();
      setState(() => _isLoading = false);
      _showSnack("Código enviado a tu correo.");
      if (_currentStep == 0) _nextPage();
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  Future<void> _verifyCode() async {
    final code = _otpController.text.trim();
    if (code.length < 6) {
      _showSnack("El código debe tener 6 dígitos", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService.verifyPasswordResetCode(
        _emailController.text.trim(),
        code,
      );
      setState(() => _isLoading = false);
      _nextPage();
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  Future<void> _changePassword() async {
    final p1 = _passController.text;
    final p2 = _confirmPassController.text;
    if (p1.isEmpty || p1.length < 8) {
      _showSnack(
        "La contraseña debe tener al menos 8 caracteres",
        isError: true,
      );
      return;
    }
    if (p1 != p2) {
      _showSnack("Las contraseñas no coinciden", isError: true);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService.resetPassword(
        _emailController.text.trim(),
        _otpController.text.trim(),
        p1,
      );
      setState(() => _isLoading = false);
      _showSnack("¡Contraseña actualizada! Inicia sesión.");
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutExpo,
    );
    setState(() => _currentStep++);
  }

  // --- ESTILOS VISUALES (ESTILO DRIVER LOGIN) ---

  InputDecoration _getDarkInputStyle({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.montserrat(color: Colors.white54, fontSize: 13),
      prefixIcon: Icon(icon, color: AppColors.primaryGreen, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D121F),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () {
            if (_currentStep > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutExpo,
              );
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Stack(
        children: [
          // 1. FONDO RADIAL PREMIUM
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
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Barra de progreso estirada
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: (_currentStep + 1) / 3,
                      backgroundColor: Colors.white10,
                      color: AppColors.primaryGreen,
                      minHeight: 6,
                    ),
                  ),
                ),

                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildStepContainer(_buildEmailStep()),
                      _buildStepContainer(_buildOtpStep()),
                      _buildStepContainer(_buildNewPasswordStep()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContainer(Widget child) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: child,
    );
  }

  // --- WIDGETS DE PASOS ---

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        Text(
          "RECUPERACIÓN",
          style: GoogleFonts.montserrat(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryGreen,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Ingresa tu correo registrado para enviarte un código de seguridad.",
          style: GoogleFonts.montserrat(
            fontSize: 15,
            color: Colors.white70,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 40),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: GoogleFonts.montserrat(color: Colors.white),
          decoration: _getDarkInputStyle(
            label: "Correo electrónico",
            icon: Icons.alternate_email,
          ),
        ),
        const SizedBox(height: 50),
        _buildActionButton("ENVIAR CÓDIGO", _sendCode),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        Text(
          "VERIFICACIÓN",
          style: GoogleFonts.montserrat(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryGreen,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Hemos enviado el código al correo:",
          style: GoogleFonts.montserrat(fontSize: 14, color: Colors.white60),
        ),
        Text(
          _emailController.text,
          style: GoogleFonts.montserrat(
            fontSize: 15,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 40),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            fontSize: 28,
            letterSpacing: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          decoration: _getDarkInputStyle(
            label: "Código de 6 dígitos",
            icon: Icons.security_rounded,
          ).copyWith(counterText: ""),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton(
            onPressed: _canResend ? _sendCode : null,
            child: Text(
              _canResend
                  ? "¿No recibiste el código? REENVIAR"
                  : "Reenviar en $_resendTimer s",
              style: GoogleFonts.montserrat(
                color: _canResend ? AppColors.primaryGreen : Colors.white24,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(height: 30),
        _buildActionButton("VERIFICAR CÓDIGO", _verifyCode),
      ],
    );
  }

  Widget _buildNewPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 40),
        Text(
          "SEGURIDAD",
          style: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryGreen,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Crea una nueva contraseña segura para tu cuenta de conductor.",
          style: GoogleFonts.montserrat(fontSize: 15, color: Colors.white70),
        ),
        const SizedBox(height: 40),
        TextField(
          controller: _passController,
          obscureText: _obscurePass,
          style: GoogleFonts.montserrat(color: Colors.white),
          decoration: _getDarkInputStyle(
            label: "Nueva contraseña",
            icon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePass ? Icons.visibility_off : Icons.visibility,
                color: Colors.white38,
              ),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _confirmPassController,
          obscureText: _obscurePass,
          style: GoogleFonts.montserrat(color: Colors.white),
          decoration: _getDarkInputStyle(
            label: "Confirmar contraseña",
            icon: Icons.verified_user_outlined,
          ),
        ),
        const SizedBox(height: 50),
        _buildActionButton("ACTUALIZAR CONTRASEÑA", _changePassword),
      ],
    );
  }

  Widget _buildActionButton(String text, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                text,
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 1,
                ),
              ),
      ),
    );
  }
}
