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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // 1. Configuración básica
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}

  await di.init();
  await initializeDateFormatting('es_ES', null);

  // 2. Lógica de Autenticación SEGURA
  final authProvider = di.sl<AuthProvider>();

  // Inicializamos en false por defecto
  bool isAuthenticated = false;

  try {
    // Intentamos verificar el estado
    isAuthenticated = await authProvider.checkAuthStatus();
  } catch (e) {
    debugPrint("Error verificando auth: $e");
    isAuthenticated =
        false; // Si falla el servidor, lo mandamos al login (Welcome)
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => di.sl<WalletProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<HistoryProvider>()),
        ChangeNotifierProvider(create: (_) => HomeProvider()),
      ],
      // Forzamos que el resultado siempre sea un String no nulo
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
