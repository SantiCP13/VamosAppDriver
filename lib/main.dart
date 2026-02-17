import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

// Imports de Features
import 'features/auth/screens/welcome_screen.dart';
import 'features/home/providers/home_provider.dart';
import 'features/wallet/providers/wallet_provider.dart';
import 'core/di/injection_container.dart' as di;
// Nota: Si tienes un DriverAuthProvider, impórtalo y agrégalo abajo.
// Si no, borra la línea de DriverAuthProvider en los providers.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Nota: No se encontró archivo .env, iniciando en modo MOCK.");
  }
  await di.init();
  runApp(
    MultiProvider(
      providers: [
        // Reemplaza esto con tu provider real de Auth si lo tienes
        // ChangeNotifierProvider(create: (_) => DriverAuthProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
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
