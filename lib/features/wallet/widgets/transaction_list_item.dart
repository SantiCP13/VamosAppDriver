// IMPORTANTE: Apuntar al modelo del Core
import '../../../core/models/transaction_model.dart';
import 'package:flutter/material.dart';

class TransactionListItem extends StatelessWidget {
  final TransactionModel transaction;

  // Corrección: Uso de super.key para eliminar la advertencia
  const TransactionListItem({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.isCredit;

    return ListTile(
      leading: CircleAvatar(
        // Corrección: Uso de .withValues(alpha: X) en lugar de .withOpacity()
        backgroundColor: isCredit
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        child: Icon(
          isCredit ? Icons.arrow_downward : Icons.arrow_upward,
          color: isCredit ? Colors.green : Colors.red,
          size: 20,
        ),
      ),
      title: Text(
        transaction.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        "${transaction.description} • ${_formatDate(transaction.date)}",
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
      trailing: Text(
        "${isCredit ? '+' : '-'} \$${transaction.amount.toStringAsFixed(0)}",
        style: TextStyle(
          color: isCredit ? Colors.green : Colors.red,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }
}
