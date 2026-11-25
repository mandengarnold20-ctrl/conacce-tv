import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Niveau du son de la vidéo pendant l'annonce (1 = normal) : la musique baisse, la voix passe devant.
final tvDuck = ValueNotifier<double>(1);

VideoPlayerController? _c;
String? _url;

/// Appelé 4 fois par seconde avec la position de l'annonce dans l'horloge de l'antenne :
/// [off] < 0 = pas encore l'heure (fichier préparé à l'avance), sinon nombre de secondes depuis le début de l'annonce.
/// Tout le monde l'entend au même moment ; si on arrive en cours, on la reprend au bon endroit.
void tvVoiceSync(String? url, double off, {bool muted = false}) {
  if (url != _url) {
    final old = _c;
    _c = null;
    _url = url;
    tvDuck.value = 1;
    old?.dispose();
    if (url == null) return;
    final c = VideoPlayerController.networkUrl(Uri.parse(url),
        // La voix se mélange à la vidéo (sans la mettre en pause).
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _c = c;
    c.initialize().then((_) {
      if (_c == c) c.setLooping(false);
    }).catchError((Object _) {});
  }
  final c = _c;
  if (c == null || !c.value.isInitialized) return;
  final d = c.value.duration.inMilliseconds / 1000;
  if (off < 0 || off >= d - 0.05 || muted) {
    if (c.value.isPlaying) c.pause();
    tvDuck.value = 1;
    return;
  }
  final want = Duration(milliseconds: (off * 1000).round());
  if (!c.value.isPlaying) {
    c.setVolume(1);
    c.seekTo(want).then((_) => c.play());
    tvDuck.value = 0.3;
  } else if ((c.value.position - want).inMilliseconds.abs() > 350) {
    c.seekTo(want);
  }
}
