import 'dart:convert';

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
    this.isPriority = false,
    this.adBreaks = const [],
    this.airExtra = Duration.zero,
    this.breaksSig = '',
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
  bool get hasBand => showBand && kind != 'habillage' && kind != 'pub' && ((artist ?? '').trim().isNotEmpty || (song ?? '').trim().isNotEmpty);

  /// Rendez-vous prioritaire : passe à son heure exacte, même si un autre rendez-vous occupe ce moment.
  final bool isPriority;

  /// Coupures publicitaires du film (instants choisis dans la régie).
  final List<TvAdBreak> adBreaks;

  /// Durée totale des pubs du film : il occupe l'antenne [duration] + [airExtra].
  final Duration airExtra;
  Duration get airDuration => duration + airExtra;

  /// Empreinte des coupures (pour savoir si la régie les a changées).
  final String breaksSig;

  /// Une publicité : ne passe jamais seule, seulement pendant une coupure.
  bool get isAd => kind == 'pub';

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
        isPriority: m['is_priority'] as bool? ?? false,
        adBreaks: TvAdBreak.listFrom(m['ad_breaks']),
        breaksSig: m['ad_breaks'] is List && (m['ad_breaks'] as List).isNotEmpty ? jsonEncode(m['ad_breaks']) : '',
        airExtra: Duration(seconds: (m['air_extra'] as num?)?.toInt() ?? 0),
      );
}

/// Texte affiché à l'écran (annonce pendant la pub, ou « Suite de votre programme » à la reprise).
/// [x], [y] : coin haut-gauche en fraction de l'écran ; [size] : hauteur du texte en % de l'écran ;
/// [delay] : secondes après le début ; [length] : durée d'affichage (0 = tout le temps).
class TvScreenText {
  const TvScreenText({this.on = true, this.text = '', this.x = 0.05, this.y = 0.08, this.size = 5, this.delay = 0, this.length = 0});

  final bool on;
  final String text;
  final double x, y, size, delay, length;

  static double _d(Object? v, double def, double lo, double hi) => v is num ? v.toDouble().clamp(lo, hi).toDouble() : def;

  static TvScreenText? from(Object? v, {String defText = '', double defY = 0.08, double defLen = 0}) {
    if (v is! Map) return null;
    return TvScreenText(
      on: v['on'] != false,
      text: (v['t'] as String?)?.trim().isNotEmpty == true ? (v['t'] as String).trim() : defText,
      x: _d(v['x'], 0.05, 0, 1),
      y: _d(v['y'], defY, 0, 1),
      size: _d(v['s'], 5, 1, 20),
      delay: _d(v['d'], 0, 0, 3600),
      length: _d(v['l'], defLen, 0, 3600),
    );
  }

  /// Affiché à [sec] secondes après le début de la séquence ?
  bool visibleAt(double sec) => on && text.isNotEmpty && sec >= delay && (length <= 0 || sec < delay + length);
}

/// Une coupure publicitaire dans un film.
class TvAdBreak {
  const TvAdBreak({required this.at, required this.adIds, this.text, this.resume});

  /// Instant de la coupure dans le film.
  final Duration at;

  /// Les spots de l'écran publicitaire, dans l'ordre (autant qu'on veut).
  final List<String> adIds;
  final TvScreenText? text;
  final TvScreenText? resume;

  static List<TvAdBreak> listFrom(Object? v) {
    if (v is! List) return const [];
    final out = <TvAdBreak>[];
    for (final b in v) {
      if (b is! Map || b['at'] is! num) continue;
      final ids = b['ads'] is List ? (b['ads'] as List).whereType<String>().toList() : <String>[if (b['ad'] is String) b['ad'] as String];
      if (ids.isEmpty) continue;
      out.add(TvAdBreak(
        at: Duration(milliseconds: ((b['at'] as num) * 1000).round()),
        adIds: ids,
        text: TvScreenText.from(b['txt'], defText: 'Publicité'),
        resume: TvScreenText.from(b['res'], defText: 'Suite de votre programme sur Conacce TV', defY: 0.82, defLen: 6),
      ));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }
}

/// Jour spécial (Noël, Pâques, congrès…) préparé dans la régie.
/// Pendant sa plage horaire, si [replaceRegular], les rendez-vous qui se répètent
/// (chaque jour, chaque semaine) ne passent pas : seule la journée spéciale passe.
class TvSpecialDay {
  const TvSpecialDay({required this.id, required this.name, required this.startsAt, required this.endsAt, this.replaceRegular = true});

  final String id;
  final String name;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool replaceRegular;

  bool covers(DateTime t) => !t.isBefore(startsAt) && t.isBefore(endsAt);

  factory TvSpecialDay.fromMap(Map<String, dynamic> m) => TvSpecialDay(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        startsAt: DateTime.parse(m['starts_at'] as String).toUtc(),
        endsAt: DateTime.parse(m['ends_at'] as String).toUtc(),
        replaceRegular: m['replace_regular'] as bool? ?? true,
      );
}

/// Ce qui passe à un moment donné : le programme, son heure de début et de fin.
class TvSlot {
  const TvSlot(this.program, this.start, this.end, {this.parent, this.adBreak, this.resumeBreak, DateTime? segStart, DateTime? textFrom})
      : _segStart = segStart,
        _textFrom = textFrom;

  /// La vidéo qui passe (le film, ou la pub pendant une coupure).
  final TvProgram program;

  /// Début « virtuel » : [positionAt] donne la position dans la vidéo (la suite d'un film reprend où il a été coupé).
  final DateTime start;
  final DateTime end;

  /// Pendant une pub : le film coupé.
  final TvProgram? parent;

  /// Pendant une pub : la coupure (texte d'annonce).
  final TvAdBreak? adBreak;

  /// Suite d'un film après une pub : la coupure précédente (message « Suite de votre programme »).
  final TvAdBreak? resumeBreak;
  final DateTime? _segStart;

  /// Heure réelle où ce morceau a commencé à l'antenne.
  DateTime get segStart => _segStart ?? start;

  /// Début de l'écran publicitaire (le texte d'annonce se compte depuis là, sur tous les spots).
  final DateTime? _textFrom;
  DateTime get textFrom => _textFrom ?? segStart;

  /// Le programme à afficher (titre) : le film, même pendant sa pub.
  TvProgram get show => parent ?? program;

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
  TvSchedule(List<TvProgram> programs,
      {DateTime? anchor, List<TvSpecialDay> specialDays = const [], this.loopRepeat = true})
      : anchor = anchor ?? defaultAnchor,
        _blackouts = specialDays.where((d) => d.replaceRegular).toList(),
        _byId = {for (final p in programs) p.id: p},
        fixed = programs.where((p) => p.isFixed && !p.isAd && p.duration > Duration.zero).toList(),
        loop = (programs.where((p) => !p.isFixed && !p.isAd && p.duration > Duration.zero).toList()
          ..sort((a, b) => a.position != b.position ? a.position.compareTo(b.position) : a.id.compareTo(b.id)));

  final List<TvProgram> fixed;
  final List<TvProgram> loop;
  final Map<String, TvProgram> _byId;

  /// Les publicités utilisées par un film (pour la réserve hors connexion).
  Iterable<TvProgram> adsOf(TvProgram p) sync* {
    for (final b in p.adBreaks) {
      for (final id in b.adIds) {
        final ad = _byId[id];
        if (ad != null) yield ad;
      }
    }
  }

  /// Jours spéciaux qui remplacent la grille habituelle.
  final List<TvSpecialDay> _blackouts;

  /// Un rendez-vous qui se répète ne passe pas pendant un jour spécial « remplaçant ».
  bool _hidden(DateTime start) => _blackouts.any((d) => d.covers(start));

  /// Point de départ commun de la boucle (le même pour tout le monde).
  /// Réglé par la régie : « Play » après « Stop » fait repartir la playlist du n° 1.
  final DateTime anchor;

  /// Case « Lire en boucle » de la régie. Décochée : la playlist passe une seule fois depuis [anchor],
  /// puis l'écran d'attente jusqu'au prochain rendez-vous.
  final bool loopRepeat;
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
          if (_hidden(start)) continue;
          yield TvSlot(p, start, start.add(p.airDuration));
        }
        continue;
      }
      if (p.repeatWeekly) {
        final weeks = now.difference(s).inDays ~/ 7;
        for (final w in [weeks - 1, weeks, weeks + 1]) {
          if (w < 0) continue;
          final start = s.add(Duration(days: 7 * w));
          if (_hidden(start)) continue;
          yield TvSlot(p, start, start.add(p.airDuration));
        }
        continue;
      }
      yield TvSlot(p, s, s.add(p.airDuration));
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
  /// Un film avec des coupures est découpé : morceau de film, pub, suite du film…
  TvSlot? at(DateTime now) {
    final base = _baseAt(now);
    return base == null ? null : _segment(base, now.toUtc());
  }

  /// Le morceau (film ou pub) d'un passage [base] qui passe à [t].
  TvSlot _segment(TvSlot base, DateTime t) {
    final p = base.program;
    if (p.adBreaks.isEmpty) return base;
    var air = Duration.zero; // temps d'antenne écoulé depuis le début du passage
    var film = Duration.zero; // position dans le film
    TvAdBreak? prev;
    TvSlot clip(DateTime start, DateTime segStart, DateTime segEnd, TvProgram prog, {TvAdBreak? ad, TvAdBreak? res, DateTime? textFrom}) {
      final end = segEnd.isAfter(base.end) ? base.end : segEnd;
      return TvSlot(prog, start, end, parent: prog == p ? null : p, adBreak: ad, resumeBreak: res, segStart: segStart, textFrom: textFrom);
    }

    for (final b in p.adBreaks) {
      if (b.at <= film || b.at >= p.duration) continue;
      final spots = [for (final id in b.adIds) if (_byId[id] != null && _byId[id]!.duration > Duration.zero) _byId[id]!];
      if (spots.isEmpty) continue;
      // Morceau de film jusqu'à la coupure.
      final s0 = base.start.add(air), s1 = s0.add(b.at - film);
      if (t.isBefore(s1)) return clip(s0.subtract(film), s0, s1, p, res: prev);
      // L'écran publicitaire : les spots l'un après l'autre.
      var a0 = s1;
      for (final ad in spots) {
        final a1 = a0.add(ad.duration);
        if (t.isBefore(a1)) return clip(a0, a0, a1, ad, ad: b, textFrom: s1);
        a0 = a1;
      }
      air += (b.at - film) + a0.difference(s1);
      film = b.at;
      prev = b;
    }
    final s0 = base.start.add(air);
    return clip(s0.subtract(film), s0, s0.add(p.duration - film), p, res: prev);
  }

  /// Le passage (film entier, pubs comprises) à [now].
  TvSlot? _baseAt(DateTime now) {
    final t = now.toUtc();
    // 1. Un rendez-vous en cours passe avant la boucle.
    TvSlot? current;
    for (final slot in _fixedAround(t)) {
      if (!t.isBefore(slot.start) && t.isBefore(slot.end)) {
        // Le rendez-vous prioritaire l'emporte ; sinon, le plus récent coupe le précédent.
        final better = current == null ||
            (slot.program.isPriority && !current.program.isPriority) ||
            (slot.program.isPriority == current.program.isPriority && slot.start.isAfter(current.start));
        if (better) current = slot;
      }
    }
    if (current != null) return current;
    // 2. Sinon, la boucle, qui tourne sans fin depuis [anchor].
    if (loop.isEmpty) return null;
    final totalMs = loop.fold<int>(0, (a, p) => a + p.airDuration.inMilliseconds);
    if (totalMs <= 0) return null;
    final raw = t.difference(anchor).inMilliseconds;
    // Boucle décochée : un seul tour de playlist, puis l'écran d'attente.
    if (!loopRepeat && (raw < 0 || raw >= totalMs)) return null;
    var inLoop = raw % totalMs;
    if (inLoop < 0) inLoop += totalMs;
    for (final p in loop) {
      final d = p.airDuration.inMilliseconds;
      if (inLoop < d) {
        final start = t.subtract(Duration(milliseconds: inLoop));
        var end = start.add(p.airDuration);
        // Un rendez-vous coupe la boucle à son heure exacte.
        final next = _nextFixedAfter(t);
        if (next != null && next.start.isBefore(end)) end = next.start;
        return TvSlot(p, start, end);
      }
      inLoop -= d;
    }
    return null;
  }

  /// Le prochain rendez-vous après [t] (affiché sur l'écran d'attente).
  TvSlot? nextFixedAfter(DateTime t) => _nextFixedAfter(t.toUtc());

  /// Le morceau suivant (film, pub ou programme suivant).
  TvSlot? after(TvSlot slot) => at(slot.end.add(const Duration(milliseconds: 500)));

  /// Le prochain programme différent (pour « À suivre » : on saute les pubs et la suite du même film).
  TvSlot? nextShow(TvSlot slot) {
    var s = after(slot);
    for (var i = 0; i < 24 && s != null && (s.show.id == slot.show.id || s.program.isAd); i++) {
      s = after(s);
    }
    return s;
  }
}

/// État de la chaîne, piloté par la régie : à l'antenne, en pause ou arrêtée.
class TvChannel {
  const TvChannel({this.status = 'playing', DateTime? anchor, this.pausedAt, this.loopRepeat = true}) : _anchor = anchor;

  /// Case « Lire en boucle » de la régie.
  final bool loopRepeat;

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
        loopRepeat: m['loop_repeat'] as bool? ?? true,
      );
}
