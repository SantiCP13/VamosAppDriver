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

  debugPrint("1 - Flutter iniciado");

  try {
    await dotenv.load(fileName: ".env");
    debugPrint("2 - dotenv cargado");
  } catch (e) {
    debugPrint("Nota: No se encontró archivo .env");
  }

  debugPrint("3 - antes de DI");

  await di.init();

  debugPrint("4 - después de DI");

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => di.sl<AuthProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<WalletProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<HistoryProvider>()),
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
