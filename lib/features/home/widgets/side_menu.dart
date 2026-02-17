import 'package:flutter/material.dart';
// Asegúrate que estas rutas sean exactas:
import '../../wallet/screens/wallet_screen.dart';
import '../../history/screens/trip_history_screen.dart';
// Si ProfileScreen no existe aún, comenta su import y su uso temporalmente
import '../../profile/screens/profile_screen.dart';

class SideMenu extends StatelessWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context) {
    // ELIMINADO: final colorScheme... (No se usaba)

    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(0),
          bottomRight: Radius.circular(0),
        ),
      ),
      child: Column(
        children: [
          // 1. Encabezado
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.black),
            margin: EdgeInsets.zero,
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Colors.grey.shade800),
            ),
            accountName: const Text(
              "Juan Conductor",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 4),
                const Text("4.95", style: TextStyle(color: Colors.white70)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Chevrolet Spark GT",
                    style: TextStyle(color: Colors.grey.shade400),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // 2. Opciones
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(
                  context,
                  icon: Icons.person_outline,
                  text: "Mi Perfil",
                  onTap: () => _navigateTo(context, const ProfileScreen()),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.account_balance_wallet_outlined,
                  text: "Billetera",
                  onTap: () => _navigateTo(context, const WalletScreen()),
                ),
                _buildMenuItem(
                  context,
                  icon: Icons.history,
                  text: "Historial de Viajes",
                  onTap: () => _navigateTo(context, const TripHistoryScreen()),
                ),
                const Divider(),
                _buildMenuItem(
                  context,
                  icon: Icons.help_outline,
                  text: "Soporte",
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Módulo de soporte pendiente"),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // 3. Cerrar Sesión
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "Cerrar Sesión",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () {
              Navigator.pop(context);
              // Aquí iría context.read<DriverAuthProvider>().logout();
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(
        Icons.arrow_forward_ios,
        size: 14,
        color: Colors.grey,
      ),
      onTap: onTap,
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.pop(context); // Cierra el drawer primero
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }
}
