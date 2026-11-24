import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Appli Android : les vidéos de la grille sont gardées dans le téléphone, comme le logo et le bandeau.
///
/// - La régie envoie la grille ; l'appli télécharge à l'avance chaque programme en 360p
///   (≈ 0,75 Mbit/s, environ 5,5 Mo par minute de vidéo).
/// - Quand la grille change, les nouveaux programmes sont téléchargés et ceux qui ne servent plus
///   sont effacés du téléphone.
/// - Sans internet, la chaîne continue avec les vidéos gardées, à la bonne heure de la grille.
///
/// Chaque vidéo est rangée dans son propre dossier (morceaux d'image, morceaux de son et liste de
/// lecture). Le dossier n'est utilisable qu'une fois entièrement téléchargé ; un téléchargement
/// coupé reprend là où il s'était arrêté.

/// Hauteur d'image gardée dans le téléphone (360p : léger, net sur un écran de téléphone).
const _targetHeight = 360;

/// Place maximale utilisée sur le téléphone (≈ 4 h 30 de programmes en 360p).
const _maxBytes = 1536 * 1024 * 1024;

Directory? _root;
Future<Directory>? _rootF;
List<({String id, String url})> _plan = const [];
String _planJson = '';
final Set<String> _ready = {};
int _bytes = 0;
bool _busy = false;
bool _wake = false;
Timer? _retry;

Future<Directory> _dir() => _rootF ??= () async {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/ctv_offline');
      await d.create(recursive: true);
      _root = d;
      await _scan();
      return d;
    }();

/// Identifiant Cloudflare de la vidéo (32 caractères) : même vidéo quelle que soit l'adresse exacte.
String? _idOf(String url) => RegExp(r'[0-9a-f]{32}').firstMatch(url)?.group(0);

Future<void> _scan() async {
  final d = _root;
  if (d == null) return;
  _ready.clear();
  var total = 0;
  await for (final e in d.list()) {
    if (e is! Directory) continue;
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (File('${e.path}/master.m3u8').existsSync()) _ready.add(name);
    await for (final f in e.list()) {
      if (f is File) total += await f.length();
    }
  }
  _bytes = total;
}

/// Reçoit la grille à préparer (liste JSON de {url, title}, dans l'ordre d'importance).
void offlinePlan(String json) {
  if (json == _planJson) return;
  _planJson = json;
  final items = <({String id, String url})>[];
  final seen = <String>{};
  try {
    for (final m in (jsonDecode(json) as List).cast<Map>()) {
      final url = '${m['url']}'.split('?').first;
      final id = _idOf(url);
      if (id == null || !url.endsWith('.m3u8') || !seen.add(id)) continue;
      items.add((id: id, url: url));
    }
  } catch (_) {
    return;
  }
  _plan = items;
  _kick();
}

void _kick() {
  if (_busy) {
    _wake = true;
    return;
  }
  _retry?.cancel();
  unawaited(_work());
}

Future<void> _work() async {
  _busy = true;
  var failed = false;
  try {
    final d = await _dir();
    do {
      _wake = false;
      final wanted = {for (final p in _plan) p.id};
      // Grille vide (pas encore reçue) : on ne touche à rien.
      if (wanted.isEmpty) break;
      // Ce qui n'est plus dans la grille est effacé du téléphone.
      for (final e in await d.list().toList()) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last.replaceAll('.part', '');
        if (!wanted.contains(name)) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
      await _scan();
      for (final p in _plan) {
        if (_wake) break;
        if (_ready.contains(p.id)) continue;
        if (_bytes >= _maxBytes) break;
        try {
          await _download(d, p.id, p.url);
          _ready.add(p.id);
        } catch (_) {
          failed = true; // pas de réseau, ou vidéo indisponible : on réessaiera
        }
        await _scan();
      }
    } while (_wake);
  } catch (_) {
    failed = true;
  } finally {
    _busy = false;
  }
  if (_wake) return _kick();
  // Réseau coupé ou téléchargement interrompu : nouvel essai dans une minute.
  if (failed) _retry = Timer(const Duration(minutes: 1), _kick);
}

final _client = http.Client();

Future<String> _text(Uri u) async {
  final r = await _client.get(u).timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) throw HttpException('HTTP ${r.statusCode}', uri: u);
  return utf8.decode(r.bodyBytes);
}

Future<void> _file(Uri u, File f) async {
  if (f.existsSync() && f.lengthSync() > 0) return; // déjà là (reprise)
  final tmp = File('${f.path}.tmp');
  for (var attempt = 0;; attempt++) {
    try {
      final req = await _client.send(http.Request('GET', u)).timeout(const Duration(seconds: 30));
      if (req.statusCode != 200) throw HttpException('HTTP ${req.statusCode}', uri: u);
      final sink = tmp.openWrite();
      await req.stream.timeout(const Duration(seconds: 45)).pipe(sink);
      await tmp.rename(f.path);
      return;
    } catch (e) {
      if (attempt >= 3) rethrow;
      await Future<void>.delayed(Duration(seconds: 2 + attempt * 3));
    }
  }
}

String? _attr(String line, String key) {
  final m = RegExp('$key=(?:"([^"]*)"|([^,]*))').firstMatch(line);
  return m == null ? null : (m.group(1) ?? m.group(2));
}

/// Télécharge une liste de lecture (image ou son) et tous ses morceaux, puis l'écrit en version locale.
Future<void> _playlist(Uri u, Directory dir, String prefix) async {
  final lines = const LineSplitter().convert(await _text(u));
  final out = <String>[];
  final jobs = <(Uri, File)>[];
  var n = 0;
  for (final line in lines) {
    if (line.startsWith('#EXT-X-MAP:')) {
      final uri = _attr(line, 'URI');
      if (uri == null) continue;
      final name = '${prefix}_init.mp4';
      jobs.add((u.resolve(uri), File('${dir.path}/$name')));
      out.add(line.replaceFirst('URI="$uri"', 'URI="$name"'));
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      final name = '${prefix}_${n++}.m4s';
      jobs.add((u.resolve(line), File('${dir.path}/$name')));
      out.add(name);
    } else {
      out.add(line);
    }
  }
  // Trois morceaux à la fois : plus rapide sur les réseaux à forte latence.
  var i = 0;
  Future<void> worker() async {
    while (i < jobs.length) {
      final j = jobs[i++];
      await _file(j.$1, j.$2);
    }
  }

  await Future.wait([worker(), worker(), worker()]);
  await File('${dir.path}/$prefix.m3u8').writeAsString('${out.join('\n')}\n');
}

Future<void> _download(Directory root, String id, String url) async {
  final base = Uri.parse(url);
  final lines = const LineSplitter().convert(await _text(base));
  String? audioLine;
  final variants = <({String inf, String uri, int h})>[];
  for (var k = 0; k < lines.length; k++) {
    final l = lines[k];
    if (l.startsWith('#EXT-X-MEDIA:') && l.contains('TYPE=AUDIO') && audioLine == null) audioLine = l;
    if (l.startsWith('#EXT-X-STREAM-INF:') && k + 1 < lines.length) {
      final res = _attr(l, 'RESOLUTION') ?? '';
      final h = int.tryParse(res.split('x').last) ?? 0;
      variants.add((inf: l, uri: lines[k + 1].trim(), h: h));
    }
  }
  if (variants.isEmpty) throw const FormatException('liste de lecture vide');
  variants.sort((a, b) => a.h.compareTo(b.h));
  // La qualité la plus proche de 360p sans la dépasser (sinon la plus légère).
  final pick = variants.lastWhere((v) => v.h <= _targetHeight, orElse: () => variants.first);

  final part = Directory('${root.path}/$id.part');
  await part.create(recursive: true);
  await _playlist(base.resolve(pick.uri), part, 'v');
  final master = StringBuffer('#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-INDEPENDENT-SEGMENTS\n');
  final audioUri = audioLine == null ? null : _attr(audioLine, 'URI');
  if (audioLine != null && audioUri != null) {
    await _playlist(base.resolve(audioUri), part, 'a');
    master.writeln(audioLine.replaceFirst('URI="$audioUri"', 'URI="a.m3u8"'));
  }
  master
    ..writeln(pick.inf)
    ..writeln('v.m3u8');
  await File('${part.path}/master.m3u8').writeAsString(master.toString());
  final done = Directory('${root.path}/$id');
  if (done.existsSync()) await done.delete(recursive: true);
  await part.rename(done.path);
}

/// Chemin de la vidéo gardée dans le téléphone, si elle est entièrement téléchargée.
String? offlineLocalFile(String url) {
  final d = _root;
  if (d == null) {
    unawaited(_dir());
    return null;
  }
  final id = _idOf(url);
  if (id == null || !_ready.contains(id)) return null;
  final f = File('${d.path}/$id/master.m3u8');
  return f.existsSync() ? f.path : null;
}

/// État de la réserve : (programmes prêts, total, Mo dans le téléphone, téléchargement en cours).
({int ready, int total, double mb, bool busy})? offlineStatus() {
  if (_plan.isEmpty) return null;
  final ready = _plan.where((p) => _ready.contains(p.id)).length;
  return (ready: ready, total: _plan.length, mb: _bytes / (1024 * 1024), busy: _busy);
}
