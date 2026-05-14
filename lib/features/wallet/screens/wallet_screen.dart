import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart'; // Importa para usar AppColors
import '../providers/wallet_provider.dart';
import '../widgets/transaction_detail_item.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

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

  Widget _buildBalanceCard(WalletProvider wallet) => Container(
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
          "\$${wallet.balance.toStringAsFixed(0)}",
          style: GoogleFonts.montserrat(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat("Hoy", "\$${wallet.todayEarnings.toStringAsFixed(0)}"),
            _stat("Viajes", "${wallet.transactions.length}"),
          ],
        ),
      ],
    ),
  );

  Widget _stat(String label, String value) => Column(
    children: [
      Text(
        value,
        style: GoogleFonts.montserrat(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      Text(
        label,
        style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
      ),
    ],
  );
}
