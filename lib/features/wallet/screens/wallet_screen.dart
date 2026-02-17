import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Importamos la Lógica
import '../providers/wallet_provider.dart';
// Importamos los Widgets visuales (Asegúrate de haberlos creado como te pasé antes)
import '../widgets/balance_card.dart';
import '../widgets/transaction_list_item.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    // Carga los datos apenas se abre la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().loadWalletData();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Escucha cambios en el proveedor
    final wallet = context.watch<WalletProvider>();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Billetera"),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: wallet.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => context.read<WalletProvider>().loadWalletData(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tarjeta de Saldo
                    BalanceCard(
                      balance: wallet.balance,
                      todayEarnings: wallet.todayEarnings,
                    ),
                    const SizedBox(height: 24),

                    // Título Historial
                    const Text(
                      "Historial Reciente",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Lista de Transacciones
                    if (wallet.transactions.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text("No hay movimientos aún"),
                        ),
                      )
                    else
                      ListView.separated(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: wallet.transactions.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          return TransactionListItem(
                            transaction: wallet.transactions[index],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
