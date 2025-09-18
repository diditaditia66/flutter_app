import 'package:flutter/material.dart';
import 'package:temperature_prediction/screens/home_screen.dart';
import 'package:temperature_prediction/screens/login_screen.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  Future<bool> _initAuth() => AuthService.instance.isLoggedIn();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Temperature Prediction',
      theme: ThemeData.dark(),
      routes: {
        '/home': (_) => const HomeScreen(),
        '/login': (_) => const LoginScreen(),
      },
      home: FutureBuilder<bool>(
        future: _initAuth(),
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snap.data == true ? const HomeScreen() : const LoginScreen();
        },
      ),
    );
  }
}
