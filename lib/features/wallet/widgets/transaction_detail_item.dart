import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/models/transaction_model.dart';

class TransactionDetailItem extends StatelessWidget {
  final TransactionModel transaction;

  const TransactionDetailItem({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    bool isCredit = transaction.isCredit;
    final String formattedDate = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(transaction.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B2E),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  // CORRECCIÓN: Comparamos con el Enum, no con un string
                  transaction.type == TransactionType.TRIP_PAYMENT
                      ? Icons.directions_car
                      : Icons.account_balance_wallet,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction
                          .description, // Ya no necesita '??' porque no es null
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      formattedDate,
                      style: GoogleFonts.poppins(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                "${isCredit ? '+' : ''}\$${transaction.amount.toStringAsFixed(0)}",
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  color: isCredit ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Asegúrate de que tu modelo tenga paymentMethod y netEarnings
              _infoChip("Pago", transaction.paymentMethod ?? "N/A"),
              _infoChip(
                "Neto",
                "\$${(transaction.netEarnings ?? 0).toStringAsFixed(0)}",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) => Row(
    children: [
      Text(
        "$label: ",
        style: GoogleFonts.poppins(color: Colors.white30, fontSize: 12),
      ),
      Text(
        value,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
