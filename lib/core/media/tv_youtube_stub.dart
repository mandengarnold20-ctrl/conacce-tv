import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Applications Android / iOS : la chaîne YouTube programmée se regarde sur le site (version web).
class TvYoutubeSurface extends StatelessWidget {
  const TvYoutubeSurface({super.key, required this.videoId, required this.slotKey, required this.position});

  final String videoId;
  final String slotKey;
  final Duration Function() position;

  @override
  Widget build(BuildContext context) {
    return const AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: Center(child: Text('Programme disponible sur le site Conacce TV', style: TextStyle(color: AppColors.mist))),
      ),
    );
  }
}

bool get tvYoutubeMuted => false;

void tvYoutubeUnmute() {}
