import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Conacce TV en direct, mis à jour instantanément (temps réel).
final liveStreamProvider = StreamProvider<LiveStream?>((ref) {
  return _db.from('live_stream').stream(primaryKey: ['id']).map((rows) => rows.isEmpty ? null : LiveStream.fromMap(rows.first));
});

/// Radio Dunamis FM, mise à jour instantanément.
final radioProvider = StreamProvider<RadioStation?>((ref) {
  return _db.from('radio').stream(primaryKey: ['id']).map((rows) => rows.isEmpty ? null : RadioStation.fromMap(rows.first));
});

/// Filtre des cultes (null = tous).
final sermonCategoryProvider = StateProvider<SermonCategory?>((ref) => null);

/// Cultes publiés, du plus récent au plus ancien.
final sermonsProvider = FutureProvider.family<List<Sermon>, SermonCategory?>((ref, category) async {
  var q = _db.from('sermons').select().eq('is_published', true);
  if (category != null) q = q.eq('category', category.name);
  final rows = await q.order('preached_on', ascending: false, nullsFirst: false).order('created_at', ascending: false).limit(200);
  return rows.map(Sermon.fromMap).toList();
});

/// Recherche dans les cultes (titre, orateur, description).
Future<List<Sermon>> searchSermons(String query) async {
  final q = query.replaceAll(RegExp(r'[%,()]'), ' ').trim();
  final rows = await _db
      .from('sermons')
      .select()
      .eq('is_published', true)
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
