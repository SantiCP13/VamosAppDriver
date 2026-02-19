import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart'; // Asegúrate de tener esta dependencia
import '../../../core/models/trip_model.dart';
import '../providers/home_provider.dart';

class ActiveTripCard extends StatelessWidget {
  const ActiveTripCard({super.key});

  Future<void> _openFuec(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el PDF del FUEC')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeProvider = Provider.of<HomeProvider>(context);
    final trip = homeProvider.activeTrip;

    if (trip == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera: Estado y FUEC
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text(
                    trip.status.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.green,
                ),
                if (trip.fuecUrl != null)
                  TextButton.icon(
                    onPressed: () => _openFuec(context, trip.fuecUrl!),
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                    label: const Text("Ver FUEC Legal"),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Información del Pasajero
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(trip.passengerName),
              subtitle: Text(
                trip.status == TripStatus.ACCEPTED
                    ? "Recoger en: ${trip.originAddress}"
                    : "Llevar a: ${trip.destinationAddress}",
              ),
            ),

            const SizedBox(height: 10),

            // Botón de Acción Principal
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: homeProvider.isLoading
                    ? null
                    : () => homeProvider.handleTripAction(context),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  backgroundColor: trip.status == TripStatus.STARTED
                      ? Colors.red
                      : Colors.blue,
                ),
                child: homeProvider.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        trip.status == TripStatus.STARTED
                            ? "FINALIZAR VIAJE"
                            : (trip.status == TripStatus.ACCEPTED
                                  ? "LLEGUÉ AL PUNTO"
                                  : "INICIAR VIAJE"),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),

            // Botón Navegación
            Center(
              child: TextButton.icon(
                onPressed: homeProvider.openExternalNavigation,
                icon: const Icon(Icons.navigation),
                label: const Text("Abrir Waze / Google Maps"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
