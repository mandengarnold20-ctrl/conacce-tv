import 'models.dart' show parseYoutubeId;

/// Un programme de la chaîne Conacce TV (grille 24 h/24).
class TvProgram {
  const TvProgram({
    required this.id,
    required this.title,
    required this.source,
    required this.videoUrl,
    required this.duration,
    required this.position,
    this.startAt,
    this.repeatDaily = false,
    this.repeatWeekly = false,
    this.artist,
    this.song,
    this.showBand = true,
    this.kind = 'clip',
  });

  final String id;
  final String title;

  /// « youtube » (lien) ou « file » (vidéo téléversée sur Cloudflare Stream).
  final String source;
  final String videoUrl;
  final Duration duration;
  final int position;

  /// Rendez-vous à heure fixe ; null = le programme tourne dans la boucle.
  final DateTime? startAt;
  final bool repeatDaily;
  final bool repeatWeekly;

  /// Bande artiste / titre (habillage) : affichée si l'artiste ou le titre est renseigné.
  final String? artist;
  final String? song;
  final bool showBand;

  /// clip, emission ou habillage (jingle, spot : jamais de bande).
  final String kind;
  bool get hasBand => showBand && kind != 'habillage' && ((artist ?? '').trim().isNotEmpty || (song ?? '').trim().isNotEmpty);

  bool get isFixed => startAt != null;
  String? get youtubeId => parseYoutubeId(videoUrl);
  bool get isYoutube => source == 'youtube' && youtubeId != null;

  /// Adresse HLS d'une vidéo Cloudflare Stream (lien « watch », iframe, manifest ou simple identifiant).
  String get fileUrl {
    final u = videoUrl.trim();
    final path = Uri.tryParse(u)?.path ?? '';
    if (path.endsWith('.m3u8') || path.endsWith('.mp4') || path.endsWith('.mpd')) return u;
    final id = RegExp(r'[0-9a-f]{32}').firstMatch(u)?.group(0);
    if (id == null) return u;
    final host = Uri.tryParse(u)?.host ?? '';
    final base = host.endsWith('cloudflarestream.com') ? 'https://$host' : 'https://videodelivery.net';
    return '$base/$id/manifest/video.m3u8';
  }

  factory TvProgram.fromMap(Map<String, dynamic> m) => TvProgram(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        source: m['source'] as String? ?? 'youtube',
        videoUrl: m['video_url'] as String? ?? '',
        duration: Duration(seconds: (m['duration'] as num?)?.toInt() ?? 0),
        position: (m['position'] as num?)?.toInt() ?? 0,
        startAt: m['start_at'] == null ? null : DateTime.parse(m['start_at'] as String).toUtc(),
        repeatDaily: m['repeat_daily'] as bool? ?? false,
        repeatWeekly: m['repeat_weekly'] as bool? ?? false,
        artist: m['artist'] as String?,
        song: m['song'] as String?,
        showBand: m['show_band'] as bool? ?? true,
        kind: m['kind'] as String? ?? 'clip',
      );
}

/// Ce qui passe à un moment donné : le programme, son heure de début et de fin.
class TvSlot {
  const TvSlot(this.program, this.start, this.end);

  final TvProgram program;
  final DateTime start;
  final DateTime end;

  /// Identifiant unique de ce passage (le même programme peut repasser plus tard).
  String get key => '${program.id}@${start.millisecondsSinceEpoch}';

  /// Où en est la vidéo à l'instant [now].
  Duration positionAt(DateTime now) {
    final p = now.difference(start);
    return p.isNegative ? Duration.zero : p;
  }
}

/// La grille de la chaîne : boucle continue + rendez-vous à heure fixe.
/// Calcul identique sur tous les téléphones, à partir de l'heure du serveur.
class TvSchedule {
  TvSchedule(List<TvProgram> programs, {DateTime? anchor})
      : anchor = anchor ?? defaultAnchor,
        fixed = programs.where((p) => p.isFixed && p.duration > Duration.zero).toList(),
        loop = (programs.where((p) => !p.isFixed && p.duration > Duration.zero).toList()
          ..sort((a, b) => a.position != b.position ? a.position.compareTo(b.position) : a.id.compareTo(b.id)));

  final List<TvProgram> fixed;
  final List<TvProgram> loop;

  /// Point de départ commun de la boucle (le même pour tout le monde).
  /// Réglé par la régie : « Play » après « Stop » fait repartir la playlist du n° 1.
  final DateTime anchor;
  static final DateTime defaultAnchor = DateTime.utc(2026, 1, 1);

  bool get isEmpty => fixed.isEmpty && loop.isEmpty;

  /// Les passages des rendez-vous autour de [now] (veille, jour même, lendemain pour les quotidiens).
  Iterable<TvSlot> _fixedAround(DateTime now) sync* {
    for (final p in fixed) {
      final s = p.startAt!;
      if (p.repeatDaily) {
        final days = now.difference(s).inDays;
        for (final d in [days - 1, days, days + 1]) {
          if (d < 0) continue;
          final start = s.add(Duration(days: d));
          yield TvSlot(p, start, start.add(p.duration));
        }
        continue;
      }
      if (p.repeatWeekly) {
        final weeks = now.difference(s).inDays ~/ 7;
        for (final w in [weeks - 1, weeks, weeks + 1]) {
          if (w < 0) continue;
          final start = s.add(Duration(days: 7 * w));
          yield TvSlot(p, start, start.add(p.duration));
        }
        continue;
      }
      yield TvSlot(p, s, s.add(p.duration));
    }
  }

  /// Le prochain rendez-vous qui commence après [t].
  TvSlot? _nextFixedAfter(DateTime t) {
    TvSlot? best;
    for (final slot in _fixedAround(t)) {
      if (slot.start.isAfter(t) && (best == null || slot.start.isBefore(best.start))) best = slot;
    }
    return best;
  }

  /// Ce qui passe à [now] (null si la grille est vide ou s'il n'y a rien à cette heure).
  TvSlot? at(DateTime now) {
    final t = now.toUtc();
    // 1. Un rendez-vous en cours passe avant la boucle.
    TvSlot? current;
    for (final slot in _fixedAround(t)) {
      if (!t.isBefore(slot.start) && t.isBefore(slot.end)) {
        if (current == null || slot.start.isAfter(current.start)) current = slot;
      }
    }
    if (current != null) return current;
    // 2. Sinon, la boucle, qui tourne sans fin depuis [anchor].
    if (loop.isEmpty) return null;
    final totalMs = loop.fold<int>(0, (a, p) => a + p.duration.inMilliseconds);
    if (totalMs <= 0) return null;
    var inLoop = t.difference(anchor).inMilliseconds % totalMs;
    if (inLoop < 0) inLoop += totalMs;
    for (final p in loop) {
      final d = p.duration.inMilliseconds;
      if (inLoop < d) {
        final start = t.subtract(Duration(milliseconds: inLoop));
        var end = start.add(p.duration);
        // Un rendez-vous coupe la boucle à son heure exacte.
        final next = _nextFixedAfter(t);
        if (next != null && next.start.isBefore(end)) end = next.start;
        return TvSlot(p, start, end);
      }
      inLoop -= d;
    }
    return null;
  }

  /// Le programme suivant (pour « À suivre »).
  TvSlot? after(TvSlot slot) => at(slot.end.add(const Duration(milliseconds: 500)));
}

/// État de la chaîne, piloté par la régie : à l'antenne, en pause ou arrêtée.
class TvChannel {
  const TvChannel({this.status = 'playing', DateTime? anchor, this.pausedAt}) : _anchor = anchor;

  final String status;
  final DateTime? _anchor;
  final DateTime? pausedAt;

  DateTime get anchor => _anchor ?? TvSchedule.defaultAnchor;
  bool get isPaused => status == 'paused';
  bool get isStopped => status == 'stopped';

  factory TvChannel.fromMap(Map<String, dynamic> m) => TvChannel(
        status: m['status'] as String? ?? 'playing',
        anchor: m['anchor'] == null ? null : DateTime.parse(m['anchor'] as String).toUtc(),
        pausedAt: m['paused_at'] == null ? null : DateTime.parse(m['paused_at'] as String).toUtc(),
      );
}
