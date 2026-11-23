import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';
import 'web_fullscreen.dart';

/// Lecteur vidéo adaptatif (HLS .m3u8 ou MP4) basé sur video_player + chewie.
/// Utilisé par la TV Live (isLive = true) et par la VOD.
///
/// L'écran reste allumé pendant la lecture. Toucher la vidéo affiche les commandes
/// (bouton plein écran) ; tourner le téléphone agrandit la vidéo à tout l'écran.
class HlsVideoPlayer extends StatefulWidget {
  const HlsVideoPlayer({
    super.key,
    required this.url,
    this.isLive = false,
    this.autoPlay = true,
    this.isFile = false,
    this.onStarted,
    this.startAt,
  });

  final String url;
  /// [url] est un chemin de fichier téléchargé (lecture hors connexion).
  final bool isFile;
  /// Appelé une fois quand la lecture démarre (statistiques).
  final VoidCallback? onStarted;
  final bool isLive;
  final bool autoPlay;

  /// Chaîne programmée : position où la vidéo doit être en ce moment (même image pour tout le monde).
  final Duration Function()? startAt;

  @override
  State<HlsVideoPlayer> createState() => _HlsVideoPlayerState();
}

class _HlsVideoPlayerState extends State<HlsVideoPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  Object? _error;

  // Direct en continu : la vidéo ne s'arrête que si l'on appuie soi-même sur pause.
  Timer? _watchdog;
  Duration _lastPosition = Duration.zero;
  int _stalledTicks = 0;
  bool _wasPlayingBeforeHidden = false;

  // Bouton plein écran (web) : visible 10 s après un toucher sur la vidéo.
  bool _showFullscreen = false;
  Timer? _fullscreenTimer;

  void _revealFullscreen() {
    _fullscreenTimer?.cancel();
    if (!_showFullscreen) setState(() => _showFullscreen = true);
    _fullscreenTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _showFullscreen = false);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tant que la vidéo est à l'écran, on autorise la rotation du téléphone.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _init();
    if (widget.isLive) _watchdog = Timer.periodic(const Duration(seconds: 3), (_) => _keepAlive());
  }

  /// Surveille le direct sans jamais le couper pour rien :
  /// - tant que l'image avance, tout va bien (même si le navigateur a signalé une petite erreur
  ///   que hls.js a déjà réparée) ;
  /// - une pause faite à la main est respectée ;
  /// - si l'image reste figée, on relance doucement la lecture, puis on recharge le direct
  ///   seulement après ~15 s sans aucune image.
  bool _stalled = false;

  void _keepAlive() {
    if (!mounted) return;
    if (_error != null) return _retry();
    final video = _video;
    final v = video?.value;
    if (video == null || v == null) return;
    if (v.hasError) {
      // Le lecteur a perdu le fil : on recharge le direct après ~6 s.
      _stalledTicks++;
      if (!_stalled) setState(() => _stalled = true);
      if (_stalledTicks >= 2) {
        _stalledTicks = 0;
        _retry();
      }
      return;
    }
    if (!v.isInitialized) return;
    final progressing = v.position != _lastPosition;
    _lastPosition = v.position;
    if (progressing) {
      _stalledTicks = 0;
      if (_stalled) setState(() => _stalled = false);
      // Chaîne programmée : si la vidéo a pris du retard (connexion lente), on la recale sur l'horaire.
      final expected = widget.startAt?.call();
      if (expected != null && (v.position - expected).abs() > const Duration(seconds: 12) && expected < v.duration) {
        video.seekTo(expected);
      }
      return;
    }
    final manualPause = !v.isPlaying && !v.isBuffering && !v.isCompleted;
    if (manualPause) {
      _stalledTicks = 0;
      if (_stalled) setState(() => _stalled = false);
      return;
    }
    _stalledTicks++;
    if (_stalledTicks >= 2) {
      if (!_stalled) setState(() => _stalled = true);
      video.play();
    }
    if (_stalledTicks >= 5) {
      _stalledTicks = 0;
      _retry();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final video = _video;
    if (!widget.isLive || video == null || !video.value.isInitialized) return;
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _wasPlayingBeforeHidden = video.value.isPlaying;
    } else if (state == AppLifecycleState.resumed && _wasPlayingBeforeHidden) {
      // Retour dans l'appli : le direct reprend tout seul.
      _wasPlayingBeforeHidden = false;
      video.play();
    }
  }

  @override
  void didUpdateWidget(HlsVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _disposeControllers();
      _init();
    }
  }

  Future<void> _init() async {
    setState(() => _error = null);
    final uri = Uri.parse(widget.url);
    final video = widget.isFile
        ? VideoPlayerController.file(File(widget.url))
        : VideoPlayerController.networkUrl(
            uri,
            formatHint: uri.path.endsWith('.m3u8') ? VideoFormat.hls : null,
          );
    _video = video;
    try {
      await video.initialize();
      if (!mounted || _video != video) return;
      final start = widget.startAt?.call();
      if (start != null && start > const Duration(seconds: 1) && start < video.value.duration) {
        await video.seekTo(start);
        if (!mounted || _video != video) return;
      }
      _chewie = ChewieController(
        videoPlayerController: video,
        autoPlay: widget.autoPlay,
        isLive: widget.isLive,
        aspectRatio: video.value.aspectRatio > 0 ? video.value.aspectRatio : 16 / 9,
        allowedScreenSleep: false,
        allowMuting: true,
        showOptions: false,
        // Sur le web, le plein écran passe par le lecteur natif du téléphone (bouton dédié).
        allowFullScreen: !kIsWeb,
        showControlsOnInitialize: false,
        // Plein écran en paysage, puis retour au portrait de l'appli.
        deviceOrientationsOnEnterFullScreen: const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
        deviceOrientationsAfterFullScreen: DeviceOrientation.values,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.sunYellow,
          handleColor: Colors.white,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white12,
        ),
        // Direct : pas de message par-dessus l'image, la surveillance ci-dessus s'occupe de tout.
        errorBuilder: (context, message) => widget.isLive ? const SizedBox.shrink() : _ErrorView(onRetry: _retry),
      );
      setState(() {});
      if (widget.autoPlay) widget.onStarted?.call();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _retry() {
    _lastPosition = Duration.zero;
    _stalled = false;
    _disposeControllers();
    _init();
  }

  void _disposeControllers() {
    _chewie?.dispose();
    _video?.dispose();
    _chewie = null;
    _video = null;
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _fullscreenTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _disposeControllers();
    // L'appli reprend l'affichage vertical.
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: _error != null
            ? (widget.isLive ? const _Reconnecting() : _ErrorView(onRetry: _retry))
            : _chewie == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.sunYellow))
                : Listener(
                    // Un toucher sur la vidéo fait apparaître le bouton plein écran.
                    onPointerDown: kIsWeb ? (_) => _revealFullscreen() : null,
                    child: Stack(fit: StackFit.expand, children: [
                      Chewie(controller: _chewie!),
                      if (widget.isLive && _stalled) const IgnorePointer(child: _Reconnecting()),
                      if (kIsWeb)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: IgnorePointer(
                            ignoring: !_showFullscreen,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 300),
                              opacity: _showFullscreen ? 1 : 0,
                              child: Material(
                                color: const Color(0x80000000),
                                shape: const CircleBorder(),
                                child: IconButton(
                                  tooltip: 'Plein écran',
                                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                                  onPressed: requestVideoFullscreen,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
      ),
    );
  }
}

/// Petite coupure du direct : message discret pendant la reconnexion automatique.
class _Reconnecting extends StatelessWidget {
  const _Reconnecting();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Color(0x99000000), borderRadius: BorderRadius.all(Radius.circular(12))),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.sunYellow)),
            SizedBox(height: 8),
            Text('Reconnexion au direct…', style: TextStyle(color: AppColors.mist, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.muted, size: 32),
          const SizedBox(height: 8),
          const Text('Lecture impossible pour le moment', style: TextStyle(color: AppColors.muted)),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
