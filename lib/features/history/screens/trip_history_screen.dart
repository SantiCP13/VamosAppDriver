import 'package:flutter/material.dart';
// Reutilizamos el modelo de wallet por ahora, o podrías crear un TripHistoryModel propio
import '../../../core/models/transaction_model.dart';
import '../../wallet/widgets/transaction_list_item.dart';

class TripHistoryScreen extends StatelessWidget {
  const TripHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Datos Mockeados para visualización
    final List<TransactionModel> history = [
      TransactionModel(
        id: '1',
        ledgerId: 'hist_001',
        title: 'Viaje Finalizado',
        description: 'Calle 85 -> Parque 93',
        amount: 8500,
        date: DateTime.now(),
        isCredit: true,
      ),
      TransactionModel(
        id: '2',
        ledgerId: 'hist_002',
        title: 'Viaje Cancelado',
        description: 'Usuario canceló',
        amount: 0,
        date: DateTime.now().subtract(const Duration(hours: 1)),
        isCredit: false,
      ),
      TransactionModel(
        id: '3',
        ledgerId: 'hist_003',
        title: 'Viaje Finalizado',
        description: 'Aeropuerto -> Centro',
        amount: 35000,
        date: DateTime.now().subtract(const Duration(days: 1)),
        isCredit: true,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Historial de Viajes")),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: history.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          return TransactionListItem(transaction: history[index]);
        },
      ),
    );
  }
}
