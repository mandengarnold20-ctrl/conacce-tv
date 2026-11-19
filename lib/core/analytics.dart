import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Statistiques anonymes (aucune donnée personnelle) : visiteurs, vues de cultes,
/// spectateurs de la TV, auditeurs de la radio, lectures des Œuvres d'Or.
class Analytics {
  Analytics._();

  static String? _visitorId;

  static Future<String> _id() async {
    if (_visitorId != null) return _visitorId!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('visitor_id');
    if (id == null) {
      final r = Random.secure();
      final b = List<int>.generate(16, (_) => r.nextInt(256));
      b[6] = (b[6] & 0x0f) | 0x40;
      b[8] = (b[8] & 0x3f) | 0x80;
      final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      id = '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
      await prefs.setString('visitor_id', id);
    }
    return _visitorId = id;
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'desktop',
    };
  }

  static Future<void> _track(String kind, [String? itemId]) async {
    try {
      await Supabase.instance.client.rpc('track', params: {
        'p_kind': kind,
        'p_visitor': await _id(),
        'p_item': itemId,
        'p_platform': _platform,
      });
    } catch (_) {
      // Une statistique perdue n'a aucune conséquence pour l'utilisateur.
    }
  }

  /// Identifiant anonyme de l'appareil (anti-spam des commentaires).
  static Future<String> visitorId() => _id();

  static Future<void> visit() => _track('visit');
  static Future<void> sermonPlay(String id) => _track('play', id);
  static Future<void> liveView() => _track('live');
  static Future<void> radioListen() => _track('radio');
  static Future<void> workRead(String id) => _track('read', id);
}
