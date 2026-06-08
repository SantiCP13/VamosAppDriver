import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/models/transaction_model.dart';

class TransactionDetailItem extends StatefulWidget {
  final TransactionModel transaction;

  const TransactionDetailItem({super.key, required this.transaction});

  @override
  State<TransactionDetailItem> createState() => _TransactionDetailItemState();
}

class _TransactionDetailItemState extends State<TransactionDetailItem> {
  bool _isExpanded = false;

  String _formatCurrency(double amount) {
    final formatter = NumberFormat("#,##0", "es_CO");
    final String sign = amount < 0 ? '-' : '';
    return "$sign\$${formatter.format(amount.abs())}";
  }

  @override
  Widget build(BuildContext context) {
    final bool isTrip = widget.transaction.originAddress != null;
    final bool isFine =
        widget.transaction.tripPaymentMethod?.toUpperCase() == 'MULTA';
    final String formattedDate = DateFormat(
      'dd/MM/yyyy • hh:mm a',
      'es',
    ).format(widget.transaction.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161B2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- ENCABEZADO (Siempre visible) ---
          InkWell(
            onTap: isTrip
                ? () => setState(() => _isExpanded = !_isExpanded)
                : null,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isFine
                        ? Icons
                              .gavel_rounded // Martillo de multa
                        : (isTrip
                              ? Icons.directions_car_rounded
                              : Icons.account_balance_wallet_rounded),
                    color: isFine ? Colors.redAccent : AppColors.primaryGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isFine
                            ? "Multa por Cancelación" // 🟢 Título dinámico para multas
                            : (isTrip
                                  ? "Servicio de Transporte"
                                  : widget.transaction.description),
                        style: GoogleFonts.montserrat(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
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

                // Valor neto y flecha
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isTrip
                          ? _formatCurrency(
                              widget.transaction.netEarnings ?? 0.0,
                            )
                          : "${widget.transaction.isCredit ? '+' : ''}${_formatCurrency(widget.transaction.amount)}",
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w900,
                        // 🟢 Si es multa, se pinta en rojo
                        color:
                            (isTrip && !isFine) || widget.transaction.isCredit
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        fontSize: 14,
                      ),
                    ),
                    if (isTrip)
                      Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: Colors.white30,
                        size: 18,
                      ),
                  ],
                ),
              ],
            ),
          ),

          // --- SECCIÓN DESPLEGABLE ---
          if (isTrip)
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _isExpanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 16),

                        // Ruta de origen a destino del viaje afectado
                        Row(
                          children: [
                            const Icon(
                              Icons.radio_button_checked_rounded,
                              color: AppColors.primaryGreen,
                              size: 14,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.transaction.originAddress!,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            width: 1.5,
                            height: 12,
                            color: Colors.white12,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: Colors.redAccent,
                              size: 14,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.transaction.destinationAddress!,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        // Duración del viaje afectado
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              color: Colors.grey,
                              size: 14,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "Duración: ${widget.transaction.durationMinutes?.toStringAsFixed(0) ?? '0'} minutos",
                              style: GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 16),

                        // 🟢 DESGLOSE EXCLUSIVO DE MULTA: No mostramos las tarifas ganadas del viaje porque no se hizo
                        if (isFine)
                          _financeRow(
                            "Cargo por Cancelación Tardía:",
                            _formatCurrency(
                              widget.transaction.netEarnings ?? 0.0,
                            ),
                            isBold: true,
                            valueColor: Colors.redAccent,
                          )
                        else ...[
                          // Desglose financiero ordinario para viajes completados
                          _financeRow(
                            "Valor pagado por usuario:",
                            _formatCurrency(
                              widget.transaction.grossAmount ?? 0.0,
                            ),
                          ),
                          _financeRow(
                            "Comisión Vamos deducida:",
                            "- ${_formatCurrency(widget.transaction.commission ?? 0.0)}",
                            valueColor: Colors.redAccent,
                          ),
                          const SizedBox(height: 6),
                          const Divider(color: Colors.white10, height: 1),
                          const SizedBox(height: 8),
                          _financeRow(
                            "Ganancia neta del viaje:",
                            _formatCurrency(
                              widget.transaction.netEarnings ?? 0.0,
                            ),
                            isBold: true,
                            valueColor: AppColors.primaryGreen,
                          ),
                        ],
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _financeRow(
    String label,
    String value, {
    bool isBold = false,
    Color valueColor = Colors.white,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: isBold ? Colors.white : Colors.white54,
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.montserrat(
              color: valueColor,
              fontSize: isBold ? 14 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
