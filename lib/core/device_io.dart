import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

bool _tv = false;

/// L'appli tourne-t-elle sur un téléviseur (Android TV / Google TV) ?
bool get isTvDevice => _tv;

/// Téléviseur reconnu par le système Android lui-même, jamais par la taille de l'écran :
/// un téléphone ou une tablette, même grand ou tourné, garde l'appli téléphone.
Future<void> detectDevice() async {
  if (!Platform.isAndroid) return;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final f = info.systemFeatures;
    // 1. Android TV / Google TV / Fire TV : interface « leanback » (jamais présente sur un téléphone).
    // 2. Boîtier TV sans Android TV officiel : pas d'écran tactile (tout téléphone et toute tablette en a un).
    _tv = f.contains('android.software.leanback') ||
        f.contains('android.software.leanback_only') ||
        f.contains('amazon.hardware.fire_tv') ||
        (f.isNotEmpty && !f.contains('android.hardware.touchscreen'));
  } catch (_) {
    _tv = false;
  }
}
