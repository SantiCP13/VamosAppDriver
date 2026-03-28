import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Asegúrate de que estas rutas sean correctas según tu estructura de carpetas
import '../../../core/theme/app_colors.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Pantallas de navegación
import 'documents_upload_screen.dart';
import 'verification_check_screen.dart';
import '../../home/screens/home_screen.dart';
import '../screens/forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // --- CONTROLADORES ---
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _authService = DriverAuthService();
  final _passwordFocusNode = FocusNode();
  bool _rememberMe = false;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final savedEmail = await _storage.read(key: 'saved_email');
    if (savedEmail != null && savedEmail.isNotEmpty) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }

  // --- ESTADOS DE LA UI ---
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  // --- MODAL INAMOVIBLE ---
  void _showLoadingModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false, // Evita que se cierre con el botón atrás de Android
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryGreen),
        ),
      ),
    );
  }

  void _closeLoadingModal() {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  /// LÓGICA CENTRAL DE LOGIN REAL
  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showSnack("Por favor ingresa un correo válido", isError: true);
      return;
    }

    if (password.isEmpty) {
      _showSnack("Ingresa tu contraseña", isError: true);
      _passwordFocusNode.requestFocus();
      return;
    }

    _showLoadingModal();

    try {
      final user = await _authService.login(email, password);

      if (_rememberMe) {
        await _storage.write(key: 'saved_email', value: email);
      } else {
        await _storage.delete(key: 'saved_email');
      }

      if (!mounted) return;
      _closeLoadingModal();

      _navigateBasedOnStatus(user);
    } catch (e) {
      if (!mounted) return;
      _closeLoadingModal();

      // Extraemos el mensaje limpio (Laravel envía "Credenciales inválidas")
      String msg = e.toString().replaceAll('Exception: ', '');

      // Mostramos el SnackBar rojo que ya tienes configurado
      _showSnack(msg, isError: true);

      // Si el error es de credenciales, limpiamos la clave y pedimos foco
      if (msg.toLowerCase().contains('credenciales') ||
          msg.toLowerCase().contains('inválidas') ||
          msg.toLowerCase().contains('contraseña')) {
        _passwordController.clear();
        _passwordFocusNode.requestFocus();
      }
    }
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
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Login Driver",
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Ingresa tus credenciales para iniciar ruta",
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 40),

                      // --- CAMPO EMAIL ---
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        style: GoogleFonts.poppins(color: Colors.black),
                        decoration: _getInputStyle(
                          label: "Correo electrónico",
                          icon: Icons.alternate_email,
                        ),
                        onSubmitted: (_) => FocusScope.of(
                          context,
                        ).requestFocus(_passwordFocusNode),
                      ),

                      const SizedBox(height: 20),

                      // --- CAMPO PASSWORD ---
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
                        onSubmitted: (_) => _handleLogin(),
                      ),

                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // --- NUEVO: CHECKBOX RECORDAR (FLEXIBLE) ---
                          Expanded(
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    activeColor: AppColors.primaryGreen,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    onChanged: (val) {
                                      setState(
                                        () => _rememberMe = val ?? false,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Recordar correo",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // --- BOTÓN ORIGINAL (ACORTADO) ---
                          TextButton(
                            onPressed: () {
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
                        ],
                      ),

                      const Spacer(),

                      // --- BOTÓN PRINCIPAL ---
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _handleLogin,
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
                          child: Text(
                            "Iniciar Sesión",
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
