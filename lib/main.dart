import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

// Imports de Features
import 'features/auth/screens/welcome_screen.dart';
import 'features/home/providers/home_provider.dart';
import 'features/wallet/providers/wallet_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/history/providers/history_provider.dart'; // <--- 1. NUEVO IMPORT

import 'core/di/injection_container.dart' as di;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Nota: No se encontró archivo .env, iniciando en modo MOCK.");
  }

  // Inicializamos la Inyección de Dependencias
  await di.init();

  runApp(
    MultiProvider(
      providers: [
        // 1. AuthProvider (Singleton)
        ChangeNotifierProvider(create: (_) => di.sl<AuthProvider>()),

        // 2. WalletProvider (Singleton - Inyectado vía GetIt)
        ChangeNotifierProvider(create: (_) => di.sl<WalletProvider>()),

        // 3. HistoryProvider (Singleton - Inyectado vía GetIt)
        // ESTA ES LA LÍNEA QUE FALTABA PARA EVITAR EL CRASH
        ChangeNotifierProvider(create: (_) => di.sl<HistoryProvider>()),

        // 4. HomeProvider
        // Nota: Si HomeProvider no está en GetIt, se instancia manual.
        // Asegúrate de que HomeProvider use sl<T>() internamente.
        ChangeNotifierProvider(create: (_) => HomeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Vamos Driver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      home: const WelcomeScreen(),
    );
  }
}
