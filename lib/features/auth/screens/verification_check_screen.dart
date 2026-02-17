import 'package:flutter/material.dart';
import '../../../core/models/user_model.dart';
import '../services/driver_auth_service.dart';
import '../../home/screens/home_screen.dart';

class VerificationCheckScreen extends StatefulWidget {
  const VerificationCheckScreen({super.key});

  @override
  State<VerificationCheckScreen> createState() =>
      _VerificationCheckScreenState();
}

class _VerificationCheckScreenState extends State<VerificationCheckScreen> {
  final DriverAuthService _authService = DriverAuthService();
  bool _checking = false;

  Future<void> _checkStatus() async {
    setState(() => _checking = true);
    try {
      // El servicio Mock cambiará internamente de UNDER_REVIEW a VERIFIED
      final status = await _authService.checkStatus();

      if (!mounted) return;

      if (status == UserVerificationStatus.VERIFIED) {
        // ¡EXITO! Navegar al Dashboard (Mapa)
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      } else if (status == UserVerificationStatus.REJECTED) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tus documentos fueron rechazados. Contacta soporte.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aún en revisión. Intenta de nuevo en unos segundos.',
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Estado de Cuenta"),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          TextButton(
            onPressed: () {
              _authService.logout();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text("Salir", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _checkStatus,
        color: Colors.black,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            const Icon(
              Icons.security_update_good,
              size: 100,
              color: Colors.amber,
            ),
            const SizedBox(height: 30),
            const Text(
              "Validando Documentación",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              "Tu perfil está siendo revisado por nuestro equipo legal para habilitar la generación de FUEC.\n\nEsto suele tomar menos de 24 horas.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            if (_checking)
              const Center(
                child: CircularProgressIndicator(color: Colors.black),
              )
            else
              ElevatedButton.icon(
                onPressed: _checkStatus,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text("VERIFICAR AHORA"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              "Desliza hacia abajo para actualizar",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
