import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'welcome_screen.dart';
import '../../home/screens/home_screen.dart';

class SplashScreen extends StatefulWidget {
  final String logoPath;
  final String nextRoute;
  final bool isLoader;
  final bool isDark;

  const SplashScreen({
    super.key,
    required this.logoPath,
    this.nextRoute = '',
    this.isLoader = false,
    this.isDark = false,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _scale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );
    _controller.forward();

    if (!widget.isLoader) {
      Future.delayed(const Duration(milliseconds: 3500), () {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 1200),
              pageBuilder: (context, animation, secondaryAnimation) {
                if (widget.nextRoute == '/home') return const HomeScreen();
                return const WelcomeScreen();
              },
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeIn,
                      ),
                      child: child,
                    );
                  },
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: widget.isDark
                ? [
                    const Color(0xFF25335A),
                    const Color(0xFF0D121F),
                  ] // FONDO DARK
                : [AppColors.white, AppColors.greyLight], // FONDO LIGHT
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              child: Hero(
                tag: 'logo',
                child: Image.asset(widget.logoPath, width: 220),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
