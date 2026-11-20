import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'tv_schedule.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Conacce TV en direct, mis à jour instantanément (temps réel).
/// Le direct ne passe devant la programmation que si OBS envoie vraiment l'image :
/// le flux est vérifié toutes les 15 s (un direct « allumé » mais muet ne bloque plus la chaîne).
final liveStreamProvider = StreamProvider<LiveStream?>((ref) {
  final ctrl = StreamController<LiveStream?>();
  LiveStream? row;
  var airing = false;
  var misses = 0;
  var busy = false;
  void emit() {
    if (ctrl.isClosed) return;
    final r = row;
    ctrl.add(r?.withAiring(airing));
  }

  Future<void> probe() async {
    final r = row;
    if (r == null || !r.isLive || r.isLink || (r.hlsUrl?.isEmpty ?? true)) {
      airing = false;
      misses = 0;
      return emit();
    }
    if (busy) return;
    busy = true;
    final ok = await hlsIsAiring(r.hlsUrl!);
    busy = false;
    if (ok) {
      airing = true;
      misses = 0;
    } else if (++misses >= 2 || !airing) {
      airing = false;
    }
    emit();
  }

  final sub = _db.from('live_stream').stream(primaryKey: ['id']).listen((rows) {
    row = rows.isEmpty ? null : LiveStream.fromMap(rows.first);
    emit();
    probe();
  }, onError: (Object e, StackTrace st) => ctrl.addError(e, st));
  final timer = Timer.periodic(const Duration(seconds: 15), (_) => probe());
  ref.onDispose(() {
    sub.cancel();
    timer.cancel();
    ctrl.close();
  });
  return ctrl.stream;
});

/// Un flux HLS « à l'antenne » renvoie une liste de lecture ; hors antenne, Cloudflare renvoie une réponse vide.
Future<bool> hlsIsAiring(String url) async {
  try {
    final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    return r.statusCode == 200 && r.body.contains('#EXT');
  } catch (_) {
    return false;
  }
}

/// Programmes de la chaîne 24 h/24 (grille), mis à jour instantanément.
final tvProgramsProvider = StreamProvider<List<TvProgram>>((ref) {
  return _db.from('tv_programs').stream(primaryKey: ['id']).map(
        (rows) => rows.where((r) => r['is_active'] != false).map(TvProgram.fromMap).toList(),
      );
});

/// État de la chaîne (régie) : à l'antenne, en pause ou arrêtée.
final tvChannelProvider = StreamProvider<TvChannel>((ref) {
  return _db.from('tv_channel').stream(primaryKey: ['id']).map(
        (rows) => rows.isEmpty ? const TvChannel() : TvChannel.fromMap(rows.first),
      );
});

/// Écart entre l'horloge du téléphone et celle du serveur : la grille se calcule sur l'heure du serveur,
/// pour que Londres et l'Afrique voient exactement la même chose.
final serverClockOffsetProvider = FutureProvider<Duration>((ref) async {
  try {
    final sent = DateTime.now();
    final res = await _db.rpc('tv_now');
    final received = DateTime.now();
    final server = DateTime.parse(res as String);
    final local = sent.add(received.difference(sent) ~/ 2);
    return server.difference(local);
  } catch (_) {
    return Duration.zero;
  }
});

/// Radio Dunamis FM, mise à jour instantanément.
final radioProvider = StreamProvider<RadioStation?>((ref) {
  return _db.from('radio').stream(primaryKey: ['id']).map((rows) => rows.isEmpty ? null : RadioStation.fromMap(rows.first));
});

/// Filtre des cultes (null = tous).
final sermonCategoryProvider = StateProvider<SermonCategory?>((ref) => null);

/// Rubrique affichée dans l'onglet Vidéos : « cultes » ou « conacce ».
final videoSectionProvider = StateProvider<String>((ref) => 'conacce');

/// Vidéos publiées d'une rubrique (et d'une catégorie), du plus récent au plus ancien.
final sermonsProvider = FutureProvider.family<List<Sermon>, (String, SermonCategory?)>((ref, key) async {
  final (section, category) = key;
  var q = _db.from('sermons').select().eq('is_published', true).eq('section', section);
  if (category != null) q = q.eq('category', category.name);
  final rows = await q.order('preached_on', ascending: false, nullsFirst: false).order('created_at', ascending: false).limit(200);
  return rows.map(Sermon.fromMap).toList();
});

/// Grand écran de l'accueil : les vidéos choisies dans l'admin (« Grand écran de l'accueil »),
/// 7 au maximum, toutes rubriques confondues. Sans choix, les 7 dernières vidéos Conacce.
final featuredVideosProvider = FutureProvider<List<Sermon>>((ref) async {
  final picked = await _db
      .from('sermons')
      .select()
      .eq('is_published', true)
      .eq('is_featured', true)
      .inFilter('section', ['conacce', 'ciu', 'cultes'])
      .order('created_at', ascending: false)
      .limit(7);
  if (picked.isNotEmpty) return picked.map(Sermon.fromMap).toList();
  final latest = await _db.from('sermons').select().eq('is_published', true).eq('section', 'conacce').order('created_at', ascending: false).limit(7);
  return latest.map(Sermon.fromMap).toList();
});

/// Recherche dans les cultes (titre, orateur, description).
Future<List<Sermon>> searchSermons(String query, {String section = 'cultes'}) async {
  final q = query.replaceAll(RegExp(r'[%,()]'), ' ').trim();
  final rows = await _db
      .from('sermons')
      .select()
      .eq('is_published', true)
      .eq('section', section)
      .or('title.ilike.%$q%,speaker.ilike.%$q%,description.ilike.%$q%')
      .order('preached_on', ascending: false, nullsFirst: false)
      .limit(50);
  return rows.map(Sermon.fromMap).toList();
}

Future<Sermon?> sermonById(String id) async {
  final row = await _db.from('sermons').select().eq('id', id).maybeSingle();
  return row == null ? null : Sermon.fromMap(row);
}

/// Œuvres d'Or : à la une d'abord, puis l'ordre choisi par l'admin.
final worksProvider = FutureProvider<List<Work>>((ref) async {
  final rows = await _db.from('works').select().order('is_featured', ascending: false).order('sort_order').order('created_at', ascending: false);
  return rows.map(Work.fromMap).toList();
});

Future<Work?> workById(String id) async {
  final row = await _db.from('works').select().eq('id', id).maybeSingle();
  return row == null ? null : Work.fromMap(row);
}

/// Affiches actives de l'accueil.
final bannersProvider = FutureProvider<List<HomeBanner>>((ref) async {
  final now = DateTime.now().toUtc().toIso8601String();
  final rows = await _db
      .from('home_banners')
      .select()
      .eq('is_active', true)
      .or('starts_at.is.null,starts_at.lte.$now')
      .or('ends_at.is.null,ends_at.gte.$now')
      .order('sort_order');
  return rows.map(HomeBanner.fromMap).toList();
});

final settingsProvider = FutureProvider<AppSettings>((ref) async {
  final row = await _db.from('app_settings').select().eq('id', 1).maybeSingle();
  return row == null ? const AppSettings() : AppSettings.fromMap(row);
});

/// Jour en cours à l'heure de Douala / Lagos (UTC+1) : les messages changent chaque jour.
String todayLagos() {
  final d = DateTime.now().toUtc().add(const Duration(hours: 1));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Messages du jour sous la TV, en temps réel (le plus récent en premier).
final liveCommentsProvider = StreamProvider.autoDispose<List<LiveComment>>((ref) {
  return _db
      .from('live_comments')
      .stream(primaryKey: ['id'])
      .eq('day', todayLagos())
      .order('created_at', ascending: false)
      .limit(200)
      .map((rows) => rows.map(LiveComment.fromMap).toList());
});

/// Envoie un message sous la TV.
Future<void> sendLiveComment({required String name, required String body, required String visitorId}) async {
  await _db.from('live_comments').insert({'name': name.trim(), 'body': body.trim(), 'visitor_id': visitorId});
}

/// Envoie un message à la CONACCE (messagerie).
Future<void> sendMessage({
  required String name,
  required String body,
  required String visitorId,
  String? countryCode,
  String? countryName,
  String? email,
  String? phone,
}) async {
  String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
  await _db.from('messages').insert({
    'name': name.trim(),
    'body': body.trim(),
    'visitor_id': visitorId,
    'country_code': countryCode,
    'country_name': countryName,
    'email': clean(email),
    'phone': clean(phone),
  });
}

/// Album affiché dans la galerie : « conacce » (Conacce Chaplains) ou « ciu ».
final galleryAlbumProvider = StateProvider<String>((ref) => 'conacce');

/// Photos publiées d'un album, les plus récentes d'abord.
final galleryProvider = FutureProvider.family<List<GalleryPhoto>, String>((ref, album) async {
  final rows = await _db
      .from('gallery_photos')
      .select()
      .eq('is_published', true)
      .eq('album', album)
      .order('sort_order')
      .order('taken_on', ascending: false, nullsFirst: false)
      .order('created_at', ascending: false)
      .limit(500);
  return rows.map(GalleryPhoto.fromMap).toList();
});
