import 'package:get_it/get_it.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Repositorios
import '../../features/home/repositories/driver_repository.dart';
import '../../features/home/repositories/driver_repository_impl.dart';
import '../../features/home/repositories/trip_repository.dart';
import '../../features/home/repositories/trip_repository_impl.dart';

// Servicios
import '../services/storage_service.dart';
import '../../features/home/services/location_service.dart';
import '../../features/home/services/trip_service.dart';
// IMPORTA TU ROUTE SERVICE (Asegúrate que la ruta sea correcta según tu árbol)
import '../../features/maps/services/route_service.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // ---------------------------------------------------
  // 1. SERVICIOS (Core & External)
  // ---------------------------------------------------
  sl.registerLazySingleton<LocationService>(() => LocationService());
  sl.registerLazySingleton<StorageService>(() => StorageService());

  // NUEVO: Registramos RouteService (La conexión a OSRM/Google)
  sl.registerLazySingleton<RouteService>(() => RouteService());

  // TripService ahora dependerá de RouteService, así que GetIt lo inyectará automáticamente
  sl.registerLazySingleton<TripService>(() => TripService(sl()));

  // ---------------------------------------------------
  // 2. REPOSITORIOS
  // ---------------------------------------------------
  final isMock = dotenv.env['ENV_TYPE'] == 'MOCK';

  if (isMock) {
    sl.registerLazySingleton<DriverRepository>(() => MockDriverRepository());
    sl.registerLazySingleton<TripRepository>(() => MockTripRepository());
  } else {
    sl.registerLazySingleton<DriverRepository>(() => ApiDriverRepository());
    sl.registerLazySingleton<TripRepository>(() => ApiTripRepository());
  }
}
