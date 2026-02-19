import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

// Imports Core & Models
import '../../../core/models/trip_model.dart';
import '../providers/home_provider.dart';

// Widgets
import '../widgets/trip_request_sheet.dart';
import '../widgets/trip_panel_sheet.dart'; // <--- NUEVO IMPORT
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<HomeProvider>();
      provider.initLocation();
      provider.loadVehicles();
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
          // Solo visible si no hay viaje activo para no saturar la pantalla
          if (trip == null)
            Positioned(
              top: 50,
              left: 20,
              child: Container(
                decoration: const BoxDecoration(
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
          // 4. PANELES INFERIORES (MODIFICADO)
          // --------------------------
          // Usamos Positioned para asegurar que se fije al fondo
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildPanelContent(context, provider),
          ),

          // --------------------------
          // 5. BOTÓN RE-CENTRAR
          // --------------------------
          // Ajustamos dinámicamente la posición del botón según si hay panel o no
          Positioned(
            right: 20,
            // Si hay viaje activo, el panel es más alto, subimos el botón.
            // Si no, lo dejamos en 300 o ajustamos según el panel de "Go Online".
            bottom: trip != null ? 350 : 280,
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
    // CASO 1: OFERTA ENTRANTE
    if (provider.incomingTrip != null) {
      return TripRequestSheet(
        trip: provider.incomingTrip!,
        onAccept: () => provider.acceptIncomingTrip(),
        onReject: () => provider.rejectIncomingTrip(),
      );
    }

    // CASO 2: VIAJE EN CURSO (AQUÍ ESTÁ EL CAMBIO CLAVE)
    if (provider.activeTrip != null) {
      // Reemplazamos el widget antiguo por el nuevo TripPanelSheet
      // No necesitamos pasar argumentos porque TripPanelSheet usa Provider internamente.
      return const TripPanelSheet();
    }

    // CASO 3: STANDBY / OFFLINE
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(16),
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
          // Selector de Vehículo (Obligatorio por FUEC)
          if (!provider.isOnline) _VehicleSelector(provider: provider),

          if (provider.isOnline)
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: Column(
                children: [
                  const Row(
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
                  const SizedBox(height: 5),
                  Text(
                    "Operando: ${provider.selectedVehicle?.fullName ?? '...'}",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 10),

          // BOTÓN PRINCIPAL (GO ONLINE)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: provider.isLoading
                  ? null
                  : () async {
                      final errorMsg = await provider.toggleOnlineStatus();
                      if (errorMsg != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(errorMsg),
                            backgroundColor: Colors.red,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: provider.isOnline
                    ? Colors.redAccent
                    : (provider.selectedVehicle == null
                          ? Colors.grey
                          : Colors.black),
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

// Widget auxiliar para selección de vehículos (Se mantiene igual)
class _VehicleSelector extends StatelessWidget {
  final HomeProvider provider;

  const _VehicleSelector({required this.provider});

  void _showSelectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Selecciona tu vehículo",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Para generar el FUEC legal, necesitamos saber qué vehículo conduces hoy.",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const Divider(),
              if (provider.myVehicles.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text("No tienes vehículos asignados.")),
                )
              else
                ...provider.myVehicles.map((vehicle) {
                  final isSelected = provider.selectedVehicle?.id == vehicle.id;
                  return ListTile(
                    leading: Icon(
                      Icons.directions_car,
                      color: isSelected ? Colors.black : Colors.grey,
                    ),
                    title: Text(
                      vehicle.plate,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      "${vehicle.brand} ${vehicle.model} - ${vehicle.color}",
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: () {
                      provider.selectVehicle(vehicle);
                      Navigator.pop(ctx);
                    },
                  );
                }),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showSelectionModal(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
          color: Colors.grey.shade50,
        ),
        child: Row(
          children: [
            const Icon(Icons.garage_outlined, color: Colors.black54),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.selectedVehicle == null
                        ? "Seleccionar Vehículo"
                        : provider.selectedVehicle!.plate,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: provider.selectedVehicle == null
                          ? Colors.redAccent
                          : Colors.black,
                    ),
                  ),
                  if (provider.selectedVehicle != null)
                    Text(
                      "${provider.selectedVehicle!.brand} ${provider.selectedVehicle!.model}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.black),
          ],
        ),
      ),
    );
  }
}
