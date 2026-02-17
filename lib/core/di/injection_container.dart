import 'package:get_it/get_it.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Importa tus Repositorios
import '../../features/home/repositories/driver_repository.dart';
import '../../features/home/repositories/driver_repository_impl.dart';
import '../../features/home/repositories/trip_repository.dart';
import '../../features/home/repositories/trip_repository_impl.dart';

// Importa los Servicios que faltaban registrar
import '../services/storage_service.dart';
import '../../features/home/services/location_service.dart';
import '../../features/home/services/trip_service.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // ---------------------------------------------------
  // 1. SERVICIOS (External & Core) - ¡ESTO FALTABA!
  // ---------------------------------------------------

  // Registramos LocationService para que HomeProvider pueda encontrarlo
  sl.registerLazySingleton<LocationService>(() => LocationService());

  // Registramos StorageService para guardar sesiones
  sl.registerLazySingleton<StorageService>(() => StorageService());

  // Registramos TripService (el calculador de rutas)
  sl.registerLazySingleton<TripService>(() => TripService());

  // ---------------------------------------------------
  // 2. REPOSITORIOS (Lógica de Negocio Switchable)
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
