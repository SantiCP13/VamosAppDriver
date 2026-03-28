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
  // Controladores
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePass = true;
  int _currentStep = 0; // 0: Email, 1: OTP, 2: New Password
  int _resendTimer = 0; // Segundos restantes
  bool _canResend = true;

  void _startResendTimer() {
    setState(() {
      _resendTimer = 60; // Espera de 1 minuto
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

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.cancel_outlined : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: GoogleFonts.poppins())),
          ],
        ),
        backgroundColor: isError
            ? const Color(0xFFE53935)
            : AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  // Instancia del servicio

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnack("Ingresa un correo válido", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.sendPasswordResetCode(email);

      // 🔥 AGREGA ESTA LÍNEA AQUÍ PARA QUITAR EL ERROR:
      _startResendTimer();

      setState(() => _isLoading = false);
      _showSnack("Código enviado a tu correo.");

      // Solo avanzamos de página si estamos en el paso 0 (Email)
      if (_currentStep == 0) {
        _nextPage();
      }
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

    if (p1.isEmpty || p1.length < 6) {
      _showSnack(
        "La contraseña debe tener al menos 6 caracteres",
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
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentStep++);
  }

  // --- ESTILOS VISUALES ---

  InputDecoration _getInputStyle({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(
        fontSize: 14,
        color: Colors.grey.shade600,
      ),
      prefixIcon: Icon(icon, size: 20, color: AppColors.primaryGreen),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      suffixIcon: suffixIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: BackButton(
          color: Colors.black,
          onPressed: () {
            if (_currentStep > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Barra de progreso
            if (_currentStep < 3)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_currentStep + 1) / 3,
                    backgroundColor: Colors.grey.shade100,
                    color: AppColors.primaryGreen,
                    minHeight: 4,
                  ),
                ),
              ),

            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildEmailStep(),
                  _buildOtpStep(),
                  _buildNewPasswordStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS DE PASOS ---

  Widget _buildEmailStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            "Recuperar cuenta",
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryGreen,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 40),
            child: Text(
              "Ingresa tu correo registrado en VAMOS APP Driver.",
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
            ),
          ),

          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: GoogleFonts.poppins(),
            decoration: _getInputStyle(
              label: "Correo electrónico",
              icon: Icons.alternate_email,
            ),
          ),

          const SizedBox(height: 50),
          _buildButton("Enviar Código", _sendCode),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            "Verifica tu identidad",
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryGreen,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 40),
            child: Text(
              "Hemos enviado un código de 6 dígitos al correo ${_emailController.text}",
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
            ),
          ),

          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 24,
              letterSpacing: 8,
              fontWeight: FontWeight.w600,
            ),
            decoration:
                _getInputStyle(
                  label: "Código de seguridad",
                  icon: Icons.lock_clock_outlined,
                ).copyWith(
                  counterText: "",
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                ),
          ),

          const SizedBox(height: 20),

          // Busca esta parte en tu ForgotPasswordScreen.dart:
          Center(
            child: TextButton(
              onPressed: _canResend
                  ? _sendCode
                  : null, // Desactivado si no puede reenviar
              child: Text(
                _canResend
                    ? "¿No recibiste el código? Reenviar"
                    : "Reenviar en $_resendTimer s",
                style: GoogleFonts.poppins(
                  color: _canResend ? AppColors.primaryGreen : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 30),
          _buildButton("Verificar Código", _verifyCode),
        ],
      ),
    );
  }

  Widget _buildNewPasswordStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Text(
            "Nueva contraseña",
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryGreen,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0, bottom: 40),
            child: Text(
              "Crea una contraseña segura para proteger tu cuenta de conductor.",
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
            ),
          ),

          TextField(
            controller: _passController,
            obscureText: _obscurePass,
            style: GoogleFonts.poppins(),
            decoration: _getInputStyle(
              label: "Nueva contraseña",
              icon: Icons.lock_outline,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: _confirmPassController,
            obscureText: _obscurePass,
            style: GoogleFonts.poppins(),
            decoration: _getInputStyle(
              label: "Confirmar contraseña",
              icon: Icons.verified_user_outlined,
            ),
          ),

          const SizedBox(height: 50),
          _buildButton("Actualizar Contraseña", _changePassword),
        ],
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 4,
          // Corrección aplicada aquí también
          shadowColor: AppColors.primaryGreen.withValues(alpha: 0.4),
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
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
