import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/history_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // SOLUCIÓN: Ejecutar la carga DESPUÉS de que se renderice el primer frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Usamos listen: false porque estamos fuera del árbol de renderizado activo
      Provider.of<HistoryProvider>(context, listen: false).loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    // IMPORTANTE: Asegúrate de borrar cualquier llamada a loadHistory() que tengas aquí.

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: const BackButton(color: Colors.black),
        title: Text(
          "Historial de Viajes",
          style: GoogleFonts.poppins(
            color: Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Consumer<HistoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.history.isEmpty) {
            return const Center(child: Text("No hay viajes registrados"));
          }

          return ListView.builder(
            itemCount: provider.history.length,
            itemBuilder: (context, index) {
              final transaction = provider.history[index];
              return ListTile(
                leading: const Icon(Icons.history, color: Colors.black),
                title: Text(transaction.title), // "Viaje Finalizado"
                subtitle: Text(transaction.description),
                trailing: Text(
                  "\$${transaction.amount.toStringAsFixed(0)}",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: transaction.amount > 0
                        ? AppColors.primaryGreen
                        : const Color(0xFFE53935),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
