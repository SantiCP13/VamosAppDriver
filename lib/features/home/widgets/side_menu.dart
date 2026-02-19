import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth/providers/auth_provider.dart'; // Importa el nuevo AuthProvider
import '../../wallet/screens/wallet_screen.dart';
import '../../history/screens/trip_history_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../auth/screens/welcome_screen.dart';

class SideMenu extends StatelessWidget {
  const SideMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // 1. Encabezado Dinámico
          Consumer<AuthProvider>(
            builder: (context, auth, child) {
              final user = auth.user;
              return UserAccountsDrawerHeader(
                decoration: const BoxDecoration(color: Colors.black),
                margin: EdgeInsets.zero,
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: (user?.photoUrl != null)
                      ? NetworkImage(user!.photoUrl!)
                      : null,
                  child: (user?.photoUrl == null)
                      ? Text(
                          user?.name[0] ?? "C",
                          style: const TextStyle(fontSize: 24),
                        )
                      : null,
                ),
                accountName: Text(
                  user?.name ?? "Conductor Invitado",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                accountEmail: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    // Nota: 'rating' no estaba en el modelo User, lo hardcodeo o agrégalo al modelo
                    const Text("5.0", style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        // Muestra Placa si existe, si no "Sin Vehículo"
                        (user?.role == null)
                            ? "Sin Vehículo"
                            : "PLACA: ${user?.documentNumber ?? '---'}",
                        // OJO: Ajustar según donde guardes la PLACA en tu User Model real
                        style: TextStyle(color: Colors.grey.shade400),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // 2. Opciones
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(context, Icons.person_outline, "Mi Perfil", () {
                  Navigator.pop(context); // Cierra drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                  // No necesitamos .then(), el Provider se encarga de todo.
                }),
                _buildMenuItem(
                  context,
                  Icons.account_balance_wallet_outlined,
                  "Billetera",
                  () => _navigateTo(context, const WalletScreen()),
                ),
                _buildMenuItem(
                  context,
                  Icons.history,
                  "Historial de Viajes",
                  () => _navigateTo(context, const TripHistoryScreen()),
                ),
              ],
            ),
          ),

          // 3. Logout
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "Cerrar Sesión",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () {
              // 1. Ejecutar lógica de Logout (limpiar token, variables, etc)
              context.read<AuthProvider>().logout();

              // 2. Navegar directamente a la pantalla de Inicio (WelcomeScreen)
              // Usamos pushAndRemoveUntil para borrar todo el historial de navegación anterior
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                (route) =>
                    false, // Predicado: false borra TODAS las rutas anteriores
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String text,
    VoidCallback onTap,
  ) {
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
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }
}
