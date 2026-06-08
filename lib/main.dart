import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

// Imports de Features
import 'features/auth/screens/welcome_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/home/providers/home_provider.dart';
import 'features/wallet/providers/wallet_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/history/providers/history_provider.dart'; // <--- 1. NUEVO IMPORT
import 'core/theme/app_theme.dart'; // Importa el nuevo tema
import 'package:intl/date_symbol_data_local.dart';
import 'core/di/injection_container.dart' as di;
import 'features/auth/screens/splash_screen.dart';
import 'package:flutter/services.dart';
import 'core/services/notification_service.dart'; // <--- AGREGAR ESTE IMPORT

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init(); // <--- AGREGAR ESTA LÍNEA

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}

  // 1. Inicializamos GetIt
  await di.init();
  await initializeDateFormatting('es_ES', null);

  // 2. Obtenemos las instancias desde el contenedor (YA REGISTRADAS como Singleton)
  final authProvider = di.sl<AuthProvider>();
  final homeProvider = di.sl<HomeProvider>(); // Instancia única

  // 3. Verificamos sesión
  bool isAuthenticated = false;
  try {
    isAuthenticated = await authProvider.checkAuthStatus();
    // Si está autenticado, inicializamos la ubicación del HomeProvider
    if (isAuthenticated) {
      await homeProvider.initLocation();
    }
  } catch (e) {
    debugPrint("Error verificando auth: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => di.sl<WalletProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<HistoryProvider>()),
        ChangeNotifierProvider.value(
          value: homeProvider,
        ), // <--- INSTANCIA ÚNICA
      ],
      child: MyApp(initialRoute: isAuthenticated ? '/home' : '/'),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String initialRoute; // Esta viene del login logic
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'VAMOS Driver',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // MODIFICACIÓN AQUÍ:
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => SplashScreen(
          logoPath: 'assets/images/logo.png',
          nextRoute: initialRoute, // Nos mandará a / o a /home según el login
          isDark: true,
        ),
        '/': (context) => const WelcomeScreen(),
        '/home': (context) => const HomeScreen(),
      },
    );
  }
}
