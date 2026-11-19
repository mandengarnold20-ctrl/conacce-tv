import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_colors.dart';

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
  });

  final String url;
  /// [url] est un chemin de fichier téléchargé (lecture hors connexion).
  final bool isFile;
  /// Appelé une fois quand la lecture démarre (statistiques).
  final VoidCallback? onStarted;
  final bool isLive;
  final bool autoPlay;

  @override
  State<HlsVideoPlayer> createState() => _HlsVideoPlayerState();
}

class _HlsVideoPlayerState extends State<HlsVideoPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  Object? _error;
  bool? _wasLandscape;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tant que la vidéo est à l'écran, on autorise la rotation du téléphone.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _wasLandscape = _isLandscape;
    _init();
  }

  /// Téléphone tourné (ou fenêtre plus large que haute), sur un petit écran uniquement.
  bool get _isLandscape {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.width > size.height && size.shortestSide < 600;
  }

  @override
  void didChangeMetrics() {
    final landscape = _isLandscape;
    if (landscape == _wasLandscape) return;
    _wasLandscape = landscape;
    final chewie = _chewie;
    if (chewie == null || !mounted) return;
    // On tourne le téléphone : la vidéo prend tout l'écran ; on le remet droit : retour normal.
    if (landscape && !chewie.isFullScreen) {
      chewie.enterFullScreen();
    } else if (!landscape && chewie.isFullScreen) {
      chewie.exitFullScreen();
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
      _chewie = ChewieController(
        videoPlayerController: video,
        autoPlay: widget.autoPlay,
        isLive: widget.isLive,
        aspectRatio: video.value.aspectRatio > 0 ? video.value.aspectRatio : 16 / 9,
        allowedScreenSleep: false,
        allowMuting: true,
        showOptions: false,
        allowFullScreen: true,
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
        errorBuilder: (context, message) => _ErrorView(onRetry: _retry),
      );
      setState(() {});
      if (widget.autoPlay) widget.onStarted?.call();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _retry() {
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
            ? _ErrorView(onRetry: _retry)
            : _chewie == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.sunYellow))
                : Chewie(controller: _chewie!),
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
