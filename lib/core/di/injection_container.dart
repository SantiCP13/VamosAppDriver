import 'package:get_it/get_it.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// --- IMPORTS (Manteniendo tus rutas) ---

// Repositorios Core/Home
import '../../features/home/repositories/driver_repository.dart';
import '../../features/home/repositories/driver_repository_impl.dart';
import '../../features/home/repositories/trip_repository.dart';
import '../../features/home/repositories/trip_repository_impl.dart';

// Repositorios Nuevos (Wallet & History)
// Asegúrate de que estas rutas sean correctas según tu estructura de carpetas
import '../../features/wallet/domain/repositories/wallet_repository.dart';
import '../../features/wallet/data/repositories/wallet_repository_impl.dart';
import '../../../features/history/domain/repositories/history_repository.dart';
import '../../features/history/data/repositories/history_repository_impl.dart';

// Servicios
import '../services/storage_service.dart'; // Si esto falla, revisa la ruta ../../core/services...
import '../../features/home/services/location_service.dart';
import '../../features/home/services/trip_service.dart';
import '../../features/maps/services/route_service.dart';

// Providers
import '../../features/wallet/providers/wallet_provider.dart';
import '../../features/history/providers/history_provider.dart';
import '../../features/auth/providers/auth_provider.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // ---------------------------------------------------
  // 1. SERVICIOS (Core & External)
  // ---------------------------------------------------
  sl.registerLazySingleton<LocationService>(() => LocationService());
  sl.registerLazySingleton<StorageService>(() => StorageService());
  sl.registerLazySingleton<RouteService>(() => RouteService());

  // TripService depende de RouteService (sl() lo inyecta automático)
  sl.registerLazySingleton<TripService>(() => TripService(sl()));

  // ---------------------------------------------------
  // 2. REPOSITORIOS (Data Layer)
  // ---------------------------------------------------
  // Leemos la variable de entorno para decidir si usar Mocks o API Real
  final isMock = dotenv.env['ENV_TYPE'] == 'MOCK';

  if (isMock) {
    // --- MOCKS (Datos falsos para pruebas) ---
    sl.registerLazySingleton<DriverRepository>(() => MockDriverRepository());
    sl.registerLazySingleton<TripRepository>(() => MockTripRepository());

    // Nuevos Módulos
    sl.registerLazySingleton<WalletRepository>(() => MockWalletRepository());
    sl.registerLazySingleton<HistoryRepository>(() => ApiHistoryRepository());
  } else {
    // --- API (Conexión real al Backend) ---
    sl.registerLazySingleton<DriverRepository>(() => ApiDriverRepository());
    sl.registerLazySingleton<TripRepository>(() => ApiTripRepository());

    // Nuevos Módulos
    sl.registerLazySingleton<WalletRepository>(() => ApiWalletRepository());

    // NOTA: Si aún no creas ApiHistoryRepository, usa el Mock temporalmente aquí
    // sl.registerLazySingleton<HistoryRepository>(() => ApiHistoryRepository());
    sl.registerLazySingleton<HistoryRepository>(() => ApiHistoryRepository());
  }

  // ---------------------------------------------------
  // 3. PROVIDERS (Presentation / State Management)
  // ---------------------------------------------------

  // AuthProvider: SINGLETON (La sesión del usuario es global)
  sl.registerLazySingleton<AuthProvider>(() => AuthProvider());

  //
  // Esto asegura que el saldo y las transacciones persistan en memoria mientras la app vive.
  sl.registerLazySingleton<WalletProvider>(
    () => WalletProvider(repository: sl()),
  );

  // De registerFactory a registerLazySingleton
  sl.registerLazySingleton<HistoryProvider>(
    () => HistoryProvider(repository: sl()),
  );
}
