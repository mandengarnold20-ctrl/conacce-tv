import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

bool _tv = false;

/// L'appli tourne-t-elle sur un téléviseur (Android TV / Google TV) ?
bool get isTvDevice => _tv;

/// Android TV / Google TV : l'appareil déclare l'interface « leanback » (télécommande, grand écran).
Future<void> detectDevice() async {
  if (!Platform.isAndroid) return;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    _tv = info.systemFeatures.contains('android.software.leanback') ||
        info.systemFeatures.contains('android.software.leanback_only');
  } catch (_) {
    _tv = false;
  }
}
