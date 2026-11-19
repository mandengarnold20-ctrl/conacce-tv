import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/env.dart';
import 'core/theme/app_theme.dart';
import 'features/shell.dart';

/// Point d'entrée de Conacce TV.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Env.isConfigured) {
    await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  }

  // Radio et cultes audio en arrière-plan, contrôles sur l'écran verrouillé.
  if (!kIsWeb) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.conacce.tv.audio',
      androidNotificationChannelName: 'Conacce TV — lecture audio',
      androidNotificationOngoing: true,
    );
  }

  await initializeDateFormatting('fr_FR');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  runApp(const ProviderScope(child: ConacceApp()));
}

class ConacceApp extends StatelessWidget {
  const ConacceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conacce TV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: Env.isConfigured ? const SplashScreen() : const _NotConfigured(),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Conacce TV : connexion à la base non configurée.', textAlign: TextAlign.center))),
      );
}
