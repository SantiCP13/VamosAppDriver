import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../home/providers/home_provider.dart';
import '../../wallet/providers/wallet_provider.dart';
import '../../wallet/screens/wallet_screen.dart';
import '../../history/screens/trip_history_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../auth/screens/welcome_screen.dart';
import '../../home/screens/support_screen.dart';
import '../../../core/models/user_model.dart'; // Asegúrate de tener el modelo importado

class SideMenu extends StatefulWidget {
  const SideMenu({super.key});

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<WalletProvider>().loadWalletData(force: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final homeProvider = context.watch<HomeProvider>();
    final walletProvider = context.watch<WalletProvider>();

    final User? user = authProvider.user; // Tipo explícito
    final String nombreMostrar = user?.name ?? "Conductor";

    // Si no quieres borrar 'inicial', úsala en el child del CircleAvatar como en el ejemplo
    final String inicial = nombreMostrar.isNotEmpty
        ? nombreMostrar[0].toUpperCase()
        : "C";

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.85,
      backgroundColor: const Color(0xFF0B0F19),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryGreen.withValues(alpha: 0.08),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(user, homeProvider, walletProvider, inicial),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 30,
                    ),
                    children: [
                      _buildMenuItem(
                        Icons.person_outline_rounded,
                        "Mi Perfil",
                        const ProfileScreen(),
                      ),
                      _buildMenuItem(
                        Icons.account_balance_wallet_outlined,
                        "Mi Billetera",
                        const WalletScreen(),
                      ),
                      _buildMenuItem(
                        Icons.history_rounded,
                        "Historial de Viajes",
                        const TripHistoryScreen(),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(color: Colors.white10),
                      ),
                      _buildMenuItem(
                        Icons.headset_mic_outlined,
                        "Soporte VAMOS",
                        const SupportScreen(),
                      ),
                    ],
                  ),
                ),
                _buildLogoutSection(authProvider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Agregamos tipos explícitos (User?, HomeProvider, WalletProvider, String)
  Widget _buildHeader(
    User? user,
    HomeProvider homeProvider,
    WalletProvider walletProvider,
    String inicial,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 40, 25, 20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.primaryGreen, Colors.blueAccent],
              ),
            ),
            child: CircleAvatar(
              radius: 42,
              backgroundColor: const Color(0xFF0B0F19),
              backgroundImage:
                  (user?.photoUrl != null && user!.photoUrl!.isNotEmpty)
                  ? NetworkImage(user.photoUrl!)
                  : null,
              child: (user?.photoUrl == null || user!.photoUrl!.isEmpty)
                  ? Text(
                      inicial,
                      style: GoogleFonts.montserrat(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white24,
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            user?.name ?? "Conductor",
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            homeProvider.selectedVehicle?.plate ?? "Vehículo no asignado",
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.account_balance_wallet,
                  color: AppColors.primaryGreen,
                  size: 18,
                ),
                const SizedBox(width: 10),
                walletProvider.isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          color: AppColors.primaryGreen,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        "Saldo: \$${walletProvider.balance.toStringAsFixed(0)}",
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, Widget screen) {
    return ListTile(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
      },
      leading: Icon(icon, color: Colors.white60, size: 22),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Colors.white24,
        size: 20,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildLogoutSection(AuthProvider authProvider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 0, 25, 40),
      child: TextButton.icon(
        onPressed: () async {
          await authProvider.logout();
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
            (r) => false,
          );
        },
        icon: const Icon(
          Icons.logout_rounded,
          color: Colors.redAccent,
          size: 20,
        ),
        label: Text(
          "Cerrar Sesión",
          style: GoogleFonts.montserrat(
            color: Colors.redAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
