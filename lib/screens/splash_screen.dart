import 'package:flutter/material.dart';
import 'package:ciaccola_frontend/screens/login_screen.dart';
import 'package:ciaccola_frontend/screens/home_screen.dart';
import 'package:ciaccola_frontend/services/auth_service.dart';
import 'package:ciaccola_frontend/services/secure_storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final valid = await _authService.isStoredTokenValid();
    if (!mounted) return;

    if (valid) {
      final token = await SecureStorageService.getToken();
      if (token != null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => HomeScreen(token: token)),
        );
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'lib/assets/ciaccola_app_icon.png',
              height: 140,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Color(0xFF00CED1)),
            ),
          ],
        ),
      ),
    );
  }
}
