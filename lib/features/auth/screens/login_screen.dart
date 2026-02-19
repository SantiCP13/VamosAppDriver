import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Asegúrate de que estas rutas sean correctas según tu estructura de carpetas
import '../../../core/theme/app_colors.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';

// Pantallas de navegación
import 'documents_upload_screen.dart';
import 'verification_check_screen.dart';
import 'register_screen.dart'; // Asumo que existe o se creará
import '../../home/screens/home_screen.dart';
import '../screens/forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // --- CONTROLADORES ---
  // Mantenemos los valores por defecto para facilitar tus pruebas
  final _emailController = TextEditingController(text: "ok@test.com");
  final _passwordController = TextEditingController(text: "123456");

  // Servicio de autenticación del Driver
  final _authService = DriverAuthService();
  final _passwordFocusNode = FocusNode();

  // --- ESTADOS DE LA UI ---
  bool _isLoading = false;
  bool _emailExists = false; // Controla la animación de mostrar el password
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  /// LÓGICA CENTRAL
  Future<void> _handleContinue() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showSnack("Por favor ingresa un correo válido", isError: true);
      return;
    }

    if (_emailExists && _passwordController.text.isEmpty) {
      _showSnack("Ingresa tu contraseña", isError: true);
      _passwordFocusNode.requestFocus();
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (!_emailExists) {
        // --- FASE 1: VALIDACIÓN LIMPIA ---
        final exists = await _mockLoginValidation(email);

        if (!mounted) return;
        setState(() => _isLoading = false);

        if (exists) {
          setState(() => _emailExists = true);
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) {
              FocusScope.of(context).requestFocus(_passwordFocusNode);
            }
          });
        } else {
          _showRegisterDialog(email);
        }
      } else {
        // --- FASE 2: LOGIN REAL ---
        final user = await _authService.login(
          email,
          _passwordController.text.trim(),
        );

        if (!mounted) return;
        setState(() => _isLoading = false);
        _navigateBasedOnStatus(user);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      String msg = e.toString().replaceAll('Exception: ', '');
      _showSnack(msg, isError: true);

      if (msg.toLowerCase().contains('password') ||
          msg.toLowerCase().contains('contraseña')) {
        _passwordController.clear();
        _passwordFocusNode.requestFocus();
      }
    }
  }

  /// Simula la latencia y extrae la lógica de verificación
  Future<bool> _mockLoginValidation(String email) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return !email.startsWith("nuevo");
  }

  void _navigateBasedOnStatus(User user) {
    Widget nextScreen;

    switch (user.verificationStatus) {
      case UserVerificationStatus.VERIFIED:
        nextScreen = const HomeScreen();
        break;

      case UserVerificationStatus.CREATED:
      case UserVerificationStatus.PENDING:
        nextScreen = const DocumentsUploadScreen();
        break;

      case UserVerificationStatus.DOCS_UPLOADED:
      case UserVerificationStatus.UNDER_REVIEW:
        nextScreen = const VerificationCheckScreen();
        break;

      case UserVerificationStatus.REJECTED:
      case UserVerificationStatus.REVOKED:
        _showSnack(
          'Tu cuenta ha sido rechazada/revocada. Contacta soporte.',
          isError: true,
        );
        _authService.logout();
        return; // No navegamos
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => nextScreen),
      (route) => false,
    );
  }

  // --- UI HELPERS (Copiados del User App) ---

  void _showRegisterDialog(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cuenta no encontrada"),
        content: Text("El conductor con correo $email no está registrado."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Reintentar",
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  // AQUÍ PASAS EL CORREO:
                  builder: (_) => RegisterScreen(emailPreIngresado: email),
                ),
              );
            },
            child: const Text(
              "Registrarme",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 30, left: 40, right: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: isError
            ? const Color(0xFFE53935)
            : AppColors.primaryGreen,
        elevation: 6,
        content: Row(
          children: [
            Icon(
              isError ? Icons.cancel_outlined : Icons.check_circle_outline,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

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
        leading: _emailExists
            ? BackButton(
                color: Colors.black,
                onPressed: () {
                  setState(() {
                    _emailExists = false;
                    _passwordController.clear();
                  });
                },
              )
            : null, // Sin botón de atrás en la fase inicial
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TÍTULO
                Text(
                  _emailExists ? "Hola de nuevo Driver!" : "Login Driver",
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),

                if (_emailExists)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 30),
                    child: Text(
                      "Confirma tu identidad para iniciar ruta",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 50),

                // --- CAMPO EMAIL ---
                TextField(
                  controller: _emailController,
                  readOnly: _emailExists,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  style: GoogleFonts.poppins(
                    color: _emailExists ? Colors.grey.shade700 : Colors.black,
                  ),
                  decoration: _getInputStyle(
                    label: "Correo electrónico",
                    icon: Icons.alternate_email,
                    suffixIcon: _emailExists
                        ? IconButton(
                            tooltip: "Editar correo",
                            icon: const Icon(
                              Icons.edit,
                              size: 20,
                              color: AppColors.primaryGreen,
                            ),
                            onPressed: () {
                              setState(() {
                                _emailExists = false;
                                _passwordController.clear();
                              });
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (_) {
                    if (!_emailExists) _handleContinue();
                  },
                ),

                // --- CAMPO PASSWORD (ANIMADO) ---
                AnimatedCrossFade(
                  firstChild: Container(height: 0),
                  secondChild: Column(
                    children: [
                      const SizedBox(height: 20),
                      TextField(
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        style: GoogleFonts.poppins(),
                        decoration: _getInputStyle(
                          label: "Contraseña",
                          icon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _handleContinue(),
                      ),

                      // Link de Olvidé contraseña (Opcional para driver)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            // AQUÍ ESTA EL CAMBIO:
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ForgotPasswordScreen(
                                  emailPreloadded: _emailController.text,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            "¿Olvidaste tu contraseña?",
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  crossFadeState: _emailExists
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                  sizeCurve: Curves.easeInOut,
                ),

                const SizedBox(height: 30),

                // --- BOTÓN PRINCIPAL ---
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      elevation: 4,
                      shadowColor: AppColors.primaryGreen.withValues(
                        alpha: 0.4,
                      ),
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
                            _emailExists ? "Iniciar Sesión" : "Continuar",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
