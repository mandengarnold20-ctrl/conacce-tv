import 'package:flutter/material.dart';

import 'hls_video_player.dart';

/// Applications Android / iOS : lecteur classique.
class TvFileSurface extends StatelessWidget {
  const TvFileSurface({
    super.key,
    required this.url,
    required this.slotKey,
    required this.position,
    required this.remaining,
    this.nextUrl,
    this.localFile,
    this.onExpand,
    this.expanded = false,
  });

  final String url;
  final String slotKey;
  final Duration Function() position;
  final Duration Function() remaining;
  final String? nextUrl;
  /// Vidéo gardée dans le téléphone (appli installée), lue à la place d'internet.
  final String? localFile;
  final VoidCallback? onExpand;
  final bool expanded;

  @override
  Widget build(BuildContext context) => HlsVideoPlayer(
        key: ValueKey('$slotKey|${localFile != null}'),
        url: localFile != null ? Uri.file(localFile!).toString() : url,
        isLive: true,
        startAt: position,
        remaining: remaining,
        onExpand: onExpand,
        expanded: expanded,
      );
}
