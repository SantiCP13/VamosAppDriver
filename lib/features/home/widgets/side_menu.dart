// lib/features/home/widgets/side_menu.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../home/providers/home_provider.dart';
import '../../wallet/providers/wallet_provider.dart';
import '../../wallet/screens/wallet_screen.dart';
import '../../history/screens/trip_history_screen.dart';
import '../../history/screens/scheduled_trips_screen.dart';
import '../../history/providers/history_provider.dart';
import '../../profile/screens/profile_screen.dart';
import '../../auth/screens/welcome_screen.dart';
import '../../home/screens/support_screen.dart';
import '../../../core/models/user_model.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 🟢 INSTALAR PROVEEDOR DE CACHÉ
import 'package:package_info_plus/package_info_plus.dart'; // 🟢 NUEVA IMPORTACIÓN

class SideMenu extends StatefulWidget {
  const SideMenu({super.key});

  @override
  State<SideMenu> createState() => _SideMenuState();
}

class _SideMenuState extends State<SideMenu> {
  String _appVersion = "v0.0.0"; // 🟢 VARIABLE DINÁMICA DE VERSIÓN

  @override
  void initState() {
    super.initState();
    _loadAppVersion(); // 🟢 CARGA INICIAL DE VERSIÓN
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<WalletProvider>().loadWalletData(force: true);
        context.read<HistoryProvider>().loadHistory(forceRefresh: true);
      }
    });
  }

  // 🟢 MÉTODO PARA LEER EL PUBSPEC DINÁMICAMENTE
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion =
              "Versión ${packageInfo.version} (${packageInfo.buildNumber})";
        });
      }
    } catch (_) {}
  }

  Map<String, dynamic>? _getCompanyOrConvenio(
    User? user,
    HomeProvider homeProvider,
  ) {
    final vehicle = homeProvider.selectedVehicle;
    if (vehicle == null) return null;

    final dynamic v = vehicle;
    Map<String, dynamic>? vehicleMap;

    try {
      if (v.toMap() != null) {
        vehicleMap = Map<String, dynamic>.from(v.toMap());
      }
    } catch (_) {
      try {
        if (v.toJson() != null) {
          vehicleMap = Map<String, dynamic>.from(v.toJson());
        }
      } catch (_) {}
    }

    String? extractRazonSocial(dynamic companyObj) {
      if (companyObj == null) return null;
      if (companyObj is Map) {
        return companyObj['razon_social']?.toString() ??
            companyObj['razonSocial']?.toString();
      }
      try {
        final dynamic co = companyObj;
        return co.razonSocial?.toString() ?? co.razon_social?.toString();
      } catch (_) {}
      return null;
    }

    bool enConvenio = false;
    try {
      enConvenio =
          v.enConvenio ??
          v.en_convenio ??
          (vehicleMap != null &&
              (vehicleMap['en_convenio'] == true ||
                  vehicleMap['enConvenio'] == true));
    } catch (_) {}

    if (enConvenio) {
      dynamic empresaConvenioObj;
      try {
        empresaConvenioObj = v.empresaConvenio ?? v.empresa_convenio;
      } catch (_) {}
      empresaConvenioObj ??=
          vehicleMap?['empresa_convenio'] ?? vehicleMap?['empresaConvenio'];

      final String? nombreConvenio = extractRazonSocial(empresaConvenioObj);
      if (nombreConvenio != null && nombreConvenio.trim().isNotEmpty) {
        return {'text': nombreConvenio, 'isConvenio': true};
      }
    }

    dynamic empresaTransporteObj;
    try {
      empresaTransporteObj = v.empresaTransporte ?? v.empresa_transporte;
    } catch (_) {}
    empresaTransporteObj ??=
        vehicleMap?['empresa_transporte'] ?? vehicleMap?['empresaTransporte'];

    final String? nombreEmpresa = extractRazonSocial(empresaTransporteObj);
    if (nombreEmpresa != null && nombreEmpresa.trim().isNotEmpty) {
      return {'text': nombreEmpresa, 'isConvenio': false};
    }

    if (user != null) {
      try {
        final dynamic du = user;
        if (du.empresa != null && du.empresa.toString().trim().isNotEmpty) {
          return {'text': du.empresa.toString(), 'isConvenio': false};
        }
      } catch (_) {}
    }

    return null;
  }

  Widget _buildCompanyBadge(User? user, HomeProvider homeProvider) {
    final Map<String, dynamic>? data = _getCompanyOrConvenio(
      user,
      homeProvider,
    );

    if (data == null) {
      return const SizedBox.shrink();
    }

    final String text = data['text'] as String;
    final bool isConvenio = data['isConvenio'] as bool;

    final Color badgeColor = isConvenio
        ? Colors.blueAccent
        : AppColors.primaryGreen;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: badgeColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isConvenio ? Icons.handshake_rounded : Icons.business_rounded,
            color: badgeColor,
            size: 14,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              isConvenio
                  ? "CONVENIO: ${text.toUpperCase()}"
                  : text.toUpperCase(),
              style: GoogleFonts.montserrat(
                color: badgeColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final homeProvider = context.watch<HomeProvider>();
    final walletProvider = context.watch<WalletProvider>();
    final historyProvider = context.watch<HistoryProvider>();

    final int scheduledCount = historyProvider.history.where((t) {
      final statusStr = t.status.toString().toUpperCase();
      return statusStr.contains('SCHEDULED_ASSIGNED') ||
          statusStr.contains('PENDING_SCHEDULED');
    }).length;

    final User? user = authProvider.user;
    final String nombreMostrar = user?.name ?? "Conductor";

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
                      vertical: 20,
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
                        Icons.event_note_rounded,
                        "Viajes Programados",
                        const ScheduledTripsScreen(),
                        badgeCount: scheduledCount,
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

  Widget _buildHeader(
    User? user,
    HomeProvider homeProvider,
    WalletProvider walletProvider,
    String inicial,
  ) {
    final bool tieneTurnoActivo = homeProvider.isOnline;

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
              // CAMBIO: Se sustituye NetworkImage por CachedNetworkImageProvider con log de prueba
              backgroundImage:
                  (user?.photoUrl != null && user!.photoUrl!.isNotEmpty)
                  ? CachedNetworkImageProvider(
                      user.photoUrl!,
                      errorListener: (ex) => debugPrint(
                        "⚠️ [SIDE MENU DRIVER] Falló carga de foto en caché: $ex",
                      ),
                    )
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

          // 🟢 MEJORA: Insignia de desconexión inmediata o renderizado de estado de turno/vehículo activo
          if (homeProvider.isNetworkDisconnected) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.25),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: Colors.redAccent,
                    size: 12,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "SIN INTERNET",
                    style: GoogleFonts.montserrat(
                      color: Colors.redAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Si hay internet, mostramos la placa del vehículo asignada al turno
            Text(
              tieneTurnoActivo
                  ? (homeProvider.selectedVehicle?.plate ??
                        "Vehículo no asignado")
                  : "Sin turno activo",
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: tieneTurnoActivo
                    ? Colors.white54
                    : Colors.redAccent.withValues(alpha: 0.8),
                fontWeight: tieneTurnoActivo
                    ? FontWeight.normal
                    : FontWeight.bold,
              ),
            ),
          ],

          if (tieneTurnoActivo && !homeProvider.isNetworkDisconnected)
            _buildCompanyBadge(user, homeProvider),

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

  Widget _buildMenuItem(
    IconData icon,
    String title,
    Widget screen, {
    int? badgeCount,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
        },
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white60, size: 20),
        ),
        title: Text(
          title,
          style: GoogleFonts.montserrat(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeCount != null && badgeCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGreen.withValues(alpha: 0.25),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  "$badgeCount",
                  style: GoogleFonts.montserrat(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white24,
              size: 20,
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildLogoutSection(AuthProvider authProvider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 0, 25, 30),
      child: Column(
        // 🟢 Agregado Column para centrar el texto dinámico debajo
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () async {
              context.read<HomeProvider>().stopTracking();
              await authProvider.logout();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (r) => false,
              );
            },
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.logout_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    "Cerrar Sesión",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w700,
                      color: Colors.redAccent,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 🟢 COPIA Y PEGA ESTE TEXTO DINÁMICO AQUÍ ABAJO:
          const SizedBox(height: 16),
          Text(
            _appVersion,
            style: GoogleFonts.montserrat(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white24, // Color discreto adaptado al fondo oscuro
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
