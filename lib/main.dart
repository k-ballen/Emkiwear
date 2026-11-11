import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'ui/theme.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';
import 'services/tremor_provider.dart';
import 'services/app_check_info.dart';
import 'services/voice_assistant_service.dart';

/// Token de depuración de App Check. Se inyecta SOLO en tiempo de compilación:
///   `flutter run --dart-define=APPCHECK_DEBUG_TOKEN=TOKEN_REGISTRADO_EN_LA_CONSOLA`
/// Nunca escribirlo en archivos del repo.
const String _appCheckDebugToken = String.fromEnvironment('APPCHECK_DEBUG_TOKEN');

Future<void> _activateAppCheck() async {
  AppCheckInfo.hasDebugToken = _appCheckDebugToken.isNotEmpty;
  try {
    if (kReleaseMode) {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: const AndroidPlayIntegrityProvider(),
        providerApple: const AppleDeviceCheckProvider(),
      );
      AppCheckInfo.provider = 'playIntegrity';
    } else {
      final String? token = _appCheckDebugToken.isEmpty ? null : _appCheckDebugToken;
      await FirebaseAppCheck.instance.activate(
        providerAndroid: AndroidDebugProvider(debugToken: token),
        providerApple: AppleDebugProvider(debugToken: token),
      );
      AppCheckInfo.provider = 'debug';
    }
    AppCheckInfo.status = 'Activado, verificando...';
    unawaited(_verifyAppCheckToken());
  } catch (e) {
    AppCheckInfo.status = 'Error al activar: $e';
    debugPrint('[AppCheck] Error al activar: $e');
  }
}

/// Pide un token para confirmar que App Check funciona (sin bloquear el arranque).
Future<void> _verifyAppCheckToken() async {
  try {
    final token = await FirebaseAppCheck.instance
        .getToken()
        .timeout(const Duration(seconds: 10));
    AppCheckInfo.status = (token != null && token.isNotEmpty) ? 'OK' : 'Sin token';
  } catch (e) {
    AppCheckInfo.status = 'Error token: $e';
    debugPrint('[AppCheck] Error al obtener token: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await _activateAppCheck();
  await initializeDateFormatting('es_ES', null);
  // Precarga el modelo (Remote Config) sin bloquear el arranque.
  unawaited(VoiceAssistantService.instance.warmUp());

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TremorProvider()),
      ],
      child: const ParkinsonApp(),
    ),
  );
}

class ParkinsonApp extends StatelessWidget {
  const ParkinsonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parkinson Care',
      theme: AppTheme.lightTheme,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const HomeScreen();
          }
          return const LoginScreen();
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
