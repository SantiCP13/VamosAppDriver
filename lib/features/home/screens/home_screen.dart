import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

// Imports Core
import '../../../core/models/trip_model.dart';
import '../providers/home_provider.dart';

// Widgets
import '../widgets/trip_request_sheet.dart';
import '../widgets/side_menu.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Inicializamos la ubicación UNA sola vez al arrancar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().initLocation();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Escuchamos los cambios del Provider Global
    final provider = context.watch<HomeProvider>();
    final trip = provider.activeTrip;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const SideMenu(),
      body: Stack(
        children: [
          // --------------------------
          // 1. EL MAPA
          // --------------------------
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter:
                  provider.currentPosition ?? const LatLng(4.6097, -74.0817),
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.vamos.driver',
              ),
              // Ruta Azul
              if (provider.routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: provider.routePoints,
                      color: Colors.blueAccent,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
              // Marcadores
              MarkerLayer(
                markers: [
                  // Auto del Conductor
                  if (provider.currentPosition != null)
                    Marker(
                      point: provider.currentPosition!,
                      width: 50,
                      height: 50,
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.black,
                        size: 40,
                      ),
                    ),
                  // Origen (Verde)
                  if (trip != null &&
                      (trip.status == TripStatus.ACCEPTED ||
                          trip.status == TripStatus.ARRIVED))
                    Marker(
                      point: trip.originLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 40,
                      ),
                    ),
                  // Destino (Rojo)
                  if (trip != null && trip.status == TripStatus.STARTED)
                    Marker(
                      point: trip.destinationLocation,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.flag,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // --------------------------
          // 2. BOTÓN MENÚ (Hamburguesa)
          // --------------------------
          if (trip == null)
            Positioned(
              top: 50,
              left: 20,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
                ),
                child: IconButton(
                  icon: const Icon(Icons.menu, color: Colors.black),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ),
            ),

          // --------------------------
          // 3. INDICADOR DE ESTADO (Online/Offline)
          // --------------------------
          if (trip == null)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 10),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: provider.isOnline ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        provider.isOnline ? "EN LÍNEA" : "DESCONECTADO",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // --------------------------
          // 4. PANELES INFERIORES (La clave del problema)
          // --------------------------
          Align(
            alignment: Alignment.bottomCenter,
            // Aquí decidimos qué panel mostrar según el estado
            child: _buildPanelContent(context, provider),
          ),

          // --------------------------
          // 5. BOTÓN RE-CENTRAR
          // --------------------------
          Positioned(
            right: 20,
            bottom: 300, // Lo subimos para que no estorbe al panel
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Colors.black),
              onPressed: () {
                if (provider.currentPosition != null) {
                  _mapController.move(provider.currentPosition!, 15);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Selector inteligente de paneles inferiores
  Widget _buildPanelContent(BuildContext context, HomeProvider provider) {
    // CASO 1: HAY UNA OFERTA DE VIAJE ENTRANTE
    if (provider.incomingTrip != null) {
      return TripRequestSheet(
        trip: provider.incomingTrip!,
        onAccept: () => provider.acceptIncomingTrip(),
        onReject: () => provider.rejectIncomingTrip(),
      );
    }

    // CASO 2: HAY UN VIAJE EN CURSO
    if (provider.activeTrip != null) {
      return _TripActiveSheet(
        trip: provider.activeTrip!,
        onActionPressed: () => provider.handleTripAction(context),
      );
    }

    // CASO 3: ESTADO STANDBY (Botón Conectar)
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(
        16,
      ), // Un poco de margen flotante se ve mejor
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (provider.isOnline)
            const Padding(
              padding: EdgeInsets.only(bottom: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    "Buscando servicios...",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: provider.isLoading
                  ? null
                  : () async {
                      // 1. Llamamos a la función y capturamos el posible error
                      final errorMsg = await provider.toggleOnlineStatus();

                      // 2. Si 'errorMsg' tiene texto (no es null), mostramos la alerta
                      if (errorMsg != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errorMsg),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: provider.isOnline
                    ? Colors.redAccent
                    : Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: provider.isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      provider.isOnline ? "DESCONECTARSE" : "INICIAR TURNO",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ... (Tu clase _TripActiveSheet PUEDES PEGARLA AQUÍ ABAJO IGUAL QUE ANTES)
class _TripActiveSheet extends StatelessWidget {
  final Trip trip;
  final VoidCallback onActionPressed;

  const _TripActiveSheet({required this.trip, required this.onActionPressed});

  @override
  Widget build(BuildContext context) {
    String title = "";
    String buttonText = "";
    Color color = Colors.blue;
    String addressToShow = "";

    switch (trip.status) {
      case TripStatus.ACCEPTED:
        title = "Recogiendo a ${trip.passengerName}";
        buttonText = "LLEGUÉ AL SITIO";
        color = Colors.orange;
        addressToShow = trip.originAddress;
        break;
      case TripStatus.ARRIVED:
        title = "Esperando al pasajero";
        buttonText = "INICIAR CARRERA";
        color = Colors.purple;
        addressToShow = trip.originAddress;
        break;
      case TripStatus.STARTED:
        title = "En ruta al destino";
        buttonText = "FINALIZAR VIAJE";
        color = Colors.green;
        addressToShow = trip.destinationAddress;
        break;
      default:
        title = "Finalizando...";
        buttonText = "CERRAR";
        addressToShow = "";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.grey[700], size: 28),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.status == TripStatus.STARTED
                          ? "Destino:"
                          : "Recogida:",
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    Text(
                      addressToShow,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: onActionPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (trip.status != TripStatus.ARRIVED) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: OutlinedButton.icon(
                onPressed: () {
                  Provider.of<HomeProvider>(
                    context,
                    listen: false,
                  ).openExternalNavigation();
                },
                icon: const Icon(Icons.navigation_outlined, size: 20),
                label: const Text("ABRIR NAVEGACIÓN (WAZE/MAPS)"),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
