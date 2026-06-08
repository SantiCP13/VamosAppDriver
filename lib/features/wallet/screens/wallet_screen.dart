// 🟢 MODIFICADO: Agregamos import de intl para dar formato premium a las monedas
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';
import '../widgets/transaction_detail_item.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  // 🟢 NUEVO: Formateador unificado de moneda colombiana con puntos de miles
  String _formatCurrency(double amount) {
    final formatter = NumberFormat("#,##0", "es_CO");
    // Si el valor es negativo, mostramos el signo '-' afuera
    final String sign = amount < 0 ? '-' : '';
    return "$sign\$${formatter.format(amount.abs())}";
  }

  @override
  Widget build(BuildContext context) {
    final WalletProvider wallet = context.watch<WalletProvider>();
    final Color darkBg = const Color(0xFF0B0F19);

    return Scaffold(
      backgroundColor: darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // --- BOTÓN DE ATRÁS PERSONALIZADO (Estilo Profile) ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Text(
                    "BILLETERA",
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () => wallet.loadWalletData(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBalanceCard(wallet),
                      const SizedBox(height: 40),
                      Text(
                        "HISTORIAL DE MOVIMIENTOS",
                        style: GoogleFonts.montserrat(
                          color: AppColors.primaryGreen,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ...wallet.transactions.map(
                        (tx) => TransactionDetailItem(transaction: tx),
                      ),
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

  Widget _buildBalanceCard(WalletProvider wallet) {
    final double bal = wallet.balance;
    // 🟢 Dinámico: Saldo disponible en rojo si está en mora (negativo), de lo contrario blanco
    final Color balColor = bal < 0 ? Colors.redAccent : Colors.white;

    final double today = wallet.todayEarnings;
    // 🟢 Dinámico: Ganancias de hoy en verde si son positivas, rojo si son negativas, blanco si es cero
    final Color todayColor = today > 0
        ? Colors.greenAccent
        : (today < 0 ? Colors.redAccent : Colors.white54);

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E2A44), Color(0xFF0B0F19)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Text(
            "Saldo Disponible",
            style: GoogleFonts.poppins(color: Colors.white54),
          ),
          Text(
            _formatCurrency(bal), // 🟢 Aplicación de formato con puntos
            style: GoogleFonts.montserrat(
              fontSize: 38,
              fontWeight: FontWeight.bold,
              color: balColor, // 🟢 Color adaptativo de saldo
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(
                "Hoy",
                _formatCurrency(today), // 🟢 Aplicación de formato con puntos
                textColor: todayColor, // 🟢 Color adaptativo de ganancias
              ),
              _stat(
                "Viajes",
                "${wallet.transactions.length}",
                textColor: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {Color textColor = Colors.white}) =>
      Column(
        children: [
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color:
                  textColor, // 🟢 Ahora recibe el color dinámico por parámetro
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
          ),
        ],
      );
}
