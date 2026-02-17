import 'package:flutter/material.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';
import 'documents_upload_screen.dart';
import 'verification_check_screen.dart';
import '../../home/screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
  // CORRECCIÓN: super.key
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController(text: "ok@test.com");
  final _passCtrl = TextEditingController(text: "123456");
  final _authService = DriverAuthService();

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _authService.login(
        _emailCtrl.text.trim(),
        _passCtrl.text.trim(),
      );

      if (!mounted) return;
      _navigateBasedOnStatus(user);
    } catch (e) {
      setState(
        () => _errorMessage = e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateBasedOnStatus(User user) {
    if (!mounted) return;

    Widget nextScreen;

    switch (user.verificationStatus) {
      // 1. VERIFICADO
      case UserVerificationStatus.VERIFIED:
        nextScreen = const HomeScreen();
        break;

      // 2. FALTAN PAPELES
      case UserVerificationStatus.CREATED:
      case UserVerificationStatus.PENDING:
        nextScreen = const DocumentsUploadScreen();
        break;

      // 3. EN REVISIÓN (Aquí incluimos DOCS_UPLOADED y UNDER_REVIEW)
      case UserVerificationStatus.DOCS_UPLOADED:
      case UserVerificationStatus.UNDER_REVIEW:
        nextScreen = const VerificationCheckScreen();
        break;

      // 4. RECHAZADO / BLOQUEADO
      case UserVerificationStatus.REJECTED:
      case UserVerificationStatus.REVOKED:
        setState(() {
          _errorMessage = 'Tu cuenta ha sido rechazada. Contacta a soporte.';
        });
        _authService.logout();
        return;

      // BORRA EL "default:" QUE TENÍAS AQUÍ ABAJO
      // Dart sabe que ya cubriste las 7 opciones del Enum.
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => nextScreen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conductor'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text(
              'Ingresa tus credenciales',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),

            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Correo Electrónico',
                hintText: 'ej. conductor@vamos.com',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email_outlined),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleLogin,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('ENTRAR'),
              ),
            ),

            const SizedBox(height: 20),
            const Text(
              'Tips Desarrollo:\nUsa "ok@test.com" para entrar.\nUsa "wait@test.com" para ver bloqueo.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
