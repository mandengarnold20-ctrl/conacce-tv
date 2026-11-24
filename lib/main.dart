import 'package:flutter/foundation.dart' show kIsWeb, LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'core/config/env.dart';
import 'core/device.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/shell.dart';

/// Point d'entrée de Conacce TV.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Polices Poppins et Urbanist : enregistrées dans l'appli (assets/google_fonts),
  // donc identiques sur Android, iPhone, télé et site, même avec une connexion faible.
  LicenseRegistry.addLicense(() async* {
    for (final f in ['OFL-Poppins.txt', 'OFL-Urbanist.txt']) {
      yield LicenseEntryWithLineBreaks(const ['google_fonts'], await rootBundle.loadString('assets/google_fonts/$f'));
    }
  });

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
  await detectDevice();
  if (isTvDevice) {
    // Téléviseur : toujours en paysage, plein écran, et l'écran de veille ne coupe jamais la chaîne.
    await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    if (!kIsWeb) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  } else {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

  runApp(ProviderScope(
    // Téléviseur : l'appli s'ouvre directement sur la chaîne.
    overrides: [if (isTvDevice) currentTabProvider.overrideWith((ref) => AppTab.tv)],
    child: const ConacceApp(),
  ));
}

class ConacceApp extends StatelessWidget {
  const ConacceApp({super.key});

  @override
  Widget build(BuildContext context) {
    final tv = isTvDevice;
    return MaterialApp(
      title: 'Conacce TV',
      debugShowCheckedModeBanner: false,
      // Taille du texte : on suit le réglage du téléphone (personnes qui voient mal),
      // mais sans dépasser +15 %, pour que les écrans gardent leur mise en page.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.9,
        maxScaleFactor: 1.15,
        child: child ?? const SizedBox.shrink(),
      ),
      // Télécommande : le bouton central (OK) valide, comme la touche Entrée.
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      // Téléviseur : l'élément choisi à la télécommande est bien visible (halo jaune).
      theme: tv
          ? AppTheme.dark.copyWith(focusColor: AppColors.sunYellow.withAlpha(90), hoverColor: AppColors.sunYellow.withAlpha(40))
          : AppTheme.dark,
      home: !Env.isConfigured
          ? const _NotConfigured()
          : tv
              ? const AppShell()
              : const SplashScreen(),
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
