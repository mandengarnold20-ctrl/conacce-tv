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
    this.onExpand,
    this.expanded = false,
  });

  final String url;
  final String slotKey;
  final Duration Function() position;
  final Duration Function() remaining;
  final String? nextUrl;
  final VoidCallback? onExpand;
  final bool expanded;

  @override
  Widget build(BuildContext context) => HlsVideoPlayer(
        key: ValueKey(slotKey),
        url: url,
        isLive: true,
        startAt: position,
        onExpand: onExpand,
        expanded: expanded,
      );
}
